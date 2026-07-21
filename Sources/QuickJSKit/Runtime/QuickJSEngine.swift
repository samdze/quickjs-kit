internal import CQuickJS

internal struct RegisteredJavaScriptReference {
    internal let identifier: UInt64
    internal let kind: JavaScriptReferenceKind
}

internal enum EngineJavaScriptValue {
    case detached(JavaScriptValue)
    case reference(RegisteredJavaScriptReference)
}

internal struct EngineModuleSource {
    internal let source: String
    internal let sourceURL: String
}

internal final class RegisteredSwiftModule {
    internal let specifier: String
    internal let exports: [String: ManagedQuickJSValue]
    internal let bindingIdentifiers: [UInt64]

    internal init(
        specifier: String,
        exports: [String: ManagedQuickJSValue],
        bindingIdentifiers: [UInt64]
    ) {
        self.specifier = specifier
        self.exports = exports
        self.bindingIdentifiers = bindingIdentifiers
    }
}

/// The only layer permitted to manipulate QuickJS pointers and owned values.
internal final class QuickJSEngine {
    internal enum InterruptionReason {
        case cancelled
        case timeout
        case custom
    }

    private struct ActiveExecution {
        internal let deadline: ContinuousClock.Instant?
        internal let sourceURL: String?
        internal var interruptionReason: InterruptionReason?
    }

    internal let runtime: OpaquePointer
    internal let context: OpaquePointer
    internal let maximumJavaScriptStackSize: Int

    private let callbackBridge: QuickJSCallbackBridge

    private var nextReferenceIdentifier: UInt64 = 1
    private var references: [UInt64: StoredQuickJSValue] = [:]
    private var identifiersByObjectAddress: [UInt: UInt64] = [:]
    internal var nextBindingIdentifier: UInt64 = 1
    internal var nextOperationIdentifier: UInt64 = 1
    internal var swiftBindings: [UInt64: RegisteredSwiftBinding] = [:]
    internal var currentGlobalBindings: [String: UInt64] = [:]
    internal var pendingSwiftPromises: [UInt64: PendingSwiftPromise] = [:]
    internal var nextHostWaiterIdentifier: UInt64 = 1
    internal var hostPromiseWaiters: [UInt64: HostPromiseWaiter] = [:]
    internal var unhandledRejections: [UInt: ManagedQuickJSValue] = [:]
    internal var observedPromiseAddresses: [UInt: Int] = [:]
    internal var unhandledRejectionHandler: (@Sendable (JavaScriptError) -> Void)?
    internal var callbackDepth = 0
    internal var interruptHandler: (@Sendable () -> Bool)?

    private let defaultExecutionTimeout: Duration?
    private var executionDepth = 0
    private var activeExecution: ActiveExecution?
    internal var stackTopRefreshCountForTesting = 0
    internal var checkpointCountForTesting = 0
    internal var moduleSources: [String: EngineModuleSource] = [:]
    internal var nativeModuleSpecifiers: Set<String> = []
    internal var moduleResolver: (@Sendable (JavaScriptModuleRequest) throws -> String)?
    internal var missingModuleRequest: JavaScriptModuleRequest?
    internal var normalizedModuleRequests: [String: JavaScriptModuleRequest] = [:]
    internal var moduleCompilationStarted = false
    internal var nextTransientModuleIdentifier: UInt64 = 1
    internal var swiftModules: [UInt: RegisteredSwiftModule] = [:]
    internal var preloadedModuleSpecifiers: Set<String> = []

