/// Metadata and argument naming used when exposing a Swift closure to JavaScript.
public struct JavaScriptFunctionOptions: Sendable, Hashable {
    /// Explicit JavaScript parameter names, or `nil` to use `argument0`,
    /// `argument1`, and so on.
    public var parameterNames: [String]?

    /// Structured TSDoc retained for declaration generation and IDE tooling.
    public var documentation: TypeScriptFunctionDocumentation?

    /// Creates function registration options.
    public init(
        parameterNames: [String]? = nil,
        documentation: TypeScriptFunctionDocumentation? = nil
    ) {
        self.parameterNames = parameterNames
        self.documentation = documentation
    }
}
