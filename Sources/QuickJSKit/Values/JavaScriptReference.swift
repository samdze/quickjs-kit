internal enum JavaScriptReferenceKind: Sendable, Hashable {
    case object
    case array
    case function
}

/// Pointer-free identity for a value retained by a runtime actor.
internal final class JavaScriptReference: Sendable, Hashable {
    internal let runtime: JavaScriptRuntime
    internal let runtimeIdentifier: ObjectIdentifier
    internal let identifier: UInt64
    internal let kind: JavaScriptReferenceKind
    private let releasesOnDeinit: Bool

    internal init(
        runtime: JavaScriptRuntime,
        identifier: UInt64,
        kind: JavaScriptReferenceKind,
        releasesOnDeinit: Bool = true
    ) {
        self.runtime = runtime
        self.runtimeIdentifier = ObjectIdentifier(runtime)
        self.identifier = identifier
        self.kind = kind
        self.releasesOnDeinit = releasesOnDeinit
    }

    deinit {
        guard releasesOnDeinit else { return }
        let runtime = runtime
        let identifier = identifier
        Task {
            await runtime.releaseReference(identifier)
        }
    }

    internal static func == (
        lhs: JavaScriptReference,
        rhs: JavaScriptReference
    ) -> Bool {
        lhs.runtimeIdentifier == rhs.runtimeIdentifier
            && lhs.identifier == rhs.identifier
    }

    internal func hash(into hasher: inout Hasher) {
        hasher.combine(runtimeIdentifier)
        hasher.combine(identifier)
    }
}
