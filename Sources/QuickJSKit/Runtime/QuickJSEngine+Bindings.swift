internal import CQuickJS

internal enum BindingInvocation {
    case synchronous(ManagedQuickJSValue)
    case asynchronous(@Sendable () async -> BindingCompletion)
}

internal struct BindingResult: Sendable {
    internal let encode: @Sendable (QuickJSEngine) throws -> ManagedQuickJSValue
}

internal enum BindingCompletion: Sendable {
    case success(BindingResult)
    case failure(any Error)
}

internal typealias BindingSettlement = @Sendable (
    UInt64,
    BindingCompletion
) async -> Void

internal struct BoundFunction {
    internal let description: BindingDescription
    internal let invoke: @Sendable (
        QuickJSEngine,
        [ManagedQuickJSValue]
    ) throws -> BindingInvocation
    internal let settle: BindingSettlement
}

internal struct BindingDefinition: Sendable {
    internal let draft: BindingDraft
    internal let invoke: @Sendable (
        QuickJSEngine,
        [ManagedQuickJSValue]
    ) throws -> BindingInvocation

    internal func bind(
        location: BindingDescription.Location,
        order: UInt64,
        settle: @escaping BindingSettlement
    ) -> BoundFunction {
        BoundFunction(
            description: draft.finalize(location: location, order: order),
            invoke: invoke,
            settle: settle
        )
    }
}

internal final class RegisteredBinding {
    internal let identifier: UInt64
    internal let name: String
    internal let function: BoundFunction?
    internal let root: (any AnyObject & Sendable)?
    internal var exposedValue: ManagedQuickJSValue?
    internal var isActive = true
    internal var activeOperations: Set<UInt64> = []
    internal var childBindingIdentifiers: [UInt64] = []

    internal init(
        identifier: UInt64,
        name: String,
        function: BoundFunction?,
        root: (any AnyObject & Sendable)? = nil
    ) {
        self.identifier = identifier
        self.name = name
        self.function = function
        self.root = root
    }
}

internal struct PendingSwiftPromise {
    internal let bindingIdentifier: UInt64
    internal let resolve: ManagedQuickJSValue
    internal let reject: ManagedQuickJSValue
    internal var task: Task<Void, Never>?
}

internal final class HostPromiseWaiter {
    internal let promise: ManagedQuickJSValue
    internal let poll: (QuickJSEngine, ManagedQuickJSValue) -> Bool
    internal let cancel: (QuickJSEngine) -> Void

    internal init(
        promise: ManagedQuickJSValue,
        poll: @escaping (QuickJSEngine, ManagedQuickJSValue) -> Bool,
        cancel: @escaping (QuickJSEngine) -> Void
    ) {
        self.promise = promise
        self.poll = poll
        self.cancel = cancel
    }
}

extension QuickJSEngine {
    private static var maximumBindingIdentifier: UInt64 { 9_007_199_254_740_991 }

    internal func registerGlobalBinding(
        named name: String,
        function: BoundFunction
    ) throws -> (UInt64, EngineJavaScriptValue) {
        let identifier = try allocateBindingIdentifier()
        let record = RegisteredBinding(
            identifier: identifier,
            name: name,
            function: function
        )
        swiftBindings[identifier] = record

        do {
            let function = try makeBoundFunction(
                bindingIdentifier: identifier,
                name: name,
                length: function.description.parameters.count
            )
            record.exposedValue = ManagedQuickJSValue(
                JS_DupValue(context, function.raw),
                in: context
            )
            let global = ManagedQuickJSValue(JS_GetGlobalObject(context), in: context)
            let status = name.withCString {
                JS_SetPropertyStr(context, global.raw, $0, JS_DupValue(context, function.raw))
            }
            guard status >= 0 else { throw extractException() }
            currentGlobalBindings[name] = identifier
            return (identifier, try decodeUntyped(function))
        } catch {
            swiftBindings.removeValue(forKey: identifier)
            throw error
        }
    }

    internal func isBindingActive(_ identifier: UInt64) -> Bool {
        swiftBindings[identifier]?.isActive == true
    }

