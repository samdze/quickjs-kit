internal import CQuickJS
internal import Foundation

extension QuickJSEngine {
    internal func encode<T: Encodable>(
        _ value: T,
        maximumNestingDepth: Int
    ) throws -> ManagedQuickJSValue {
        prepareForEngineCall()
        guard maximumNestingDepth > 0 else {
            throw EncodingError.invalidValue(
                maximumNestingDepth,
                .init(
                    codingPath: [],
                    debugDescription: "maximumNestingDepth must be greater than zero."
                )
            )
        }
        let state = JavaScriptEncodingState()
        let result = try encodeValue(
            value,
            codingPath: [],
            depth: 0,
            maximumNestingDepth: maximumNestingDepth,
            state: state
        )
        try state.throwIfNeeded()
        return result
    }

    fileprivate func encodeValue<T: Encodable>(
        _ value: T,
        codingPath: [any CodingKey],
        depth: Int,
        maximumNestingDepth: Int,
        state: JavaScriptEncodingState
    ) throws -> ManagedQuickJSValue {
        try state.throwIfNeeded()
        if let data = value as? Data { return try newData(data) }
        if let date = value as? Date {
            return try checked(JS_NewDate(context, date.timeIntervalSince1970 * 1_000))
        }
        if let url = value as? URL { return newString(url.absoluteString) }
        if let bigInt = value as? JavaScriptBigInt { return try newBigInt(bigInt) }

        let storage = JavaScriptEncodingStorage()
        let encoder = JavaScriptValueEncoderImplementation(
            engine: self,
            storage: storage,
            state: state,
            codingPath: codingPath,
            depth: depth,
            maximumNestingDepth: maximumNestingDepth
        )
        try value.encode(to: encoder)
        try state.throwIfNeeded()
        guard let encoded = storage.value else {
            throw EncodingError.invalidValue(
                value,
                .init(
                    codingPath: codingPath,
                    debugDescription: "The Encodable value did not produce a JavaScript value."
                )
            )
        }
        return encoded
    }

    fileprivate func newSignedInteger(_ value: Int64) -> ManagedQuickJSValue {
        let limit = Int64(JavaScriptValue.maximumSafeInteger)
        if value >= -limit && value <= limit {
            return ManagedQuickJSValue(JS_NewFloat64(context, Double(value)), in: context)
        }
        return ManagedQuickJSValue(JS_NewBigInt64(context, value), in: context)
    }

    fileprivate func newUnsignedInteger(_ value: UInt64) -> ManagedQuickJSValue {
        if value <= UInt64(JavaScriptValue.maximumSafeInteger) {
            return ManagedQuickJSValue(JS_NewFloat64(context, Double(value)), in: context)
        }
        return ManagedQuickJSValue(JS_NewBigUint64(context, value), in: context)
    }

    fileprivate func newData(_ data: Data) throws -> ManagedQuickJSValue {
        let bufferRaw = data.withUnsafeBytes { bytes in
            JS_NewArrayBufferCopy(
                context,
                bytes.bindMemory(to: UInt8.self).baseAddress,
                bytes.count
            )
        }
        let buffer = try checked(bufferRaw)
        // QuickJS's typed-array constructor reads the optional offset and
        // length slots directly, so the public C entry requires the same
        // three-slot argument padding used by a JavaScript call.
        var arguments = [
            buffer.raw,
            quickJSUndefined(),
            quickJSUndefined(),
        ]
        let raw = arguments.withUnsafeMutableBufferPointer { buffer in
            JS_NewTypedArray(
                context,
                Int32(buffer.count),
                buffer.baseAddress,
                JS_TYPED_ARRAY_UINT8
            )
        }
        return try checked(raw)
    }

    fileprivate func checked(_ raw: JSValue) throws -> ManagedQuickJSValue {
        let value = ManagedQuickJSValue(raw, in: context)
        if JS_IsException(raw) != 0 { throw extractException() }
        return value
    }

    fileprivate func newObject() throws -> ManagedQuickJSValue {
        try checked(JS_NewObject(context))
    }

    fileprivate func newArray() throws -> ManagedQuickJSValue {
        try checked(JS_NewArray(context))
    }

    fileprivate func set(
        _ value: ManagedQuickJSValue,
        forProperty name: String,
        on object: ManagedQuickJSValue
    ) throws {
        let result = name.withCString {
            JS_SetPropertyStr(context, object.raw, $0, JS_DupValue(context, value.raw))
        }
        guard result >= 0 else { throw extractException() }
    }

