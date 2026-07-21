/// Describes JavaScript surfaces backed by one per-runtime Swift root.
public struct JavaScriptRuntimeInstanceBuilder<Root: AnyObject & Sendable> {
    internal var destinations: [RuntimeInstanceDestination<Root>] = []

    internal init() {}

    /// Adds root-backed functions and snapshot values to the global object.
    public mutating func globals(
        _ configure: @Sendable (
            inout JavaScriptInstanceExportBuilder<Root>
        ) -> Void
    ) {
        var builder = JavaScriptInstanceExportBuilder<Root>()
        configure(&builder)
        destinations.append(.globals(builder.members))
    }

    /// Adds a named object whose members use the per-runtime root.
    public mutating func export(
        as name: String,
        documentation: TypeScriptDocumentation? = nil,
        _ configure: @Sendable (
            inout JavaScriptInstanceExportBuilder<Root>
        ) -> Void
    ) {
        var builder = JavaScriptInstanceExportBuilder<Root>()
        configure(&builder)
        destinations.append(
            .object(
                name: name,
                documentation: documentation,
                members: builder.members
            )
        )
    }

    /// Adds a Swift-defined module whose exports use the per-runtime root.
    public mutating func defineModule(
        _ specifier: String,
        documentation: TypeScriptDocumentation? = nil,
        _ configure: @Sendable (
            inout JavaScriptInstanceExportBuilder<Root>
        ) -> Void
    ) {
        var builder = JavaScriptInstanceExportBuilder<Root>()
        configure(&builder)
        destinations.append(
            .module(
                specifier: specifier,
                documentation: documentation,
                members: builder.members
            )
        )
    }
}

internal enum RuntimeInstanceDestination<Root: AnyObject & Sendable>: Sendable {
    case globals([RuntimeInstanceMemberDefinition<Root>])
    case object(
        name: String,
        documentation: TypeScriptDocumentation?,
        members: [RuntimeInstanceMemberDefinition<Root>]
    )
    case module(
        specifier: String,
        documentation: TypeScriptDocumentation?,
        members: [RuntimeInstanceMemberDefinition<Root>]
    )

    internal var environmentGlobals: [EnvironmentGlobalDescription] {
        switch self {
        case let .globals(members):
            return members.map(\.environmentGlobalDescription)
        case let .object(name, documentation, members):
            return [
                .object(
                    name: name,
                    documentation: documentation,
                    members: members.map(\.environmentDescription)
                )
            ]
        case .module:
            return []
        }
    }

    internal var validationMessage: String? {
        let nameMessage: String?
        let documentation: TypeScriptDocumentation?
        let members: [RuntimeInstanceMemberDefinition<Root>]
        let duplicateMessage: String

        switch self {
        case let .globals(value):
            nameMessage = nil
            documentation = nil
            members = value
            duplicateMessage = "Global definitions cannot contain duplicate names."
        case let .object(name, valueDocumentation, value):
            nameMessage = BindingValidation.nameMessage(name, role: "Export names")
            documentation = valueDocumentation
            members = value
            duplicateMessage = "An object export cannot contain duplicate member names."
        case let .module(specifier, valueDocumentation, value):
            nameMessage = BindingValidation.nameMessage(
                specifier,
                role: "Module specifiers"
            )
            documentation = valueDocumentation
            members = value
            duplicateMessage = "A Swift module cannot contain duplicate export names."
        }

        return nameMessage
            ?? TypeScriptDocumentationValidation.message(for: documentation)
            ?? members.lazy.compactMap(\.validationMessage).first
            ?? (BindingValidation.hasDuplicateNames(members.map(\.name))
                ? duplicateMessage
                : nil)
    }

    internal var environmentModule: EnvironmentModuleDescription? {
        guard case let .module(specifier, documentation, members) = self else {
            return nil
        }
        return .swift(
            specifier: specifier,
            documentation: documentation,
            members: members.map(\.environmentDescription)
        )
    }

    internal func materialize(_ root: Root) async throws -> RuntimeTemplateDefinition {
        let definition: RuntimeTemplateDefinition
        switch self {
        case let .globals(members):
            definition = .globals(try await members.materialize(root))
        case let .object(name, documentation, members):
            definition = .object(
                name: name,
                documentation: documentation,
                root: root,
                members: try await members.materialize(root)
            )
        case let .module(specifier, documentation, members):
            definition = .module(
                specifier: specifier,
                documentation: documentation,
                members: try await members.materialize(root)
            )
        }
        return definition
    }
}

private extension Array {
    func materialize<Root: AnyObject & Sendable>(
        _ root: Root
    ) async throws -> [JavaScriptExportMemberDefinition]
    where Element == RuntimeInstanceMemberDefinition<Root> {
        var result: [JavaScriptExportMemberDefinition] = []
        result.reserveCapacity(count)
        for member in self {
            result.append(try await member.materialize(root))
        }
        return result
    }
}