    internal init(configuration: JavaScriptRuntime.Configuration) throws {
        let memoryLimit = try Self.platformSize(
            configuration.memoryLimit,
            label: "memory limit"
        )
        let maximumStackSize = try Self.platformSize(
            configuration.maximumStackSize,
            label: "maximum stack size"
        )

        guard let runtime = JS_NewRuntime() else {
            throw JavaScriptError(
                kind: .resourceLimit,
                message: "QuickJS could not allocate a runtime."
            )
        }

        if let memoryLimit { JS_SetMemoryLimit(runtime, memoryLimit) }
        if let maximumStackSize { JS_SetMaxStackSize(runtime, maximumStackSize) }

        guard let context = JS_NewContext(runtime) else {
            JS_FreeRuntime(runtime)
            throw JavaScriptError(
                kind: .resourceLimit,
                message: "QuickJS could not allocate a JavaScript context."
            )
        }

        let callbackBridge = QuickJSCallbackBridge()
        self.runtime = runtime
        self.context = context
        self.maximumJavaScriptStackSize = maximumStackSize ?? Int(JS_DEFAULT_STACK_SIZE)
        self.defaultExecutionTimeout = configuration.defaultExecutionTimeout
        self.callbackBridge = callbackBridge
        callbackBridge.engine = self
        JS_SetRuntimeOpaque(
            runtime,
            Unmanaged.passUnretained(callbackBridge).toOpaque()
        )
        JS_SetHostPromiseRejectionTracker(
            runtime,
            quickJSKitPromiseRejectionTracker,
            Unmanaged.passUnretained(callbackBridge).toOpaque()
        )
        JS_SetInterruptHandler(
            runtime,
            quickJSKitInterruptHandler,
            Unmanaged.passUnretained(callbackBridge).toOpaque()
        )
        JS_SetModuleLoaderFunc(
            runtime,
            quickJSKitModuleNormalizer,
            quickJSKitModuleLoader,
            Unmanaged.passUnretained(callbackBridge).toOpaque()
        )
    }

    deinit {
        JS_UpdateStackTop(runtime)
        JS_SetHostPromiseRejectionTracker(runtime, nil, nil)
        JS_SetInterruptHandler(runtime, nil, nil)
        JS_SetModuleLoaderFunc(runtime, nil, nil, nil)
        JS_SetRuntimeOpaque(runtime, nil)
        swiftModules.removeAll()
        removeAllBindingsForTeardown()
        references.removeAll()
        identifiersByObjectAddress.removeAll()
        JS_FreeContext(context)
        JS_FreeRuntime(runtime)
    }

    internal var retainedReferenceCount: Int { references.count }

    internal func memoryUsage(allocationLimit: UInt64?) -> JavaScriptMemoryUsage {
        prepareForEngineCall()
        var usage = JSMemoryUsage()
        JS_ComputeMemoryUsage(runtime, &usage)
        return JavaScriptMemoryUsage(
            allocatedBytes: UInt64(max(0, usage.malloc_size)),
            allocationLimit: allocationLimit,
            usedBytes: UInt64(max(0, usage.memory_used_size))
        )
    }

    internal func collectGarbage() {
        prepareForEngineCall()
        JS_RunGC(runtime)
    }

    internal func prepareForEngineCall() {
        // Swift actors serialize access but do not provide OS-thread affinity.
        // A callback is nested inside an already prepared QuickJS entry. Moving
        // the stack top deeper while JavaScript frames are active corrupts the
        // engine's overflow baseline.
        if callbackDepth == 0, executionDepth == 0 { JS_UpdateStackTop(runtime) }
    }

    internal func withExecution<Result>(
        options: JavaScriptExecutionOptions,
        sourceURL: String? = nil,
        checkpoint: Bool = true,
        _ operation: () throws -> Result
    ) throws -> Result {
        guard executionDepth == 0 else { return try operation() }

        JS_UpdateStackTop(runtime)
        stackTopRefreshCountForTesting += 1
        let timeout: Duration?
        switch options.timeout {
        case .runtimeDefault:
            timeout = defaultExecutionTimeout
        case .disabled:
            timeout = nil
        case let .after(duration):
            timeout = duration
        }
        activeExecution = ActiveExecution(
            deadline: timeout.map { ContinuousClock.now.advanced(by: $0) },
            sourceURL: sourceURL,
            interruptionReason: nil
        )
        executionDepth = 1
        defer {
            executionDepth = 0
            activeExecution = nil
        }

        do {
            let result = try operation()
            if checkpoint { try drainPendingJobs() }
            if let reason = activeExecution?.interruptionReason {
                throw interruptionError(reason, sourceURL: sourceURL)
            }
            return result
        } catch {
            if let reason = activeExecution?.interruptionReason {
                clearPendingException()
                throw interruptionError(reason, sourceURL: sourceURL)
            }
            throw error
        }
    }

