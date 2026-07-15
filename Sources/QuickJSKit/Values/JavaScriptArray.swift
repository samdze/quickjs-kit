/// A live JavaScript array bound to its originating runtime.
public struct JavaScriptArray: Sendable, Hashable {
    internal let reference: JavaScriptReference

    internal init(reference: JavaScriptReference) {
        self.reference = reference
    }

    /// The general JavaScript value representing this array.
    public var value: JavaScriptValue { JavaScriptValue(reference: reference) }

    /// This array viewed as a JavaScript object.
    public var object: JavaScriptObject { JavaScriptObject(reference: reference) }

    /// The current JavaScript array length.
    public var count: Int {
        get async throws {
            try await reference.runtime.arrayCount(reference)
        }
    }

    /// Reads an array element. A sparse slot produces `undefined`.
    public func value(at index: Int) async throws -> JavaScriptValue {
        try await reference.runtime.value(at: index, in: reference)
    }

    /// Reads and directly decodes an array element.
    public func value<T: Decodable & Sendable>(
        at index: Int,
        as type: T.Type = T.self
    ) async throws -> T {
        try await reference.runtime.value(at: index, in: reference, as: type)
    }

    /// Encodes and assigns an array element.
    public func set<T: Encodable & Sendable>(
        _ value: T,
        at index: Int
    ) async throws {
        try await reference.runtime.set(value, at: index, in: reference)
    }

    /// Assigns an existing JavaScript value to an array element.
    public func set(_ value: JavaScriptValue, at index: Int) async throws {
        try await reference.runtime.set(value, at: index, in: reference)
    }

    /// Encodes and appends an element.
    public func append<T: Encodable & Sendable>(_ value: T) async throws {
        try await reference.runtime.append(value, to: reference)
    }

    /// Appends an existing JavaScript value.
    public func append(_ value: JavaScriptValue) async throws {
        try await reference.runtime.append(value, to: reference)
    }
}
