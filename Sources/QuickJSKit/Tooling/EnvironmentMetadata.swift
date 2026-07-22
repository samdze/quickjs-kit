internal struct EnvironmentFunctionDescription: Sendable, Hashable {
    internal let name: String
    internal let parameters: [BindingParameterDescription]
    internal let result: BindingTypeShape
    internal let effects: BindingDescription.Effects
    internal let documentation: TypeScriptFunctionDocumentation?
    internal let sourceLocation: TypeScriptSourceLocation?

    internal init(_ description: BindingDescription) {
        self.name = description.name
        self.parameters = description.parameters
        self.result = description.result
        self.effects = description.effects
        self.documentation = description.documentation
        self.sourceLocation = description.sourceLocation
    }

    internal init(_ draft: BindingDraft) {
        self.name = draft.name
        self.parameters = draft.parameters
        self.result = draft.result
        self.effects = draft.effects
        self.documentation = draft.documentation
        self.sourceLocation = draft.sourceLocation
    }
}

internal struct EnvironmentValueDescription: Sendable, Hashable {
    internal let name: String
    internal let type: BindingTypeShape
    internal let documentation: TypeScriptDocumentation?
    internal let isReadOnly: Bool
    internal let sourceLocation: TypeScriptSourceLocation?

    internal init(
        name: String,
        type: BindingTypeShape,
        documentation: TypeScriptDocumentation?,
        isReadOnly: Bool,
        sourceLocation: TypeScriptSourceLocation? = nil
    ) {
        self.name = name
        self.type = type
        self.documentation = documentation
        self.isReadOnly = isReadOnly
        self.sourceLocation = sourceLocation
    }
}

internal enum EnvironmentMemberDescription: Sendable, Hashable {
    case function(EnvironmentFunctionDescription)
    case type(EnvironmentTypeDescription)
    case value(EnvironmentValueDescription)

    internal var name: String {
        switch self {
        case let .function(function): function.name
        case let .type(type): type.name
        case let .value(value): value.name
        }
    }
}

internal struct EnvironmentTypeDescription: Sendable, Hashable {
    internal enum Kind: Sendable, Hashable {
        case structure
        case enumeration(cases: [TypeScriptEnumCase])
        case host(
            constructors: [EnvironmentFunctionDescription],
            staticMembers: [EnvironmentMemberDescription],
            instanceMembers: [EnvironmentMemberDescription]
        )
    }

    internal let name: String
    internal var schema: TypeScriptSchema?
    internal let documentation: TypeScriptDocumentation?
    internal let sourceLocation: TypeScriptSourceLocation?
    internal let kind: Kind
}

internal enum EnvironmentGlobalDescription: Sendable, Hashable {
    case function(EnvironmentFunctionDescription)
    case object(
        name: String,
        documentation: TypeScriptDocumentation?,
        members: [EnvironmentMemberDescription]
    )
    case type(EnvironmentTypeDescription)
    case value(EnvironmentValueDescription)

    internal var name: String {
        switch self {
        case let .function(function): function.name
        case let .object(name, _, _): name
        case let .type(type): type.name
        case let .value(value): value.name
        }
    }
}

internal struct RegisteredEnvironmentGlobal: Sendable, Hashable {
    internal let bindingIdentifier: UInt64?
    internal let description: EnvironmentGlobalDescription
}

internal enum EnvironmentModuleDescription: Sendable, Hashable {
    case swift(
        specifier: String,
        documentation: TypeScriptDocumentation?,
        members: [EnvironmentMemberDescription]
    )
    case source(
        specifier: String,
        documentation: TypeScriptDocumentation?,
        declarations: TypeScriptModuleDeclarations?
    )

    internal var specifier: String {
        switch self {
        case let .swift(specifier, _, _), let .source(specifier, _, _): specifier
        }
    }
}

extension JavaScriptExportMemberDefinition {
    internal var environmentDescription: EnvironmentMemberDescription {
        switch storage {
        case let .function(definition):
            return .function(EnvironmentFunctionDescription(definition.draft))
        case let .runtimeFunction(definition):
            return .function(EnvironmentFunctionDescription(definition.draft))
        case let .property(type, _, setter):
            return .value(
                EnvironmentValueDescription(
                    name: name,
                    type: type,
                    documentation: documentation,
                    isReadOnly: setter == nil
                )
            )
        case let .runtimeProperty(type, _, setter):
            return .value(
                EnvironmentValueDescription(
                    name: name,
                    type: type,
                    documentation: documentation,
                    isReadOnly: setter == nil
                )
            )
        case let .value(type, _), let .liveValue(type, _):
            return .value(
                EnvironmentValueDescription(
                    name: name,
                    type: type,
                    documentation: documentation,
                    isReadOnly: true
                )
            )
        case let .type(definition):
            return .type(definition.environmentDescription)
        case let .materializedHostType(definition, _, _):
            return .type(definition.environmentDescription)
        }
    }
}