    internal func shouldInterrupt() -> Bool {
        guard activeExecution != nil else { return false }
        if withUnsafeCurrentTask(body: { $0?.isCancelled == true }) {
            activeExecution?.interruptionReason = .cancelled
            return true
        }
        if let deadline = activeExecution?.deadline, ContinuousClock.now >= deadline {
            activeExecution?.interruptionReason = .timeout
            return true
        }
        if interruptHandler?() == true {
            activeExecution?.interruptionReason = .custom
            return true
        }
        return false
    }

    private func interruptionError(
        _ reason: InterruptionReason,
        sourceURL: String?
    ) -> JavaScriptError {
        switch reason {
        case .cancelled:
            JavaScriptError(
                kind: .cancelled,
                name: "CancellationError",
                message: "JavaScript execution was cancelled.",
                sourceURL: sourceURL
            )
        case .timeout:
            JavaScriptError(
                kind: .timeout,
                message: "JavaScript execution exceeded its deadline.",
                sourceURL: sourceURL
            )
        case .custom:
            JavaScriptError(
                kind: .interrupted,
                message: "JavaScript execution was interrupted by the host.",
                sourceURL: sourceURL
            )
        }
    }

    internal func evaluate(
        _ source: String,
        sourceURL: String
    ) throws -> EngineJavaScriptValue {
        let result = try evaluateRaw(source, sourceURL: sourceURL)
        return try decodeUntyped(result, sourceURL: sourceURL)
    }

    internal func evaluateRaw(
        _ source: String,
        sourceURL: String
    ) throws -> ManagedQuickJSValue {
        prepareForEngineCall()
        let sourceByteCount = source.utf8.count
        let rawResult = source.withCString { sourcePointer in
            sourceURL.withCString { sourceURLPointer in
                JS_Eval(
                    context,
                    sourcePointer,
                    sourceByteCount,
                    sourceURLPointer,
                    Int32(JS_EVAL_TYPE_GLOBAL)
                )
            }
        }
        let result = ManagedQuickJSValue(rawResult, in: context)
        if JS_IsException(result.raw) != 0 {
            throw extractException(sourceURL: sourceURL)
        }
        return result
    }

    internal func decodeUntyped(
        _ value: ManagedQuickJSValue,
        sourceURL: String? = nil
    ) throws -> EngineJavaScriptValue {
        if JS_IsUndefined(value.raw) != 0 { return .detached(.undefined) }
        if JS_IsNull(value.raw) != 0 { return .detached(.null) }
        if JS_IsBool(value.raw) != 0 {
            let result = JS_ToBool(context, value.raw)
            guard result >= 0 else { throw extractException(sourceURL: sourceURL) }
            return .detached(JavaScriptValue(result != 0))
        }
        if JS_IsNumber(value.raw) != 0 {
            var result = 0.0
            guard JS_ToFloat64(context, &result, value.raw) == 0 else {
                throw extractException(sourceURL: sourceURL)
            }
            return .detached(JavaScriptValue(result))
        }
        if JS_IsString(value.raw) != 0, let string = string(from: value.raw) {
            return .detached(JavaScriptValue(string))
        }
        if JS_IsBigInt(context, value.raw) != 0,
           let representation = string(from: value.raw),
           let bigInt = JavaScriptBigInt(representation) {
            return .detached(JavaScriptValue(bigInt))
        }
        if JS_IsObject(value.raw) != 0 {
            return .reference(register(value.raw))
        }
        if JS_IsSymbol(value.raw) != 0 {
            throw JavaScriptError(
                kind: .conversion,
                message: "JavaScript symbols are not supported.",
                sourceURL: sourceURL
            )
        }
        throw JavaScriptError(
            kind: .conversion,
            message: "QuickJSKit could not represent the JavaScript result.",
            sourceURL: sourceURL
        )
    }

