internal import CQuickJS

internal struct RegisteredJavaScriptReference {
    internal let identifier: UInt64
    internal let kind: JavaScriptReferenceKind
}

internal enum EngineJavaScriptValue {
    case detached(JavaScriptValue)
    case reference(RegisteredJavaScriptReference)
}

/// The only layer permitted to manipulate QuickJS pointers and owned values.
internal final class QuickJSEngine {
    internal let runtime: OpaquePointer
    internal let context: OpaquePointer

    private var nextReferenceIdentifier: UInt64 = 1
    private var references: [UInt64: StoredQuickJSValue] = [:]
    private var identifiersByObjectAddress: [UInt: UInt64] = [:]

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

        self.runtime = runtime
        self.context = context
    }

    deinit {
        JS_UpdateStackTop(runtime)
        references.removeAll()
        identifiersByObjectAddress.removeAll()
        JS_FreeContext(context)
        JS_FreeRuntime(runtime)
    }

    internal var retainedReferenceCount: Int { references.count }

    internal func prepareForEngineCall() {
        // Swift actors serialize access but do not provide OS-thread affinity.
        JS_UpdateStackTop(runtime)
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
                message: "JavaScript symbols are not supported in Phase 2.",
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
            kind: kind
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
    fileprivate var clientCount = 1

    fileprivate init(
        raw: JSValue,
        context: OpaquePointer,
        objectAddress: UInt,
        kind: JavaScriptReferenceKind
    ) {
        self.raw = raw
        self.context = context
        self.objectAddress = objectAddress
        self.kind = kind
    }

    deinit { JS_FreeValue(context, raw) }
}
