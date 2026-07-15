/// A live JavaScript object bound to its originating runtime.
///
/// The handle contains no C pointer and may cross concurrency boundaries. Each
/// operation re-enters the owning ``JavaScriptRuntime`` actor.
public struct JavaScriptObject: Sendable, Hashable {
    internal let reference: JavaScriptReference

    internal init(reference: JavaScriptReference) {
        self.reference = reference
    }

    /// The general JavaScript value representing this object.
    public var value: JavaScriptValue {
        JavaScriptValue(reference: reference)
    }

    /// Reads a property using normal JavaScript property access semantics.
    public func value(forProperty name: String) async throws -> JavaScriptValue {
        try await reference.runtime.value(forProperty: name, on: reference)
    }

    /// Reads and directly decodes a property.
    public func value<T: Decodable & Sendable>(
        forProperty name: String,
        as type: T.Type = T.self
    ) async throws -> T {
        try await reference.runtime.value(
            forProperty: name,
            on: reference,
            as: type
        )
    }

    /// Encodes and assigns a property value.
    public func set<T: Encodable & Sendable>(
        _ value: T,
        forProperty name: String
    ) async throws {
        try await reference.runtime.set(value, forProperty: name, on: reference)
    }

    /// Assigns an existing JavaScript value.
    public func set(
        _ value: JavaScriptValue,
        forProperty name: String
    ) async throws {
        try await reference.runtime.set(value, forProperty: name, on: reference)
    }

    /// Returns whether JavaScript property lookup can find this name.
    public func hasProperty(_ name: String) async throws -> Bool {
        try await reference.runtime.hasProperty(name, on: reference)
    }

    /// Deletes a property and reports whether deletion succeeded.
    @discardableResult
    public func deleteProperty(_ name: String) async throws -> Bool {
        try await reference.runtime.deleteProperty(name, on: reference)
    }

    /// Returns this object's own enumerable string property names.
    public func propertyNames() async throws -> [String] {
        try await reference.runtime.propertyNames(of: reference)
    }
}