    fileprivate func set(
        _ value: ManagedQuickJSValue,
        at index: Int,
        on array: ManagedQuickJSValue
    ) throws {
        guard let index = UInt32(exactly: index) else {
            throw JavaScriptError(kind: .conversion, message: "Encoded array is too large.")
        }
        let result = JS_SetPropertyUint32(
            context,
            array.raw,
            index,
            JS_DupValue(context, value.raw)
        )
        guard result >= 0 else { throw extractException() }
    }
}

private final class JavaScriptEncodingState {
    fileprivate var error: (any Error)?

    fileprivate func record(_ error: any Error) {
        if self.error == nil { self.error = error }
    }

    fileprivate func throwIfNeeded() throws {
        if let error { throw error }
    }
}

private final class JavaScriptEncodingStorage {
    fileprivate var value: ManagedQuickJSValue?

    fileprivate func store(
        _ value: ManagedQuickJSValue,
        codingPath: [any CodingKey]
    ) throws {
        guard self.value == nil else {
            throw EncodingError.invalidValue(
                value,
                .init(
                    codingPath: codingPath,
                    debugDescription: "An Encodable value requested more than one container."
                )
            )
        }
        self.value = value
    }
}

private final class JavaScriptValueEncoderImplementation: Encoder {
    fileprivate let engine: QuickJSEngine
    fileprivate let storage: JavaScriptEncodingStorage
    fileprivate let state: JavaScriptEncodingState
    fileprivate let codingPath: [any CodingKey]
    fileprivate let depth: Int
    fileprivate let maximumNestingDepth: Int
    fileprivate var userInfo: [CodingUserInfoKey: Any] { [:] }

    fileprivate init(
        engine: QuickJSEngine,
        storage: JavaScriptEncodingStorage,
        state: JavaScriptEncodingState,
        codingPath: [any CodingKey],
        depth: Int,
        maximumNestingDepth: Int
    ) {
        self.engine = engine
        self.storage = storage
        self.state = state
        self.codingPath = codingPath
        self.depth = depth
        self.maximumNestingDepth = maximumNestingDepth
    }

    fileprivate func container<Key: CodingKey>(
        keyedBy type: Key.Type
    ) -> KeyedEncodingContainer<Key> {
        let nextDepth = depth + 1
        var object: ManagedQuickJSValue
        do {
            try checkDepth(nextDepth)
            object = try engine.newObject()
            try storage.store(object, codingPath: codingPath)
        } catch {
            state.record(error)
            object = ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
        }
        return KeyedEncodingContainer(
            JavaScriptKeyedEncodingContainer(
                encoder: self,
                object: object,
                containerDepth: nextDepth
            )
        )
    }

    fileprivate func unkeyedContainer() -> any UnkeyedEncodingContainer {
        let nextDepth = depth + 1
        var array: ManagedQuickJSValue
        do {
            try checkDepth(nextDepth)
            array = try engine.newArray()
            try storage.store(array, codingPath: codingPath)
        } catch {
            state.record(error)
            array = ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
        }
        return JavaScriptUnkeyedEncodingContainer(
            encoder: self,
            array: array,
            containerDepth: nextDepth
        )
    }

    fileprivate func singleValueContainer() -> any SingleValueEncodingContainer {
        JavaScriptSingleValueEncodingContainer(encoder: self)
    }

    fileprivate func encode<T: Encodable>(
        _ value: T,
        at path: [any CodingKey],
        depth: Int
    ) throws -> ManagedQuickJSValue {
        try engine.encodeValue(
            value,
            codingPath: path,
            depth: depth,
            maximumNestingDepth: maximumNestingDepth,
            state: state
        )
    }

    fileprivate func child(
        at path: [any CodingKey],
        depth: Int
    ) -> JavaScriptValueEncoderImplementation {
        JavaScriptValueEncoderImplementation(
            engine: engine,
            storage: JavaScriptEncodingStorage(),
            state: state,
            codingPath: path,
            depth: depth,
            maximumNestingDepth: maximumNestingDepth
        )
    }