    internal func releaseReference(_ identifier: UInt64) {
        guard let stored = references[identifier] else { return }
        if stored.isPromise { unmarkPromiseObserved(at: stored.objectAddress) }
        stored.clientCount -= 1
        guard stored.clientCount == 0 else { return }
        identifiersByObjectAddress.removeValue(forKey: stored.objectAddress)
        references.removeValue(forKey: identifier)
    }

    internal func withRawValue<Result>(
        for identifier: UInt64,
        _ body: (JSValue) throws -> Result
    ) throws -> Result {
        if identifier == 0 {
            let global = ManagedQuickJSValue(JS_GetGlobalObject(context), in: context)
            return try body(global.raw)
        }
        guard let stored = references[identifier] else {
            throw JavaScriptError(
                kind: .runtime,
                message: "The JavaScript value is no longer available."
            )
        }
        return try body(stored.raw)
    }

    internal func duplicateValue(for identifier: UInt64) throws -> ManagedQuickJSValue {
        try withRawValue(for: identifier) { raw in
            ManagedQuickJSValue(JS_DupValue(context, raw), in: context)
        }
    }

    internal func materialize(_ value: JavaScriptValue) throws -> ManagedQuickJSValue {
        switch value.storage {
        case .undefined:
            ManagedQuickJSValue(quickJSUndefined(), in: context)
        case .null:
            ManagedQuickJSValue(quickJSNull(), in: context)
        case let .boolean(value):
            ManagedQuickJSValue(JS_NewBool(context, value ? 1 : 0), in: context)
        case let .number(value):
            ManagedQuickJSValue(JS_NewFloat64(context, value), in: context)
        case let .string(value):
            newString(value)
        case let .bigInt(value):
            try newBigInt(value)
        case let .reference(reference):
            try duplicateValue(for: reference.identifier)
        }
    }

    internal func newString(_ value: String) -> ManagedQuickJSValue {
        let raw = value.withCString { pointer in
            JS_NewStringLen(context, pointer, value.utf8.count)
        }
        return ManagedQuickJSValue(raw, in: context)
    }

    internal func newBigInt(_ value: JavaScriptBigInt) throws -> ManagedQuickJSValue {
        if let signed = Int64(value.description) {
            return ManagedQuickJSValue(JS_NewBigInt64(context, signed), in: context)
        }
        if let unsigned = UInt64(value.description) {
            return ManagedQuickJSValue(JS_NewBigUint64(context, unsigned), in: context)
        }

        // Parsing a canonical literal avoids depending on the mutable global
        // `BigInt` binding. The representation has already been validated as
        // an optional sign followed only by decimal digits.
        let source = value.description + "n"
        let raw = source.withCString { sourcePointer in
            JS_Eval(
                context,
                sourcePointer,
                source.utf8.count,
                "<QuickJSKit BigInt>",
                Int32(JS_EVAL_TYPE_GLOBAL)
            )
        }
        let result = ManagedQuickJSValue(raw, in: context)
        if JS_IsException(raw) != 0 { throw extractException() }
        return result
    }

    internal func string(from value: JSValue) -> String? {
        var byteCount = 0
        guard let pointer = JS_ToCStringLen2(context, &byteCount, value, 0) else {
            return nil
        }
        defer { JS_FreeCString(context, pointer) }
        return String(
            decoding: UnsafeRawBufferPointer(start: pointer, count: byteCount),
            as: UTF8.self
        )
    }

