/// A detached JavaScript value with Swift value semantics.
///
/// `JavaScriptValue` never contains a QuickJS pointer and is `Sendable`.
/// Phase 1 represents JavaScript primitives only. Future runtime-bound types
/// such as objects and functions will preserve this safety boundary rather than
/// exposing manual ownership.
public struct JavaScriptValue: Sendable, Equatable, Hashable, CustomStringConvertible {
    internal enum Storage: Sendable, Equatable, Hashable {
        case undefined
        case null
        case boolean(Bool)
        case number(Double)
        case string(String)
    }

    internal let storage: Storage

    internal init(storage: Storage) {
        self.storage = storage
    }

    /// The JavaScript `undefined` value.
    public static let undefined = JavaScriptValue(storage: .undefined)

    /// The JavaScript `null` value.
    public static let null = JavaScriptValue(storage: .null)

    /// Creates a JavaScript boolean value.
    ///
    /// - Parameter value: The Swift boolean to represent.
    public init(_ value: Bool) {
        self.init(storage: .boolean(value))
    }

    /// Creates a JavaScript number value.
    ///
    /// JavaScript numbers use IEEE 754 binary64 representation, matching
    /// Swift's `Double`.
    ///
    /// - Parameter value: The Swift number to represent.
    public init(_ value: Double) {
        self.init(storage: .number(value))
    }

    /// Creates a JavaScript string value.
    ///
    /// - Parameter value: The Swift string to represent.
    public init(_ value: String) {
        self.init(storage: .string(value))
    }

    /// Whether this value is JavaScript `undefined`.
    public var isUndefined: Bool {
        storage == .undefined
    }

    /// Whether this value is JavaScript `null`.
    public var isNull: Bool {
        storage == .null
    }

    /// The represented boolean, or `nil` when this is another value kind.
    public var booleanValue: Bool? {
        guard case let .boolean(value) = storage else { return nil }
        return value
    }

    /// The represented number, or `nil` when this is another value kind.
    public var numberValue: Double? {
        guard case let .number(value) = storage else { return nil }
        return value
    }

    /// The represented string, or `nil` when this is another value kind.
    public var stringValue: String? {
        guard case let .string(value) = storage else { return nil }
        return value
    }

    /// A concise, human-readable representation of the value.
    public var description: String {
        switch storage {
        case .undefined:
            "undefined"
        case .null:
            "null"
        case let .boolean(value):
            value.description
        case let .number(value):
            value.description
        case let .string(value):
            value
        }
    }
}