    private func checkDepth(_ depth: Int) throws {
        guard depth <= maximumNestingDepth else {
            throw EncodingError.invalidValue(
                depth,
                .init(
                    codingPath: codingPath,
                    debugDescription: "JavaScript encoding exceeded maximumNestingDepth (\(maximumNestingDepth))."
                )
            )
        }
    }
}

private struct JavaScriptKeyedEncodingContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
    fileprivate let encoder: JavaScriptValueEncoderImplementation
    fileprivate let object: ManagedQuickJSValue
    fileprivate let containerDepth: Int
    fileprivate var codingPath: [any CodingKey] { encoder.codingPath }

    fileprivate mutating func encodeNil(forKey key: Key) throws {
        try set(ManagedQuickJSValue(quickJSNull(), in: encoder.engine.context), for: key)
    }

    fileprivate mutating func encode(_ value: Bool, forKey key: Key) throws {
        try set(ManagedQuickJSValue(JS_NewBool(encoder.engine.context, value ? 1 : 0), in: encoder.engine.context), for: key)
    }

    fileprivate mutating func encode(_ value: String, forKey key: Key) throws { try set(encoder.engine.newString(value), for: key) }
    fileprivate mutating func encode(_ value: Double, forKey key: Key) throws { try set(ManagedQuickJSValue(JS_NewFloat64(encoder.engine.context, value), in: encoder.engine.context), for: key) }
    fileprivate mutating func encode(_ value: Float, forKey key: Key) throws { try encode(Double(value), forKey: key) }
    fileprivate mutating func encode(_ value: Int, forKey key: Key) throws { try set(encoder.engine.newSignedInteger(Int64(value)), for: key) }
    fileprivate mutating func encode(_ value: Int8, forKey key: Key) throws { try set(encoder.engine.newSignedInteger(Int64(value)), for: key) }
    fileprivate mutating func encode(_ value: Int16, forKey key: Key) throws { try set(encoder.engine.newSignedInteger(Int64(value)), for: key) }
    fileprivate mutating func encode(_ value: Int32, forKey key: Key) throws { try set(encoder.engine.newSignedInteger(Int64(value)), for: key) }
    fileprivate mutating func encode(_ value: Int64, forKey key: Key) throws { try set(encoder.engine.newSignedInteger(value), for: key) }
    fileprivate mutating func encode(_ value: UInt, forKey key: Key) throws { try set(encoder.engine.newUnsignedInteger(UInt64(value)), for: key) }
    fileprivate mutating func encode(_ value: UInt8, forKey key: Key) throws { try set(encoder.engine.newUnsignedInteger(UInt64(value)), for: key) }
    fileprivate mutating func encode(_ value: UInt16, forKey key: Key) throws { try set(encoder.engine.newUnsignedInteger(UInt64(value)), for: key) }
    fileprivate mutating func encode(_ value: UInt32, forKey key: Key) throws { try set(encoder.engine.newUnsignedInteger(UInt64(value)), for: key) }
    fileprivate mutating func encode(_ value: UInt64, forKey key: Key) throws { try set(encoder.engine.newUnsignedInteger(value), for: key) }

    fileprivate mutating func encode<T: Encodable>(_ value: T, forKey key: Key) throws {
        try set(encoder.encode(value, at: codingPath + [key], depth: containerDepth), for: key)
    }

    fileprivate mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type,
        forKey key: Key
    ) -> KeyedEncodingContainer<NestedKey> {
        let child = encoder.child(at: codingPath + [key], depth: containerDepth)
        let container = child.container(keyedBy: keyType)
        attach(child, for: key)
        return container
    }

    fileprivate mutating func nestedUnkeyedContainer(forKey key: Key) -> any UnkeyedEncodingContainer {
        let child = encoder.child(at: codingPath + [key], depth: containerDepth)
        let container = child.unkeyedContainer()
        attach(child, for: key)
        return container
    }

    fileprivate mutating func superEncoder() -> any Encoder {
        guard let key = Key(stringValue: "super") else {
            encoder.state.record(
                EncodingError.invalidValue(
                    "super",
                    .init(codingPath: codingPath, debugDescription: "CodingKey cannot represent the super key.")
                )
            )
            return encoder.child(at: codingPath, depth: containerDepth)
        }
        return superEncoder(forKey: key)
    }

    fileprivate mutating func superEncoder(forKey key: Key) -> any Encoder {
        let child = encoder.child(at: codingPath + [key], depth: containerDepth)
        let engine = encoder.engine
        let state = encoder.state
        let object = object
        return JavaScriptReferencingEncoder(child: child) {
            do {
                try state.throwIfNeeded()
                guard let value = child.storage.value else { return }
                try engine.set(value, forProperty: key.stringValue, on: object)
            } catch {
                state.record(error)
            }
        }
    }

    private func set(_ value: ManagedQuickJSValue, for key: Key) throws {
        try encoder.state.throwIfNeeded()
        try encoder.engine.set(value, forProperty: key.stringValue, on: object)
    }

    private func attach(_ child: JavaScriptValueEncoderImplementation, for key: Key) {
        do {
            try child.state.throwIfNeeded()
            if let value = child.storage.value { try set(value, for: key) }
        } catch {
            encoder.state.record(error)
        }
    }
}