    internal func removeBinding(
        _ identifier: UInt64,
        cancellingInFlight: Bool
    ) throws -> Bool {
        guard let binding = swiftBindings[identifier], binding.isActive else { return false }
        binding.isActive = false

        for childIdentifier in binding.childBindingIdentifiers {
            _ = try removeBinding(childIdentifier, cancellingInFlight: cancellingInFlight)
        }

        if currentGlobalBindings[binding.name] == identifier {
            let global = ManagedQuickJSValue(JS_GetGlobalObject(context), in: context)
            let property = binding.name.withCString {
                JS_GetPropertyStr(context, global.raw, $0)
            }
            let current = ManagedQuickJSValue(property, in: context)
            if JS_IsException(property) != 0 { throw extractException() }
            if let exposed = binding.exposedValue,
               JS_StrictEq(context, current.raw, exposed.raw) != 0 {
                let atom = binding.name.withCString { JS_NewAtom(context, $0) }
                defer { JS_FreeAtom(context, atom) }
                let status = JS_DeleteProperty(context, global.raw, atom, Int32(JS_PROP_THROW))
                guard status >= 0 else { throw extractException() }
            }
            currentGlobalBindings.removeValue(forKey: binding.name)
        }

        if cancellingInFlight {
            for operationIdentifier in Array(binding.activeOperations) {
                cancelSwiftPromise(operationIdentifier)
            }
        }
        discardBindingIfFinished(binding)
        return true
    }

    internal func registerExport(
        named name: String,
        root: any AnyObject & Sendable,
        members: [JavaScriptExportMemberDefinition],
        settle: @escaping BindingSettlement
    ) throws -> (UInt64, EngineJavaScriptValue) {
        guard !BindingValidation.hasDuplicateNames(members.map(\.name)) else {
            throw JavaScriptError(
                kind: .conversion,
                message: "An export cannot contain duplicate member names."
            )
        }

        let exportIdentifier = try allocateBindingIdentifier()
        let exportRecord = RegisteredBinding(
            identifier: exportIdentifier,
            name: name,
            function: nil,
            root: root
        )
        swiftBindings[exportIdentifier] = exportRecord
        var createdChildren: [UInt64] = []

        do {
            let object = ManagedQuickJSValue(JS_NewObject(context), in: context)
            if JS_IsException(object.raw) != 0 { throw extractException() }
            for (memberOrder, member) in members.enumerated() {
                switch member.storage {
                case let .function(definition):
                    let childIdentifier = try allocateBindingIdentifier()
                    let boundFunction = definition.bind(
                        location: .objectExport(name: name),
                        order: UInt64(memberOrder),
                        settle: settle
                    )
                    let child = RegisteredBinding(
                        identifier: childIdentifier,
                        name: member.name,
                        function: boundFunction,
                        root: root
                    )
                    swiftBindings[childIdentifier] = child
                    createdChildren.append(childIdentifier)
                    let rawFunction = try makeBoundFunction(
                        bindingIdentifier: childIdentifier,
                        name: member.name,
                        length: boundFunction.description.parameters.count
                    )
                    child.exposedValue = ManagedQuickJSValue(
                        JS_DupValue(context, rawFunction.raw),
                        in: context
                    )
                    try defineProperty(
                        member.name,
                        on: object.raw,
                        value: rawFunction.raw,
                        flags: 0
                    )
                case let .value(encode):
                    let value = try encode(self)
                    try defineProperty(
                        member.name,
                        on: object.raw,
                        value: value.raw,
                        flags: Int32(JS_PROP_ENUMERABLE)
                    )
                case let .liveValue(value):
                    let materialized = try materialize(value)
                    try defineProperty(
                        member.name,
                        on: object.raw,
                        value: materialized.raw,
                        flags: Int32(JS_PROP_ENUMERABLE)
                    )
                }
            }
            exportRecord.childBindingIdentifiers = createdChildren
            exportRecord.exposedValue = ManagedQuickJSValue(
                JS_DupValue(context, object.raw),
                in: context
            )
            let global = ManagedQuickJSValue(JS_GetGlobalObject(context), in: context)
            let status = name.withCString {
                JS_SetPropertyStr(context, global.raw, $0, JS_DupValue(context, object.raw))
            }
            guard status >= 0 else { throw extractException() }
            currentGlobalBindings[name] = exportIdentifier
            return (exportIdentifier, try decodeUntyped(object))
        } catch {
            for identifier in createdChildren { swiftBindings.removeValue(forKey: identifier) }
            swiftBindings.removeValue(forKey: exportIdentifier)
            throw error
        }
    }

