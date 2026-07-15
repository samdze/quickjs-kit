/// A stable handle to a Swift API exposed to JavaScript.
///
/// Binding handles contain no C pointers and can safely cross concurrency
/// domains. Dropping a handle does not unregister the binding; call ``remove(cancellingInFlight:)``
/// or tear down its runtime to end the binding's lifetime.
public struct JavaScriptBinding: Sendable, Hashable {
    /// The name under which the binding was installed.
    public let name: String

    /// The JavaScript function or object created for this binding.
    public let value: JavaScriptValue

    private let reference: JavaScriptBindingReference

    internal init(
        name: String,
        value: JavaScriptValue,
        reference: JavaScriptBindingReference
    ) {
        self.name = name
        self.value = value
        self.reference = reference
    }

    /// Whether this binding still accepts new calls.
    public var isActive: Bool {
        get async { await reference.runtime.isBindingActive(reference.identifier) }
    }

    /// Disables this binding and optionally cancels its active asynchronous calls.
    ///
    /// Removal is idempotent. The return value is `true` only when this call
    /// transitioned an active binding to the removed state.
    @discardableResult
    public func remove(cancellingInFlight: Bool = false) async throws -> Bool {
        try await reference.runtime.removeBinding(
            reference.identifier,
            cancellingInFlight: cancellingInFlight
        )
    }
}

internal struct JavaScriptBindingReference: Sendable, Hashable {
    internal let runtime: JavaScriptRuntime
    internal let runtimeIdentifier: ObjectIdentifier
    internal let identifier: UInt64

    internal init(runtime: JavaScriptRuntime, identifier: UInt64) {
        self.runtime = runtime
        self.runtimeIdentifier = ObjectIdentifier(runtime)
        self.identifier = identifier
    }

    internal static func == (
        lhs: JavaScriptBindingReference,
        rhs: JavaScriptBindingReference
    ) -> Bool {
        lhs.runtimeIdentifier == rhs.runtimeIdentifier && lhs.identifier == rhs.identifier
    }

    internal func hash(into hasher: inout Hasher) {
        hasher.combine(runtimeIdentifier)
        hasher.combine(identifier)
    }
}