    internal func extractException(sourceURL: String? = nil) -> JavaScriptError {
        let exception = ManagedQuickJSValue(JS_GetException(context), in: context)
        let rendered = string(from: exception.raw) ?? "JavaScript execution failed."
        let name = propertyString(named: "name", on: exception.raw)
        let message = propertyString(named: "message", on: exception.raw) ?? rendered
        let stack = propertyString(named: "stack", on: exception.raw)

        let kind: JavaScriptError.Kind
        if name == "SyntaxError" {
            kind = .syntax
        } else if name == "InternalError" && message.lowercased().contains("memory") {
            kind = .resourceLimit
        } else {
            kind = .exception
        }
        return JavaScriptError(
            kind: kind,
            name: name,
            message: message,
            stack: stack,
            sourceURL: sourceURL
        )
    }

    internal func clearPendingException() {
        guard JS_HasException(context) != 0 else { return }
        _ = ManagedQuickJSValue(JS_GetException(context), in: context)
    }

    private func register(_ raw: JSValue) -> RegisteredJavaScriptReference {
        let address = quickJSObjectAddress(raw)
        if let identifier = identifiersByObjectAddress[address],
           let stored = references[identifier] {
            stored.clientCount += 1
            return RegisteredJavaScriptReference(
                identifier: identifier,
                kind: stored.kind
            )
        }

        let identifier = nextReferenceIdentifier
        nextReferenceIdentifier &+= 1
        let kind: JavaScriptReferenceKind
        if JS_IsFunction(context, raw) != 0 {
            kind = .function
        } else if JS_IsArray(context, raw) != 0 {
            kind = .array
        } else {
            kind = .object
        }
        let stored = StoredQuickJSValue(
            raw: JS_DupValue(context, raw),
            context: context,
            objectAddress: address,
            kind: kind,
            isPromise: promiseStateRaw(raw) != nil
        )
        references[identifier] = stored
        identifiersByObjectAddress[address] = identifier
        return RegisteredJavaScriptReference(identifier: identifier, kind: kind)
    }

    private func propertyString(named name: String, on object: JSValue) -> String? {
        let raw = name.withCString { JS_GetPropertyStr(context, object, $0) }
        let property = ManagedQuickJSValue(raw, in: context)
        guard JS_IsException(raw) == 0, JS_IsString(raw) != 0 else { return nil }
        return withExtendedLifetime(property) { string(from: raw) }
    }

    private static func platformSize(_ value: UInt64?, label: String) throws -> Int? {
        guard let value else { return nil }
        guard let result = Int(exactly: value) else {
            throw JavaScriptError(
                kind: .resourceLimit,
                message: "The \(label) does not fit this platform's address space."
            )
        }
        return result
    }

    private func promiseStateRaw(_ raw: JSValue) -> UInt32? {
        let state = JS_PromiseState(context, raw).rawValue
        return state <= 2 ? state : nil
    }
}

internal final class ManagedQuickJSValue {
    internal let raw: JSValue
    private let context: OpaquePointer

    internal init(_ raw: JSValue, in context: OpaquePointer) {
        self.raw = raw
        self.context = context
    }

    deinit { JS_FreeValue(context, raw) }
}

private final class StoredQuickJSValue {
    fileprivate let raw: JSValue
    fileprivate let context: OpaquePointer
    fileprivate let objectAddress: UInt
    fileprivate let kind: JavaScriptReferenceKind
    fileprivate let isPromise: Bool
    fileprivate var clientCount = 1

    fileprivate init(
        raw: JSValue,
        context: OpaquePointer,
        objectAddress: UInt,
        kind: JavaScriptReferenceKind,
        isPromise: Bool
    ) {
        self.raw = raw
        self.context = context
        self.objectAddress = objectAddress
        self.kind = kind
        self.isPromise = isPromise
    }

    deinit { JS_FreeValue(context, raw) }
}
