internal import CQuickJS
internal import Foundation

extension QuickJSEngine {
    internal func decode<T: Decodable>(
        _ type: T.Type,
        from value: ManagedQuickJSValue,
        maximumNestingDepth: Int
    ) throws -> T {
        prepareForEngineCall()
        guard maximumNestingDepth > 0 else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: [],
                    debugDescription: "maximumNestingDepth must be greater than zero."
                )
            )
        }
        return try decodeValue(
            type,
            from: value,
            codingPath: [],
            depth: 0,
            maximumNestingDepth: maximumNestingDepth
        )
    }

    fileprivate func decodeValue<T: Decodable>(
        _ type: T.Type,
        from value: ManagedQuickJSValue,
        codingPath: [any CodingKey],
        depth: Int,
        maximumNestingDepth: Int
    ) throws -> T {
        if type == Data.self {
            return try cast(decodeData(from: value.raw, codingPath: codingPath), to: type)
        }
        if type == Date.self {
            return try cast(decodeDate(from: value.raw, codingPath: codingPath), to: type)
        }
        if type == URL.self {
            return try cast(decodeURL(from: value.raw, codingPath: codingPath), to: type)
        }
        if type == JavaScriptBigInt.self {
            return try cast(decodeBigInt(from: value.raw, codingPath: codingPath), to: type)
        }

        let decoder = JavaScriptValueDecoderImplementation(
            engine: self,
            value: value,
            codingPath: codingPath,
            depth: depth,
            maximumNestingDepth: maximumNestingDepth
        )
        return try T(from: decoder)
    }

    fileprivate func decodeInteger<T: FixedWidthInteger>(
        _ type: T.Type,
        from raw: JSValue,
        codingPath: [any CodingKey]
    ) throws -> T {
        if JS_IsNumber(raw) != 0 {
            var number = 0.0
            guard JS_ToFloat64(context, &number, raw) == 0 else {
                throw extractException()
            }
            guard number.isFinite,
                  number.rounded(.towardZero) == number,
                  abs(number) <= Double(JavaScriptValue.maximumSafeInteger),
                  let result = T(exactly: number) else {
                throw DecodingError.dataCorrupted(
                    .init(
                        codingPath: codingPath,
                        debugDescription: "Expected an exactly representable \(T.self)."
                    )
                )
            }
            return result
        }
        if JS_IsBigInt(context, raw) != 0,
           let representation = string(from: raw) {
            if T.isSigned,
               let signed = Int64(representation),
               let result = T(exactly: signed) {
                return result
            }
            if !T.isSigned,
               let unsigned = UInt64(representation),
               let result = T(exactly: unsigned) {
                return result
            }
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: codingPath,
                    debugDescription: "JavaScript bigint is outside the range of \(T.self)."
                )
            )
        }
        throw typeMismatch(type, codingPath: codingPath, expected: "an integer number or bigint")
    }

    fileprivate func decodeBool(
        from raw: JSValue,
        codingPath: [any CodingKey]
    ) throws -> Bool {
        guard JS_IsBool(raw) != 0 else {
            throw typeMismatch(Bool.self, codingPath: codingPath, expected: "a boolean")
        }
        let value = JS_ToBool(context, raw)
        guard value >= 0 else { throw extractException() }
        return value != 0
    }

    fileprivate func decodeString(
        from raw: JSValue,
        codingPath: [any CodingKey]
    ) throws -> String {
        guard JS_IsString(raw) != 0, let value = string(from: raw) else {
            throw typeMismatch(String.self, codingPath: codingPath, expected: "a string")
        }
        return value
    }

    fileprivate func decodeDouble(
        from raw: JSValue,
        codingPath: [any CodingKey]
    ) throws -> Double {
        guard JS_IsNumber(raw) != 0 else {
            throw typeMismatch(Double.self, codingPath: codingPath, expected: "a number")
        }
        var value = 0.0
        guard JS_ToFloat64(context, &value, raw) == 0 else { throw extractException() }
        return value
    }

    fileprivate func decodeFloat(
        from raw: JSValue,
        codingPath: [any CodingKey]
    ) throws -> Float {
        let double = try decodeDouble(from: raw, codingPath: codingPath)
        let value = Float(double)
        guard !value.isInfinite || double.isInfinite else {
            throw dataCorrupted(codingPath, "Number is outside the range of Float.")
        }
        return value
    }

    fileprivate func decodeData(
        from raw: JSValue,
        codingPath: [any CodingKey]
    ) throws -> Data {
        var byteCount = 0
        if let pointer = JS_GetArrayBuffer(context, &byteCount, raw) {
            return Data(bytes: pointer, count: byteCount)
        }
        if JS_HasException(context) == 0 {
            return Data()
        }
        clearPendingException()

        var offset = 0
        var length = 0
        let bufferRaw = JS_GetTypedArrayBuffer(
            context,
            raw,
            &offset,
            &length,
            nil
        )
        if JS_IsException(bufferRaw) == 0 {
            let buffer = ManagedQuickJSValue(bufferRaw, in: context)
            var bufferLength = 0
            guard let pointer = JS_GetArrayBuffer(context, &bufferLength, buffer.raw),
                  offset <= bufferLength,
                  length <= bufferLength - offset else {
                if JS_HasException(context) != 0 { throw extractException() }
                throw dataCorrupted(codingPath, "Typed-array view has invalid byte bounds.")
            }
            return Data(bytes: pointer.advanced(by: offset), count: length)
        }
        clearPendingException()

        if JS_IsArray(context, raw) != 0 {
            let count = try arrayLength(of: raw, codingPath: codingPath)
            var bytes: [UInt8] = []
            bytes.reserveCapacity(count)
            for index in 0..<count {
                let element = ManagedQuickJSValue(
                    JS_GetPropertyUint32(context, raw, UInt32(index)),
                    in: context
                )
                if JS_IsException(element.raw) != 0 { throw extractException() }
                bytes.append(
                    try decodeInteger(
                        UInt8.self,
                        from: element.raw,
                        codingPath: codingPath + [JavaScriptIndexCodingKey(index: index)]
                    )
                )
            }
            return Data(bytes)
        }

        throw typeMismatch(
            Data.self,
            codingPath: codingPath,
            expected: "an ArrayBuffer, typed-array view, or byte array"
        )
    }

    fileprivate func decodeDate(
        from raw: JSValue,
        codingPath: [any CodingKey]
    ) throws -> Date {
        if JS_IsNumber(raw) != 0 {
            let milliseconds = try decodeDouble(from: raw, codingPath: codingPath)
            guard milliseconds.isFinite else {
                throw dataCorrupted(codingPath, "Date milliseconds must be finite.")
            }
            return Date(timeIntervalSince1970: milliseconds / 1_000)
        }
        if JS_IsString(raw) != 0 {
            let representation = try decodeString(from: raw, codingPath: codingPath)
            guard let date = ISO8601DateFormatter().date(from: representation) else {
                throw dataCorrupted(codingPath, "Expected an ISO-8601 date string.")
            }
            return date
        }
        if JS_IsObject(raw) != 0 {
            let methodRaw = "getTime".withCString {
                JS_GetPropertyStr(context, raw, $0)
            }
            let method = ManagedQuickJSValue(methodRaw, in: context)
            if JS_IsException(method.raw) != 0 { throw extractException() }
            if JS_IsFunction(context, method.raw) != 0 {
                let result = ManagedQuickJSValue(
                    JS_Call(context, method.raw, raw, 0, nil),
                    in: context
                )
                if JS_IsException(result.raw) != 0 { throw extractException() }
                let milliseconds = try decodeDouble(from: result.raw, codingPath: codingPath)
                guard milliseconds.isFinite else {
                    throw dataCorrupted(codingPath, "JavaScript Date is invalid.")
                }
                return Date(timeIntervalSince1970: milliseconds / 1_000)
            }
        }
        throw typeMismatch(Date.self, codingPath: codingPath, expected: "a Date, Unix milliseconds, or ISO-8601 string")
    }

    fileprivate func decodeURL(
        from raw: JSValue,
        codingPath: [any CodingKey]
    ) throws -> URL {
        let representation: String
        if JS_IsString(raw) != 0 {
            representation = try decodeString(from: raw, codingPath: codingPath)
        } else if JS_IsObject(raw) != 0 {
            let hrefRaw = "href".withCString { JS_GetPropertyStr(context, raw, $0) }
            let href = ManagedQuickJSValue(hrefRaw, in: context)
            if JS_IsException(href.raw) != 0 { throw extractException() }
            representation = try decodeString(
                from: href.raw,
                codingPath: codingPath + [JavaScriptStringCodingKey("href")]
            )
        } else {
            throw typeMismatch(URL.self, codingPath: codingPath, expected: "a URL string or object with href")
        }
        guard let url = URL(string: representation) else {
            throw dataCorrupted(codingPath, "Expected a valid URL representation.")
        }
        return url
    }

    fileprivate func decodeBigInt(
        from raw: JSValue,
        codingPath: [any CodingKey]
    ) throws -> JavaScriptBigInt {
        guard JS_IsBigInt(context, raw) != 0,
              let representation = string(from: raw),
              let value = JavaScriptBigInt(representation) else {
            throw typeMismatch(JavaScriptBigInt.self, codingPath: codingPath, expected: "a bigint")
        }
        return value
    }

    fileprivate func arrayLength(
        of raw: JSValue,
        codingPath: [any CodingKey]
    ) throws -> Int {
        let lengthRaw = "length".withCString { JS_GetPropertyStr(context, raw, $0) }
        let length = ManagedQuickJSValue(lengthRaw, in: context)
        if JS_IsException(length.raw) != 0 { throw extractException() }
        return try decodeInteger(Int.self, from: length.raw, codingPath: codingPath)
    }

    fileprivate func typeMismatch<T>(
        _ type: T.Type,
        codingPath: [any CodingKey],
        expected: String
    ) -> DecodingError {
        DecodingError.typeMismatch(
            type,
            .init(codingPath: codingPath, debugDescription: "Expected \(expected).")
        )
    }

    fileprivate func dataCorrupted(
        _ codingPath: [any CodingKey],
        _ description: String
    ) -> DecodingError {
        DecodingError.dataCorrupted(
            .init(codingPath: codingPath, debugDescription: description)
        )
    }

    private func cast<Value, Result>(_ value: Value, to type: Result.Type) throws -> Result {
        guard let result = value as? Result else {
            throw JavaScriptError(
                kind: .internalFailure,
                message: "QuickJSKit failed an internal special-type cast."
            )
        }
        return result
    }
}

