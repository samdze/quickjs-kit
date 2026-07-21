internal import CQuickJS

extension QuickJSEngine {
    internal func propertyValue(
        named name: String,
        on identifier: UInt64
    ) throws -> EngineJavaScriptValue {
        return try withRawValue(for: identifier) { object in
            let raw = name.withCString { JS_GetPropertyStr(context, object, $0) }
            let value = ManagedQuickJSValue(raw, in: context)
            if JS_IsException(raw) != 0 { throw extractException() }
            markPromiseObserved(value)
            return try decodeUntyped(value)
        }
    }

    internal func rawPropertyValue(
        named name: String,
        on identifier: UInt64
    ) throws -> ManagedQuickJSValue {
        return try withRawValue(for: identifier) { object in
            let raw = name.withCString { JS_GetPropertyStr(context, object, $0) }
            let value = ManagedQuickJSValue(raw, in: context)
            if JS_IsException(raw) != 0 { throw extractException() }
            return value
        }
    }

    internal func setProperty(
        named name: String,
        on identifier: UInt64,
        to value: ManagedQuickJSValue
    ) throws {
        try withRawValue(for: identifier) { object in
            let result = name.withCString {
                JS_SetPropertyStr(context, object, $0, JS_DupValue(context, value.raw))
            }
            guard result >= 0 else { throw extractException() }
        }
    }

    internal func hasProperty(named name: String, on identifier: UInt64) throws -> Bool {
        return try withRawValue(for: identifier) { object in
            let atom = name.withCString { JS_NewAtom(context, $0) }
            defer { JS_FreeAtom(context, atom) }
            let result = JS_HasProperty(context, object, atom)
            guard result >= 0 else { throw extractException() }
            return result != 0
        }
    }

    internal func deleteProperty(named name: String, on identifier: UInt64) throws -> Bool {
        return try withRawValue(for: identifier) { object in
            let atom = name.withCString { JS_NewAtom(context, $0) }
            defer { JS_FreeAtom(context, atom) }
            let result = JS_DeleteProperty(context, object, atom, Int32(JS_PROP_THROW))
            guard result >= 0 else { throw extractException() }
            return result != 0
        }
    }

    internal func ownEnumerablePropertyNames(of identifier: UInt64) throws -> [String] {
        return try withRawValue(for: identifier) { object in
            try ownEnumerablePropertyNames(of: object)
        }
    }

    internal func ownEnumerablePropertyNames(of object: JSValue) throws -> [String] {
            var table: UnsafeMutablePointer<JSPropertyEnum>?
            var count: UInt32 = 0
            let flags = Int32(JS_GPN_STRING_MASK | JS_GPN_ENUM_ONLY)
            guard JS_GetOwnPropertyNames(context, &table, &count, object, flags) >= 0 else {
                throw extractException()
            }
            guard let table else { return [] }
            defer { JS_FreePropertyEnum(context, table, count) }

            var names: [String] = []
            names.reserveCapacity(Int(count))
            for index in 0..<Int(count) {
                let atom = table[index].atom
                guard let pointer = JS_AtomToCString(context, atom) else {
                    throw extractException()
                }
                defer { JS_FreeCString(context, pointer) }
                names.append(String(cString: pointer))
            }
            return names
    }

    internal func arrayLength(_ identifier: UInt64) throws -> Int {
        let value = try rawPropertyValue(named: "length", on: identifier)
        var result: Int64 = 0
        guard JS_ToInt64(context, &result, value.raw) == 0,
              let count = Int(exactly: result), count >= 0 else {
            if JS_HasException(context) != 0 { throw extractException() }
            throw JavaScriptError(kind: .conversion, message: "Invalid JavaScript array length.")
        }
        return count
    }

    internal func arrayValue(at index: Int, in identifier: UInt64) throws -> EngineJavaScriptValue {
        let value = try rawArrayValue(at: index, in: identifier)
        markPromiseObserved(value)
        return try decodeUntyped(value)
    }

    internal func rawArrayValue(at index: Int, in identifier: UInt64) throws -> ManagedQuickJSValue {
        guard index >= 0, let index = UInt32(exactly: index) else {
            throw JavaScriptError(kind: .conversion, message: "Array indices must fit UInt32.")
        }
        return try withRawValue(for: identifier) { array in
            let raw = JS_GetPropertyUint32(context, array, index)
            let value = ManagedQuickJSValue(raw, in: context)
            if JS_IsException(raw) != 0 { throw extractException() }
            return value
        }
    }

    internal func setArrayValue(
        _ value: ManagedQuickJSValue,
        at index: Int,
        in identifier: UInt64
    ) throws {
        guard index >= 0, let index = UInt32(exactly: index) else {
            throw JavaScriptError(kind: .conversion, message: "Array indices must fit UInt32.")
        }
        try withRawValue(for: identifier) { array in
            let result = JS_SetPropertyUint32(
                context,
                array,
                index,
                JS_DupValue(context, value.raw)
            )
            guard result >= 0 else { throw extractException() }
        }
    }

    internal func call(
        _ functionIdentifier: UInt64,
        receiverIdentifier: UInt64?,
        arguments: [ManagedQuickJSValue]
    ) throws -> EngineJavaScriptValue {
        let result = try callRaw(
            functionIdentifier,
            receiverIdentifier: receiverIdentifier,
            arguments: arguments
        )
        markPromiseObserved(result)
        return try decodeUntyped(result)
    }

    internal func callRaw(
        _ functionIdentifier: UInt64,
        receiverIdentifier: UInt64?,
        arguments: [ManagedQuickJSValue]
    ) throws -> ManagedQuickJSValue {
        return try withRawValue(for: functionIdentifier) { function in
            let invoke: (JSValue) throws -> ManagedQuickJSValue = { receiver in
                var rawArguments = arguments.map(\.raw)
                let raw = rawArguments.withUnsafeMutableBufferPointer { buffer in
                    JS_Call(
                        self.context,
                        function,
                        receiver,
                        Int32(buffer.count),
                        buffer.baseAddress
                    )
                }
                let result = ManagedQuickJSValue(raw, in: self.context)
                if JS_IsException(raw) != 0 { throw self.extractException() }
                return result
            }

            if let receiverIdentifier {
                return try withRawValue(for: receiverIdentifier, invoke)
            }
            return try invoke(quickJSUndefined())
        }
    }
}
