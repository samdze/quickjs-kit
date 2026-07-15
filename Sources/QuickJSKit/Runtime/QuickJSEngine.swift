internal import CQuickJS

/// The only layer permitted to manipulate QuickJS pointers and owned values.
///
/// This type is deliberately not `Sendable`. Its enclosing
/// ``JavaScriptRuntime`` actor supplies the synchronization guarantee.
internal final class QuickJSEngine {
    private let runtime: OpaquePointer
    private let context: OpaquePointer

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

        if let memoryLimit {
            JS_SetMemoryLimit(runtime, memoryLimit)
        }
        if let maximumStackSize {
            JS_SetMaxStackSize(runtime, maximumStackSize)
        }

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
        // The context must be released before its owning runtime.
        JS_UpdateStackTop(runtime)
        JS_FreeContext(context)
        JS_FreeRuntime(runtime)
    }

    internal func evaluate(
        _ source: String,
        sourceURL: String
    ) throws -> JavaScriptValue {
        // Actors serialize access but may resume on a different OS thread.
        // QuickJS uses this address for native stack-overflow checks.
        JS_UpdateStackTop(runtime)

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
        let result = OwnedQuickJSValue(rawResult, in: context)

        if JS_IsException(result.raw) != 0 {
            throw extractException(sourceURL: sourceURL)
        }

        return try decodePrimitive(result, sourceURL: sourceURL)
    }

    private func decodePrimitive(
        _ value: borrowing OwnedQuickJSValue,
        sourceURL: String
    ) throws -> JavaScriptValue {
        if JS_IsUndefined(value.raw) != 0 {
            return .undefined
        }
        if JS_IsNull(value.raw) != 0 {
            return .null
        }
        if JS_IsBool(value.raw) != 0 {
            let result = JS_ToBool(context, value.raw)
            guard result >= 0 else {
                throw extractException(sourceURL: sourceURL)
            }
            return JavaScriptValue(result != 0)
        }
        if JS_IsNumber(value.raw) != 0 {
            var result = 0.0
            guard JS_ToFloat64(context, &result, value.raw) == 0 else {
                throw extractException(sourceURL: sourceURL)
            }
            return JavaScriptValue(result)
        }
        if JS_IsString(value.raw) != 0,
           let result = string(from: value.raw) {
            return JavaScriptValue(result)
        }

        throw JavaScriptError(
            kind: .conversion,
            message: "Phase 1 can return only undefined, null, boolean, number, and string values.",
            sourceURL: sourceURL
        )
    }

    private func extractException(sourceURL: String) -> JavaScriptError {
        let exception = OwnedQuickJSValue(JS_GetException(context), in: context)
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

    private func propertyString(named name: String, on object: JSValue) -> String? {
        let rawProperty = name.withCString { namePointer in
            JS_GetPropertyStr(context, object, namePointer)
        }
        let property = OwnedQuickJSValue(rawProperty, in: context)
        guard JS_IsException(property.raw) == 0,
              JS_IsString(property.raw) != 0 else {
            return nil
        }
        return string(from: property.raw)
    }

    private func string(from value: JSValue) -> String? {
        var byteCount = 0
        guard let pointer = JS_ToCStringLen2(context, &byteCount, value, 0) else {
            return nil
        }
        defer { JS_FreeCString(context, pointer) }

        let bytes = UnsafeRawBufferPointer(start: pointer, count: byteCount)
        return String(decoding: bytes, as: UTF8.self)
    }

    private static func platformSize(
        _ value: UInt64?,
        label: String
    ) throws -> Int? {
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

/// A +1 QuickJS value whose reference is released at the end of its lexical
/// lifetime. Noncopyability prevents accidental double-free bugs.
private struct OwnedQuickJSValue: ~Copyable {
    fileprivate let raw: JSValue
    private let context: OpaquePointer

    fileprivate init(_ raw: JSValue, in context: OpaquePointer) {
        self.raw = raw
        self.context = context
    }

    deinit {
        JS_FreeValue(context, raw)
    }
}