private struct JavaScriptUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    fileprivate let encoder: JavaScriptValueEncoderImplementation
    fileprivate let array: ManagedQuickJSValue
    fileprivate let containerDepth: Int
    fileprivate var codingPath: [any CodingKey] { encoder.codingPath }
    fileprivate var count = 0

    fileprivate mutating func encodeNil() throws { try append(ManagedQuickJSValue(quickJSNull(), in: encoder.engine.context)) }
    fileprivate mutating func encode(_ value: Bool) throws { try append(ManagedQuickJSValue(JS_NewBool(encoder.engine.context, value ? 1 : 0), in: encoder.engine.context)) }
    fileprivate mutating func encode(_ value: String) throws { try append(encoder.engine.newString(value)) }
    fileprivate mutating func encode(_ value: Double) throws { try append(ManagedQuickJSValue(JS_NewFloat64(encoder.engine.context, value), in: encoder.engine.context)) }
    fileprivate mutating func encode(_ value: Float) throws { try encode(Double(value)) }
    fileprivate mutating func encode(_ value: Int) throws { try append(encoder.engine.newSignedInteger(Int64(value))) }
    fileprivate mutating func encode(_ value: Int8) throws { try append(encoder.engine.newSignedInteger(Int64(value))) }
    fileprivate mutating func encode(_ value: Int16) throws { try append(encoder.engine.newSignedInteger(Int64(value))) }
    fileprivate mutating func encode(_ value: Int32) throws { try append(encoder.engine.newSignedInteger(Int64(value))) }
    fileprivate mutating func encode(_ value: Int64) throws { try append(encoder.engine.newSignedInteger(value)) }
    fileprivate mutating func encode(_ value: UInt) throws { try append(encoder.engine.newUnsignedInteger(UInt64(value))) }
    fileprivate mutating func encode(_ value: UInt8) throws { try append(encoder.engine.newUnsignedInteger(UInt64(value))) }
    fileprivate mutating func encode(_ value: UInt16) throws { try append(encoder.engine.newUnsignedInteger(UInt64(value))) }
    fileprivate mutating func encode(_ value: UInt32) throws { try append(encoder.engine.newUnsignedInteger(UInt64(value))) }
    fileprivate mutating func encode(_ value: UInt64) throws { try append(encoder.engine.newUnsignedInteger(value)) }

    fileprivate mutating func encode<T: Encodable>(_ value: T) throws {
        let key = JavaScriptIndexCodingKey(index: count)
        try append(encoder.encode(value, at: codingPath + [key], depth: containerDepth))
    }

    fileprivate mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy keyType: NestedKey.Type
    ) -> KeyedEncodingContainer<NestedKey> {
        let key = JavaScriptIndexCodingKey(index: count)
        let child = encoder.child(at: codingPath + [key], depth: containerDepth)
        let container = child.container(keyedBy: keyType)
        attach(child)
        return container
    }

    fileprivate mutating func nestedUnkeyedContainer() -> any UnkeyedEncodingContainer {
        let key = JavaScriptIndexCodingKey(index: count)
        let child = encoder.child(at: codingPath + [key], depth: containerDepth)
        let container = child.unkeyedContainer()
        attach(child)
        return container
    }

    fileprivate mutating func superEncoder() -> any Encoder {
        let key = JavaScriptIndexCodingKey(index: count)
        let index = count
        count += 1
        let child = encoder.child(at: codingPath + [key], depth: containerDepth)
        let engine = encoder.engine
        let state = encoder.state
        let array = array
        return JavaScriptReferencingEncoder(child: child) {
            do {
                try state.throwIfNeeded()
                guard let value = child.storage.value else { return }
                try engine.set(value, at: index, on: array)
            } catch {
                state.record(error)
            }
        }
    }

    private mutating func append(_ value: ManagedQuickJSValue) throws {
        try encoder.state.throwIfNeeded()
        try encoder.engine.set(value, at: count, on: array)
        count += 1
    }

    private mutating func attach(_ child: JavaScriptValueEncoderImplementation) {
        do {
            try child.state.throwIfNeeded()
            if let value = child.storage.value { try append(value) }
        } catch {
            encoder.state.record(error)
        }
    }
}