    internal func settleSwiftPromise(
        _ operationIdentifier: UInt64,
        with result: Result<ManagedQuickJSValue, any Error>
    ) {
        guard let pending = pendingSwiftPromises.removeValue(forKey: operationIdentifier) else {
            return
        }
        let argument: ManagedQuickJSValue
        let function: ManagedQuickJSValue
        switch result {
        case let .success(value):
            argument = value
            function = pending.resolve
        case let .failure(error):
            argument = makeJavaScriptError(from: error)
            function = pending.reject
        }
        _ = callRawFunction(function.raw, arguments: [argument.raw])
        finishOperation(operationIdentifier, bindingIdentifier: pending.bindingIdentifier)
    }

    internal func cancelSwiftPromise(_ operationIdentifier: UInt64) {
        guard let pending = pendingSwiftPromises.removeValue(forKey: operationIdentifier) else {
            return
        }
        pending.task?.cancel()
        let error = makeJavaScriptError(from: CancellationError())
        _ = callRawFunction(pending.reject.raw, arguments: [error.raw])
        finishOperation(operationIdentifier, bindingIdentifier: pending.bindingIdentifier)
    }

    internal func drainPendingJobs() throws {
        checkpointCountForTesting += 1
        var jobContext: OpaquePointer?
        while true {
            let status = JS_ExecutePendingJob(runtime, &jobContext)
            if status == 0 {
                pollHostPromiseWaiters()
                reportUnhandledRejections()
                return
            }
            if status < 0 { throw extractException() }
        }
    }

    internal func removeAllBindingsForTeardown() {
        for operationIdentifier in Array(pendingSwiftPromises.keys) {
            pendingSwiftPromises[operationIdentifier]?.task?.cancel()
        }
        pendingSwiftPromises.removeAll()
        for waiter in hostPromiseWaiters.values { waiter.cancel(self) }
        hostPromiseWaiters.removeAll()
        swiftBindings.removeAll()
        currentGlobalBindings.removeAll()
        unhandledRejections.removeAll()
        observedPromiseAddresses.removeAll()
    }

    internal func promiseState(of value: ManagedQuickJSValue) -> UInt32? {
        let state = JS_PromiseState(context, value.raw).rawValue
        return state <= 2 ? state : nil
    }

    internal func promiseResult(of promise: ManagedQuickJSValue) -> ManagedQuickJSValue {
        ManagedQuickJSValue(JS_PromiseResult(context, promise.raw), in: context)
    }

    internal func markPromiseObserved(_ value: ManagedQuickJSValue) {
        guard promiseState(of: value) != nil else { return }
        let address = quickJSObjectAddress(value.raw)
        observedPromiseAddresses[address, default: 0] += 1
        unhandledRejections.removeValue(forKey: address)
    }

    internal func unmarkPromiseObserved(_ value: ManagedQuickJSValue) {
        guard promiseState(of: value) != nil else { return }
        unmarkPromiseObserved(at: quickJSObjectAddress(value.raw))
    }

    internal func unmarkPromiseObserved(at address: UInt) {
        guard let count = observedPromiseAddresses[address] else { return }
        if count <= 1 {
            observedPromiseAddresses.removeValue(forKey: address)
        } else {
            observedPromiseAddresses[address] = count - 1
        }
    }

    internal func recordPromiseRejection(
        promise: JSValue,
        reason: JSValue,
        isHandled: Bool
    ) {
        let address = quickJSObjectAddress(promise)
        if isHandled || observedPromiseAddresses[address] != nil {
            unhandledRejections.removeValue(forKey: address)
            return
        }
        unhandledRejections[address] = ManagedQuickJSValue(
            JS_DupValue(context, reason),
            in: context
        )
    }