private final class JavaScriptValueDecoderImplementation: Decoder {
    fileprivate let engine: QuickJSEngine
    fileprivate let value: ManagedQuickJSValue
    fileprivate let codingPath: [any CodingKey]
    fileprivate let depth: Int
    fileprivate let maximumNestingDepth: Int
    fileprivate var userInfo: [CodingUserInfoKey: Any] { [:] }

    fileprivate init(
        engine: QuickJSEngine,
        value: ManagedQuickJSValue,
        codingPath: [any CodingKey],
        depth: Int,
        maximumNestingDepth: Int
    ) {
        self.engine = engine
        self.value = value
        self.codingPath = codingPath
        self.depth = depth
        self.maximumNestingDepth = maximumNestingDepth
    }

    fileprivate func container<Key: CodingKey>(
        keyedBy type: Key.Type
    ) throws -> KeyedDecodingContainer<Key> {
        let containerDepth = try checkedContainerDepth()
        guard JS_IsObject(value.raw) != 0,
              JS_IsArray(engine.context, value.raw) == 0,
              JS_IsFunction(engine.context, value.raw) == 0 else {
            throw engine.typeMismatch(
                [String: Any].self,
                codingPath: codingPath,
                expected: "an object with own enumerable properties"
            )
        }
        let names = try engine.ownEnumerablePropertyNames(of: value.raw)
        return KeyedDecodingContainer(
            JavaScriptKeyedDecodingContainer(
                decoder: self,
                propertyNames: Set(names),
                containerDepth: containerDepth
            )
        )
    }

