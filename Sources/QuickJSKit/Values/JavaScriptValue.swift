/// A JavaScript value with safe Swift ownership semantics.
///
/// Primitive values are detached from QuickJS and can be copied freely. Object,
/// array, and function values contain only a pointer-free identity that routes
/// operations back through their originating ``JavaScriptRuntime`` actor.
public struct JavaScriptValue: Sendable, Equatable, Hashable, CustomStringConvertible {
    internal enum Storage: Sendable, Equatable, Hashable {
        case undefined
        case null
        case boolean(Bool)
        case number(Double)
        case string(String)
        case bigInt(JavaScriptBigInt)
        case reference(JavaScriptReference)
    }

    /// JavaScript's largest exactly representable integer as a `Number`.
    ///
    /// This deliberately uses `Int64` rather than platform-width `Int` so the
    /// value is available on 32-bit Swift targets such as watchOS.
    internal static let maximumSafeInteger: Int64 = 9_007_199_254_740_991
    internal let storage: Storage

    internal init(storage: Storage) {
        self.storage = storage
    }

    internal init(reference: JavaScriptReference) {
        self.init(storage: .reference(reference))
    }

    /// The JavaScript `undefined` value.
    public static let undefined = JavaScriptValue(storage: .undefined)

    /// The JavaScript `null` value.
    public static let null = JavaScriptValue(storage: .null)

    /// Creates a JavaScript boolean value.
    public init(_ value: Bool) {
        self.init(storage: .boolean(value))
    }

    /// Creates a JavaScript number value.
    public init(_ value: Double) {
        self.init(storage: .number(value))
    }

    /// Creates a JavaScript number value from a single-precision value.
    public init(_ value: Float) {
        self.init(Double(value))
    }

    /// Creates a lossless JavaScript numeric value.
    ///
    /// Values in JavaScript's safe integer range become `number`; larger
    /// magnitudes become `bigint`.
    public init(_ value: Int) {
        let integer = Int64(value)
        if integer >= -Self.maximumSafeInteger && integer <= Self.maximumSafeInteger {
            self.init(Double(integer))
        } else {
            self.init(JavaScriptBigInt(integer))
        }
    }

    /// Creates a lossless JavaScript numeric value.
    ///
    /// Values in JavaScript's safe integer range become `number`; larger values
    /// become `bigint`.
    public init(_ value: UInt) {
        let integer = UInt64(value)
        if integer <= UInt64(Self.maximumSafeInteger) {
            self.init(Double(integer))
        } else {
            self.init(JavaScriptBigInt(integer))
        }
    }

    /// Creates a JavaScript arbitrary-precision integer value.
    public init(_ value: JavaScriptBigInt) {
        self.init(storage: .bigInt(value))
    }

    /// Creates a JavaScript string value.
    public init(_ value: String) {
        self.init(storage: .string(value))
    }

    /// Whether this value is JavaScript `undefined`.
    public var isUndefined: Bool { storage == .undefined }

    /// Whether this value is JavaScript `null`.
    public var isNull: Bool { storage == .null }

    /// Whether this value is a JavaScript object of any supported specialization.
    public var isObject: Bool {
        guard case .reference = storage else { return false }
        return true
    }

    /// Whether this value is a JavaScript array.
    public var isArray: Bool {
        guard case let .reference(reference) = storage else { return false }
        return reference.kind == .array
    }

    /// Whether this value is a JavaScript function.
    public var isFunction: Bool {
        guard case let .reference(reference) = storage else { return false }
        return reference.kind == .function
    }

    /// The represented boolean, or `nil` for another value kind.
    public var booleanValue: Bool? {
        guard case let .boolean(value) = storage else { return nil }
        return value
    }

    /// The represented number, or `nil` for another value kind.
    public var numberValue: Double? {
        guard case let .number(value) = storage else { return nil }
        return value
    }

    /// The represented string, or `nil` for another value kind.
    public var stringValue: String? {
        guard case let .string(value) = storage else { return nil }
        return value
    }

    /// The represented arbitrary-precision integer, or `nil` for another kind.
    public var bigIntValue: JavaScriptBigInt? {
        guard case let .bigInt(value) = storage else { return nil }
        return value
    }

    /// A live object handle, or `nil` for a primitive value.
    public var objectValue: JavaScriptObject? {
        guard case let .reference(reference) = storage else { return nil }
        return JavaScriptObject(reference: reference)
    }

    /// A live array handle, or `nil` when this is not an array.
    public var arrayValue: JavaScriptArray? {
        guard case let .reference(reference) = storage,
              reference.kind == .array else { return nil }
        return JavaScriptArray(reference: reference)
    }

    /// A live function handle, or `nil` when this is not a function.
    public var functionValue: JavaScriptFunction? {
        guard case let .reference(reference) = storage,
              reference.kind == .function else { return nil }
        return JavaScriptFunction(reference: reference)
    }

    /// A concise representation that never executes JavaScript.
    public var description: String {
        switch storage {
        case .undefined: "undefined"
        case .null: "null"
        case let .boolean(value): value.description
        case let .number(value): value.description
        case let .string(value): value
        case let .bigInt(value): value.description + "n"
        case let .reference(reference):
            switch reference.kind {
            case .object: "[object]"
            case .array: "[array]"
            case .function: "[function]"
            }
        }
    }
}
