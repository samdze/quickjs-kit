/// Metadata and argument naming used when exposing a Swift closure to JavaScript.
public struct JavaScriptFunctionOptions: Sendable, Hashable {
    /// Explicit JavaScript parameter names, or `nil` to use `argument0`,
    /// `argument1`, and so on.
    public var parameterNames: [String]?

    /// Human-readable API documentation retained for declaration generation.
    public var documentation: String?

    /// Creates function registration options.
    public init(
        parameterNames: [String]? = nil,
        documentation: String? = nil
    ) {
        self.parameterNames = parameterNames
        self.documentation = documentation
    }
}