    internal func allocateHostWaiterIdentifier() -> UInt64 {
        defer { nextHostWaiterIdentifier &+= 1 }
        return nextHostWaiterIdentifier
    }

    internal func installHostPromiseWaiter(
        _ waiter: HostPromiseWaiter,
        identifier: UInt64
    ) {
        hostPromiseWaiters[identifier] = waiter
        pollHostPromiseWaiters()
    }

    internal func cancelHostPromiseWaiter(_ identifier: UInt64) {
        guard let waiter = hostPromiseWaiters.removeValue(forKey: identifier) else { return }
        waiter.cancel(self)
    }

    internal func errorFromRejectedPromise(_ promise: ManagedQuickJSValue) -> JavaScriptError {
        let reason = promiseResult(of: promise)
        return errorFromRejectionReason(reason)
    }

    private func errorFromRejectionReason(_ reason: ManagedQuickJSValue) -> JavaScriptError {
        let rendered = string(from: reason.raw) ?? "A JavaScript promise was rejected."
        let name = propertyStringForBinding(named: "name", on: reason.raw)
        let message = propertyStringForBinding(named: "message", on: reason.raw) ?? rendered
        let stack = propertyStringForBinding(named: "stack", on: reason.raw)
        return JavaScriptError(
            kind: name == "CancellationError" ? .cancelled : .exception,
            name: name,
            message: message,
            stack: stack
        )
    }

    fileprivate func invokeBinding(
        identifier: UInt64,
        arguments: UnsafeMutablePointer<JSValue>?,
        count: Int
    ) -> JSValue {
        let isOutermostCallback = callbackDepth == 0
        if isOutermostCallback {
            // QuickJS's stack limit is measured from the outer JavaScript
            // entry. Swift Codable and generic callback frames are host stack,
            // not recursive JavaScript execution, and can legitimately exceed
            // that budget. Sync callbacks cannot re-enter JavaScript, so pause
            // the engine check while the host thunk runs and restore the exact
            // configured JavaScript limit before returning to QuickJS.
            JS_SetMaxStackSize(runtime, 0)
        }
        callbackDepth += 1
        defer {
            callbackDepth -= 1
            if isOutermostCallback {
                JS_SetMaxStackSize(runtime, maximumJavaScriptStackSize)
            }
        }
        guard let binding = swiftBindings[identifier],
              binding.isActive,
              let function = binding.function else {
            return throwJavaScriptError(
                name: "ReferenceError",
                message: "This Swift binding has been removed."
            )
        }

        let ownedArguments = (0..<count).map { index in
            ManagedQuickJSValue(
                JS_DupValue(context, arguments?[index] ?? quickJSUndefined()),
                in: context
            )
        }
        do {
            switch try function.invoke(self, ownedArguments) {
            case let .synchronous(value):
                return JS_DupValue(context, value.raw)
            case let .asynchronous(operation):
                return try beginSwiftPromise(
                    binding: binding,
                    operation: operation,
                    settle: function.settle
                )
            }
        } catch let decodingError as DecodingError {
            return throwJavaScriptError(
                name: "TypeError",
                message: String(describing: decodingError)
            )
        } catch {
            let value = makeJavaScriptError(from: error)
            return JS_Throw(context, JS_DupValue(context, value.raw))
        }
    }

    private func beginSwiftPromise(
        binding: RegisteredBinding,
        operation: @escaping @Sendable () async -> BindingCompletion,
        settle: @escaping BindingSettlement
    ) throws -> JSValue {
        let operationIdentifier = try allocateOperationIdentifier()
        var resolvingFunctions = [quickJSUndefined(), quickJSUndefined()]
        let promiseRaw = resolvingFunctions.withUnsafeMutableBufferPointer { buffer in
            JS_NewPromiseCapability(context, buffer.baseAddress)
        }
        if JS_IsException(promiseRaw) != 0 { throw extractException() }
        let promise = ManagedQuickJSValue(promiseRaw, in: context)
        let resolve = ManagedQuickJSValue(resolvingFunctions[0], in: context)
        let reject = ManagedQuickJSValue(resolvingFunctions[1], in: context)
        pendingSwiftPromises[operationIdentifier] = PendingSwiftPromise(
            bindingIdentifier: binding.identifier,
            resolve: resolve,
            reject: reject,
            task: nil
        )
        binding.activeOperations.insert(operationIdentifier)
        let task = Task {
            let completion = await operation()
            await settle(operationIdentifier, completion)
        }
        pendingSwiftPromises[operationIdentifier]?.task = task
        return JS_DupValue(context, promise.raw)
    }