private struct JavaScriptSingleValueEncodingContainer: SingleValueEncodingContainer {
    fileprivate let encoder: JavaScriptValueEncoderImplementation
    fileprivate var codingPath: [any CodingKey] { encoder.codingPath }

    fileprivate mutating func encodeNil() throws { try store(ManagedQuickJSValue(quickJSNull(), in: encoder.engine.context)) }
    fileprivate mutating func encode(_ value: Bool) throws { try store(ManagedQuickJSValue(JS_NewBool(encoder.engine.context, value ? 1 : 0), in: encoder.engine.context)) }
    fileprivate mutating func encode(_ value: String) throws { try store(encoder.engine.newString(value)) }
    fileprivate mutating func encode(_ value: Double) throws { try store(ManagedQuickJSValue(JS_NewFloat64(encoder.engine.context, value), in: encoder.engine.context)) }
    fileprivate mutating func encode(_ value: Float) throws { try encode(Double(value)) }
    fileprivate mutating func encode(_ value: Int) throws { try store(encoder.engine.newSignedInteger(Int64(value))) }
    fileprivate mutating func encode(_ value: Int8) throws { try store(encoder.engine.newSignedInteger(Int64(value))) }
    fileprivate mutating func encode(_ value: Int16) throws { try store(encoder.engine.newSignedInteger(Int64(value))) }
    fileprivate mutating func encode(_ value: Int32) throws { try store(encoder.engine.newSignedInteger(Int64(value))) }
    fileprivate mutating func encode(_ value: Int64) throws { try store(encoder.engine.newSignedInteger(value)) }
    fileprivate mutating func encode(_ value: UInt) throws { try store(encoder.engine.newUnsignedInteger(UInt64(value))) }
    fileprivate mutating func encode(_ value: UInt8) throws { try store(encoder.engine.newUnsignedInteger(UInt64(value))) }
    fileprivate mutating func encode(_ value: UInt16) throws { try store(encoder.engine.newUnsignedInteger(UInt64(value))) }
    fileprivate mutating func encode(_ value: UInt32) throws { try store(encoder.engine.newUnsignedInteger(UInt64(value))) }
    fileprivate mutating func encode(_ value: UInt64) throws { try store(encoder.engine.newUnsignedInteger(value)) }

    fileprivate mutating func encode<T: Encodable>(_ value: T) throws {
        try store(encoder.encode(value, at: codingPath, depth: encoder.depth))
    }

    private func store(_ value: ManagedQuickJSValue) throws {
        try encoder.state.throwIfNeeded()
        try encoder.storage.store(value, codingPath: codingPath)
    }
}

private final class JavaScriptReferencingEncoder: Encoder {
    private let child: JavaScriptValueEncoderImplementation
    private let attach: () -> Void

    fileprivate var codingPath: [any CodingKey] { child.codingPath }
    fileprivate var userInfo: [CodingUserInfoKey: Any] { [:] }

    fileprivate init(
        child: JavaScriptValueEncoderImplementation,
        attach: @escaping () -> Void
    ) {
        self.child = child
        self.attach = attach
    }

    deinit { attach() }

    fileprivate func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> { child.container(keyedBy: type) }
    fileprivate func unkeyedContainer() -> any UnkeyedEncodingContainer { child.unkeyedContainer() }
    fileprivate func singleValueContainer() -> any SingleValueEncodingContainer { child.singleValueContainer() }
}

internal struct JavaScriptIndexCodingKey: CodingKey {
    internal let intValue: Int?
    internal let stringValue: String

    internal init(index: Int) {
        self.intValue = index
        self.stringValue = "Index \(index)"
    }

    internal init?(intValue: Int) { self.init(index: intValue) }
    internal init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
}
