/// A live ES module namespace bound to its originating runtime.
public struct JavaScriptModule: Sendable, Hashable {
    /// The canonical specifier used to identify the module.
    public let specifier: String

    /// The module namespace object.
    public let namespace: JavaScriptObject

    internal init(specifier: String, namespace: JavaScriptObject) {
        self.specifier = specifier
        self.namespace = namespace
    }

    /// Returns the module's exported string names in deterministic order.
    public func exportNames() async throws -> [String] {
        try await namespace.propertyNames()
    }

    /// Returns one exported value without converting live objects.
    public func value(forExport name: String) async throws -> JavaScriptValue {
        try await namespace.value(forProperty: name)
    }

    /// Decodes one exported value as a Swift type.
    public func value<T: Decodable & Sendable>(
        forExport name: String,
        as type: T.Type = T.self
    ) async throws -> T {
        try await namespace.value(forProperty: name, as: type)
    }

    /// Returns one exported JavaScript function as a reusable live handle.
    ///
    /// Resolve an export once and retain the returned handle when Swift calls
    /// it repeatedly. The handle remains bound to this module's runtime.
    public func function(forExport name: String) async throws -> JavaScriptFunction {
        let value = try await value(forExport: name)
        guard let function = value.functionValue else {
            throw JavaScriptError(
                kind: .conversion,
                message: "Module export '\(name)' is not a function."
            )
        }
        return function
    }
}