    fileprivate func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let containerDepth = try checkedContainerDepth()
        guard JS_IsArray(engine.context, value.raw) != 0 else {
            throw engine.typeMismatch([Any].self, codingPath: codingPath, expected: "an array")
        }
        return JavaScriptUnkeyedDecodingContainer(
            decoder: self,
            count: try engine.arrayLength(of: value.raw, codingPath: codingPath),
            containerDepth: containerDepth
        )
    }

    fileprivate func singleValueContainer() throws -> any SingleValueDecodingContainer {
        JavaScriptSingleValueDecodingContainer(decoder: self)
    }

    fileprivate func decode<T: Decodable>(
        _ type: T.Type,
        from value: ManagedQuickJSValue,
        at path: [any CodingKey],
        depth: Int
    ) throws -> T {
        try engine.decodeValue(
            type,
            from: value,
            codingPath: path,
            depth: depth,
            maximumNestingDepth: maximumNestingDepth
        )
    }

    fileprivate func child(
        value: ManagedQuickJSValue,
        path: [any CodingKey],
        depth: Int
    ) -> JavaScriptValueDecoderImplementation {
        JavaScriptValueDecoderImplementation(
            engine: engine,
            value: value,
            codingPath: path,
            depth: depth,
            maximumNestingDepth: maximumNestingDepth
        )
    }

    private func checkedContainerDepth() throws -> Int {
        let next = depth + 1
        guard next <= maximumNestingDepth else {
            throw DecodingError.dataCorrupted(
                .init(
                    codingPath: codingPath,
                    debugDescription: "JavaScript decoding exceeded maximumNestingDepth (\(maximumNestingDepth))."
                )
            )
        }
        return next
    }
}

private struct JavaScriptKeyedDecodingContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    fileprivate let decoder: JavaScriptValueDecoderImplementation
    fileprivate let propertyNames: Set<String>
    fileprivate let containerDepth: Int
    fileprivate var codingPath: [any CodingKey] { decoder.codingPath }
    fileprivate var allKeys: [Key] { propertyNames.compactMap(Key.init(stringValue:)) }

    fileprivate func contains(_ key: Key) -> Bool { propertyNames.contains(key.stringValue) }

    fileprivate func decodeNil(forKey key: Key) throws -> Bool {
        guard contains(key) else { return true }
        let value = try property(for: key)
        return JS_IsNull(value.raw) != 0 || JS_IsUndefined(value.raw) != 0
    }

    fileprivate func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try decoder.engine.decodeBool(from: property(for: key).raw, codingPath: path(key)) }
    fileprivate func decode(_ type: String.Type, forKey key: Key) throws -> String { try decoder.engine.decodeString(from: property(for: key).raw, codingPath: path(key)) }
    fileprivate func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decoder.engine.decodeDouble(from: property(for: key).raw, codingPath: path(key)) }
    fileprivate func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try decoder.engine.decodeFloat(from: property(for: key).raw, codingPath: path(key)) }
    fileprivate func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try integer(type, key) }
    fileprivate func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try integer(type, key) }
    fileprivate func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try integer(type, key) }
    fileprivate func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try integer(type, key) }
    fileprivate func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try integer(type, key) }
    fileprivate func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try integer(type, key) }
    fileprivate func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try integer(type, key) }
    fileprivate func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try integer(type, key) }
    fileprivate func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try integer(type, key) }
    fileprivate func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try integer(type, key) }

    fileprivate func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        let value = try property(for: key)
        return try decoder.decode(type, from: value, at: path(key), depth: containerDepth)
    }

    fileprivate func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> {
        try decoder.child(value: property(for: key), path: path(key), depth: containerDepth).container(keyedBy: type)
    }

    fileprivate func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try decoder.child(value: property(for: key), path: path(key), depth: containerDepth).unkeyedContainer()
    }

    fileprivate func superDecoder() throws -> any Decoder {
        try superDecoder(forKey: Key(stringValue: "super")!)
    }

    fileprivate func superDecoder(forKey key: Key) throws -> any Decoder {
        decoder.child(value: try property(for: key), path: path(key), depth: containerDepth)
    }

    private func property(for key: Key) throws -> ManagedQuickJSValue {
        guard contains(key) else {
            throw DecodingError.keyNotFound(
                key,
                .init(codingPath: codingPath, debugDescription: "No value associated with key \(key.stringValue).")
            )
        }
        let raw = key.stringValue.withCString {
            JS_GetPropertyStr(decoder.engine.context, decoder.value.raw, $0)
        }
        let value = ManagedQuickJSValue(raw, in: decoder.engine.context)
        if JS_IsException(raw) != 0 { throw decoder.engine.extractException() }
        return value
    }

    private func path(_ key: Key) -> [any CodingKey] { codingPath + [key] }

    private func integer<T: FixedWidthInteger>(_ type: T.Type, _ key: Key) throws -> T {
        try decoder.engine.decodeInteger(type, from: property(for: key).raw, codingPath: path(key))
    }

}