    private func finishOperation(_ identifier: UInt64, bindingIdentifier: UInt64) {
        guard let binding = swiftBindings[bindingIdentifier] else { return }
        binding.activeOperations.remove(identifier)
        discardBindingIfFinished(binding)
    }

    private func pollHostPromiseWaiters() {
        var completed: [UInt64] = []
        for (identifier, waiter) in hostPromiseWaiters {
            if waiter.poll(self, waiter.promise) {
                completed.append(identifier)
            }
        }
        for identifier in completed { hostPromiseWaiters.removeValue(forKey: identifier) }
    }

    private func reportUnhandledRejections() {
        guard let handler = unhandledRejectionHandler else {
            unhandledRejections.removeAll()
            return
        }
        let pending = unhandledRejections.sorted { $0.key < $1.key }
        unhandledRejections.removeAll()
        for (_, reason) in pending {
            handler(errorFromRejectionReason(reason))
        }
    }

    private func propertyStringForBinding(named name: String, on object: JSValue) -> String? {
        guard JS_IsObject(object) != 0 else { return nil }
        let raw = name.withCString { JS_GetPropertyStr(context, object, $0) }
        let property = ManagedQuickJSValue(raw, in: context)
        guard JS_IsException(raw) == 0, JS_IsString(raw) != 0 else {
            clearPendingException()
            return nil
        }
        return string(from: property.raw)
    }

    private func discardBindingIfFinished(_ binding: RegisteredBinding) {
        guard !binding.isActive, binding.activeOperations.isEmpty else { return }
        swiftBindings.removeValue(forKey: binding.identifier)
    }

    internal func makeBoundFunction(
        bindingIdentifier: UInt64,
        name: String,
        length: Int
    ) throws -> ManagedQuickJSValue {
        let identifierValue = ManagedQuickJSValue(
            JS_NewInt64(context, Int64(bindingIdentifier)),
            in: context
        )
        var data = [identifierValue.raw]
        let raw = data.withUnsafeMutableBufferPointer { buffer in
            JS_NewCFunctionData(
                context,
                quickJSKitBindingTrampoline,
                Int32(length),
                0,
                1,
                buffer.baseAddress
            )
        }
        let function = ManagedQuickJSValue(raw, in: context)
        if JS_IsException(raw) != 0 { throw extractException() }
        let functionName = newString(name)
        try defineProperty("name", on: function.raw, value: functionName.raw, flags: 0)
        return function
    }

    internal func defineProperty(
        _ name: String,
        on object: JSValue,
        value: JSValue,
        flags: Int32
    ) throws {
        let status = name.withCString {
            JS_DefinePropertyValueStr(
                context,
                object,
                $0,
                JS_DupValue(context, value),
                flags
            )
        }
        guard status >= 0 else { throw extractException() }
    }

    internal func throwJavaScriptError(name: String, message: String) -> JSValue {
        let error = makeJavaScriptError(name: name, message: message, swiftType: nil)
        return JS_Throw(context, JS_DupValue(context, error.raw))
    }

    private func makeJavaScriptError(from error: any Error) -> ManagedQuickJSValue {
        if error is CancellationError {
            return makeJavaScriptError(
                name: "CancellationError",
                message: "The Swift task was cancelled.",
                swiftType: String(reflecting: type(of: error))
            )
        }
        if let error = error as? JavaScriptError {
            return makeJavaScriptError(
                name: error.name ?? "Error",
                message: error.message,
                swiftType: nil
            )
        }
        return makeJavaScriptError(
            name: "SwiftError",
            message: String(describing: error),
            swiftType: String(reflecting: type(of: error))
        )
    }

