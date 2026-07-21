internal struct EnvironmentFunctionDescription: Sendable, Hashable {
    internal let name: String
    internal let parameters: [BindingParameterDescription]
    internal let result: BindingTypeShape
    internal let effects: BindingDescription.Effects
    internal let documentation: String?

    internal init(_ description: BindingDescription) {
        self.name = description.name
        self.parameters = description.parameters
        self.result = description.result
        self.effects = description.effects
        self.documentation = description.documentation
    }

    internal init(_ draft: BindingDraft) {
        self.name = draft.name
        self.parameters = draft.parameters
        self.result = draft.result
        self.effects = draft.effects
        self.documentation = draft.documentation
    }
}

internal struct EnvironmentValueDescription: Sendable, Hashable {
    internal let name: String
    internal let type: BindingTypeShape
    internal let documentation: String?
    internal let isReadOnly: Bool
}

internal enum EnvironmentMemberDescription: Sendable, Hashable {
    case function(EnvironmentFunctionDescription)
    case value(EnvironmentValueDescription)

    internal var name: String {
        switch self {
        case let .function(function): function.name
        case let .value(value): value.name
        }
    }
}

internal enum EnvironmentGlobalDescription: Sendable, Hashable {
    case function(EnvironmentFunctionDescription)
    case object(name: String, members: [EnvironmentMemberDescription])
    case value(EnvironmentValueDescription)

    internal var name: String {
        switch self {
        case let .function(function): function.name
        case let .object(name, _): name
        case let .value(value): value.name
        }
    }
}

internal struct RegisteredEnvironmentGlobal: Sendable, Hashable {
    internal let bindingIdentifier: UInt64?
    internal let description: EnvironmentGlobalDescription
}

internal enum EnvironmentModuleDescription: Sendable, Hashable {
    case swift(specifier: String, members: [EnvironmentMemberDescription])
    case source(specifier: String, declarations: TypeScriptModuleDeclarations?)

    internal var specifier: String {
        switch self {
        case let .swift(specifier, _), let .source(specifier, _): specifier
        }
    }
}

extension JavaScriptExportMemberDefinition {
    internal var environmentDescription: EnvironmentMemberDescription {
        switch storage {
        case let .function(definition):
            return .function(EnvironmentFunctionDescription(definition.draft))
        case let .value(type, _), let .liveValue(type, _):
            return .value(
                EnvironmentValueDescription(
                    name: name,
                    type: type,
                    documentation: documentation,
                    isReadOnly: true
                )
            )
        }
    }
}