private struct JavaScriptUnkeyedDecodingContainer: UnkeyedDecodingContainer {
    fileprivate let decoder: JavaScriptValueDecoderImplementation
    fileprivate let count: Int?
    fileprivate let containerDepth: Int
    fileprivate var currentIndex = 0
    fileprivate var codingPath: [any CodingKey] { decoder.codingPath }
    fileprivate var isAtEnd: Bool { currentIndex >= (count ?? 0) }

    fileprivate mutating func decodeNil() throws -> Bool {
        let value = try next()
        if JS_IsNull(value.raw) != 0 || JS_IsUndefined(value.raw) != 0 {
            currentIndex += 1
            return true
        }
        return false
    }

    fileprivate mutating func decode(_ type: Bool.Type) throws -> Bool {
        let engine = decoder.engine
        return try consume { try engine.decodeBool(from: $0.raw, codingPath: $1) }
    }
    fileprivate mutating func decode(_ type: String.Type) throws -> String {
        let engine = decoder.engine
        return try consume { try engine.decodeString(from: $0.raw, codingPath: $1) }
    }
    fileprivate mutating func decode(_ type: Double.Type) throws -> Double {
        let engine = decoder.engine
        return try consume { try engine.decodeDouble(from: $0.raw, codingPath: $1) }
    }
    fileprivate mutating func decode(_ type: Float.Type) throws -> Float {
        let engine = decoder.engine
        return try consume { value, path in
            try engine.decodeFloat(from: value.raw, codingPath: path)
        }
    }
    fileprivate mutating func decode(_ type: Int.Type) throws -> Int { try integer(type) }
    fileprivate mutating func decode(_ type: Int8.Type) throws -> Int8 { try integer(type) }
    fileprivate mutating func decode(_ type: Int16.Type) throws -> Int16 { try integer(type) }
    fileprivate mutating func decode(_ type: Int32.Type) throws -> Int32 { try integer(type) }
    fileprivate mutating func decode(_ type: Int64.Type) throws -> Int64 { try integer(type) }
    fileprivate mutating func decode(_ type: UInt.Type) throws -> UInt { try integer(type) }
    fileprivate mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try integer(type) }
    fileprivate mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try integer(type) }
    fileprivate mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try integer(type) }
    fileprivate mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try integer(type) }

    fileprivate mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let value = try next()
        let path = currentPath
        defer { currentIndex += 1 }
        return try decoder.decode(type, from: value, at: path, depth: containerDepth)
    }

    fileprivate mutating func nestedContainer<NestedKey: CodingKey>(keyedBy type: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> {
        let child = try nextChild()
        return try child.container(keyedBy: type)
    }

    fileprivate mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        try nextChild().unkeyedContainer()
    }

    fileprivate mutating func superDecoder() throws -> any Decoder { try nextChild() }

    private var currentPath: [any CodingKey] { codingPath + [JavaScriptIndexCodingKey(index: currentIndex)] }

    private func next() throws -> ManagedQuickJSValue {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                Any.self,
                .init(codingPath: codingPath, debugDescription: "Unkeyed container is at end.")
            )
        }
        let raw = JS_GetPropertyUint32(decoder.engine.context, decoder.value.raw, UInt32(currentIndex))
        let value = ManagedQuickJSValue(raw, in: decoder.engine.context)
        if JS_IsException(raw) != 0 { throw decoder.engine.extractException() }
        return value
    }

    private mutating func consume<Result>(
        _ body: (ManagedQuickJSValue, [any CodingKey]) throws -> Result
    ) throws -> Result {
        let value = try next()
        let path = currentPath
        defer { currentIndex += 1 }
        return try body(value, path)
    }

    private mutating func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let engine = decoder.engine
        return try consume { try engine.decodeInteger(type, from: $0.raw, codingPath: $1) }
    }

    private mutating func nextChild() throws -> JavaScriptValueDecoderImplementation {
        let value = try next()
        let path = currentPath
        currentIndex += 1
        return decoder.child(value: value, path: path, depth: containerDepth)
    }
}

