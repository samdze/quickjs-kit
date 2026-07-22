/// Metadata and argument naming used when exposing a Swift closure to JavaScript.
public struct JavaScriptFunctionOptions: Sendable, Hashable {
    /// Explicit JavaScript parameter names, or `nil` to use `argument0`,
    /// `argument1`, and so on.
    public var parameterNames: [String]?

    /// Structured TSDoc retained for declaration generation and IDE tooling.
    public var documentation: TypeScriptFunctionDocumentation?

    /// A logical Swift source location, normally supplied by a macro.
    public var sourceLocation: TypeScriptSourceLocation?

    /// Logical Swift locations for named parameters, normally supplied by a macro.
    public var parameterSourceLocations: [String: TypeScriptSourceLocation]

    /// Creates function registration options.
    public init(
        parameterNames: [String]? = nil,
        documentation: TypeScriptFunctionDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        parameterSourceLocations: [String: TypeScriptSourceLocation] = [:]
    ) {
        self.parameterNames = parameterNames
        self.documentation = documentation
        self.sourceLocation = sourceLocation
        self.parameterSourceLocations = parameterSourceLocations
    }
}
