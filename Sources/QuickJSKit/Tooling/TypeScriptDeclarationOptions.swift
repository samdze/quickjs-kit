/// Options controlling TypeScript declaration generation.
public struct TypeScriptDeclarationOptions: Sendable, Hashable {
    /// How generation handles runtime-valid values without TypeScript metadata.
    public enum Completeness: Sendable, Hashable {
        /// Reject incomplete custom Codable and source-module metadata.
        case strict
        /// Render incomplete values and modules as explicitly untyped.
        case allowUntyped
    }

    /// The namespace containing named Swift model schemas.
    public var typeNamespace: String

    /// The policy for missing structural metadata.
    public var completeness: Completeness

    /// How generation handles missing TSDoc metadata.
    public var documentationCompleteness: DocumentationCompleteness

    /// Creates declaration options.
    public init(
        typeNamespace: String = "QuickJSKit",
        completeness: Completeness = .strict,
        documentationCompleteness: DocumentationCompleteness = .allowMissing
    ) {
        self.typeNamespace = typeNamespace
        self.completeness = completeness
        self.documentationCompleteness = documentationCompleteness
    }
}

/// Controls whether every generated declaration must have complete TSDoc.
public enum DocumentationCompleteness: Sendable, Hashable {
    /// Generate declarations when some documentation is absent.
    case allowMissing
    /// Reject generated declarations with incomplete documentation.
    case requireComplete
}

/// A deterministic failure while generating TypeScript tooling.
public struct TypeScriptToolingError: Error, Sendable, Hashable, CustomStringConvertible {
    /// A human-readable explanation suitable for diagnostics.
    public let message: String

    /// Creates a tooling error with an actionable message.
    public init(_ message: String) {
        self.message = message
    }

    /// The diagnostic text.
    public var description: String { message }
}