    private func makeJavaScriptError(
        name: String,
        message: String,
        swiftType: String?
    ) -> ManagedQuickJSValue {
        let error = ManagedQuickJSValue(JS_NewError(context), in: context)
        let nameValue = newString(name)
        let messageValue = newString(message)
        try? defineProperty("name", on: error.raw, value: nameValue.raw, flags: Int32(JS_PROP_CONFIGURABLE))
        try? defineProperty("message", on: error.raw, value: messageValue.raw, flags: Int32(JS_PROP_CONFIGURABLE))
        if let swiftType {
            let swiftTypeValue = newString(swiftType)
            try? defineProperty("swiftType", on: error.raw, value: swiftTypeValue.raw, flags: 0)
        }
        return error
    }

    private func callRawFunction(_ function: JSValue, arguments: [JSValue]) -> Bool {
        var arguments = arguments
        let resultRaw = arguments.withUnsafeMutableBufferPointer { buffer in
            JS_Call(context, function, quickJSUndefined(), Int32(buffer.count), buffer.baseAddress)
        }
        let result = ManagedQuickJSValue(resultRaw, in: context)
        if JS_IsException(result.raw) != 0 {
            clearPendingException()
            return false
        }
        return true
    }

    internal func allocateBindingIdentifier() throws -> UInt64 {
        guard nextBindingIdentifier <= Self.maximumBindingIdentifier else {
            throw JavaScriptError(kind: .resourceLimit, message: "The binding identifier space is exhausted.")
        }
        defer { nextBindingIdentifier += 1 }
        return nextBindingIdentifier
    }

    private func allocateOperationIdentifier() throws -> UInt64 {
        guard nextOperationIdentifier < UInt64.max else {
            throw JavaScriptError(kind: .resourceLimit, message: "The asynchronous operation identifier space is exhausted.")
        }
        defer { nextOperationIdentifier += 1 }
        return nextOperationIdentifier
    }
}

private let quickJSKitBindingTrampoline: @convention(c) (
    OpaquePointer?,
    JSValue,
    Int32,
    UnsafeMutablePointer<JSValue>?,
    Int32,
    UnsafeMutablePointer<JSValue>?
) -> JSValue = { context, _, argumentCount, arguments, _, functionData in
    guard let context,
          let functionData,
          let runtime = JS_GetRuntime(context),
          let opaque = JS_GetRuntimeOpaque(runtime) else {
        return quickJSUndefined()
    }
    let bridge = Unmanaged<QuickJSRuntimeBridge>.fromOpaque(opaque).takeUnretainedValue()
    guard let engine = bridge.engine else { return quickJSUndefined() }
    var identifier: Int64 = 0
    guard JS_ToInt64(context, &identifier, functionData[0]) == 0, identifier > 0 else {
        engine.clearPendingException()
        return quickJSUndefined()
    }
    return engine.invokeBinding(
        identifier: UInt64(identifier),
        arguments: arguments,
        count: Int(argumentCount)
    )
}

internal let quickJSKitPromiseRejectionTracker: @convention(c) (
    OpaquePointer?,
    JSValue,
    JSValue,
    Int32,
    UnsafeMutableRawPointer?
) -> Void = { _, promise, reason, isHandled, opaque in
    guard let opaque else { return }
    let bridge = Unmanaged<QuickJSRuntimeBridge>.fromOpaque(opaque).takeUnretainedValue()
    bridge.engine?.recordPromiseRejection(
        promise: promise,
        reason: reason,
        isHandled: isHandled != 0
    )
}

internal let quickJSKitInterruptHandler: @convention(c) (
    OpaquePointer?,
    UnsafeMutableRawPointer?
) -> Int32 = { _, opaque in
    guard let opaque else { return 0 }
    let bridge = Unmanaged<QuickJSRuntimeBridge>.fromOpaque(opaque).takeUnretainedValue()
    return bridge.engine?.shouldInterrupt() == true ? 1 : 0
}