private struct JavaScriptSingleValueDecodingContainer: SingleValueDecodingContainer {
    fileprivate let decoder: JavaScriptValueDecoderImplementation
    fileprivate var codingPath: [any CodingKey] { decoder.codingPath }

    fileprivate func decodeNil() -> Bool { JS_IsNull(decoder.value.raw) != 0 || JS_IsUndefined(decoder.value.raw) != 0 }
    fileprivate func decode(_ type: Bool.Type) throws -> Bool { try decoder.engine.decodeBool(from: decoder.value.raw, codingPath: codingPath) }
    fileprivate func decode(_ type: String.Type) throws -> String { try decoder.engine.decodeString(from: decoder.value.raw, codingPath: codingPath) }
    fileprivate func decode(_ type: Double.Type) throws -> Double { try decoder.engine.decodeDouble(from: decoder.value.raw, codingPath: codingPath) }
    fileprivate func decode(_ type: Float.Type) throws -> Float { try decoder.engine.decodeFloat(from: decoder.value.raw, codingPath: codingPath) }
    fileprivate func decode(_ type: Int.Type) throws -> Int { try integer(type) }
    fileprivate func decode(_ type: Int8.Type) throws -> Int8 { try integer(type) }
    fileprivate func decode(_ type: Int16.Type) throws -> Int16 { try integer(type) }
    fileprivate func decode(_ type: Int32.Type) throws -> Int32 { try integer(type) }
    fileprivate func decode(_ type: Int64.Type) throws -> Int64 { try integer(type) }
    fileprivate func decode(_ type: UInt.Type) throws -> UInt { try integer(type) }
    fileprivate func decode(_ type: UInt8.Type) throws -> UInt8 { try integer(type) }
    fileprivate func decode(_ type: UInt16.Type) throws -> UInt16 { try integer(type) }
    fileprivate func decode(_ type: UInt32.Type) throws -> UInt32 { try integer(type) }
    fileprivate func decode(_ type: UInt64.Type) throws -> UInt64 { try integer(type) }

    fileprivate func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try decoder.decode(type, from: decoder.value, at: codingPath, depth: decoder.depth)
    }

    private func integer<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        try decoder.engine.decodeInteger(type, from: decoder.value.raw, codingPath: codingPath)
    }
}

internal struct JavaScriptStringCodingKey: CodingKey {
    internal let stringValue: String
    internal let intValue: Int? = nil
    internal init(_ value: String) { stringValue = value }
    internal init?(stringValue: String) { self.init(stringValue) }
    internal init?(intValue: Int) { return nil }
}
