extension JavaScriptRuntimeTemplate {
    /// Composes JavaScript destinations backed by one per-runtime Swift root.
    @resultBuilder
    public enum InstanceBuilder<Root: AnyObject> {
        /// Accepts one contextual per-runtime destination.
        internal static func buildExpression(
            _ expression: Instance<Root>
        ) -> Instance<Root> {
            expression
        }

        /// Combines destinations in lexical order.
        public static func buildBlock(
            _ components: Instance<Root>...
        ) -> Instance<Root> {
            Instance.merging(components)
        }

        /// Includes destinations produced by an optional branch.
        public static func buildOptional(
            _ component: Instance<Root>?
        ) -> Instance<Root> {
            component ?? Instance()
        }

        /// Selects the first branch of a conditional destination.
        public static func buildEither(
            first component: Instance<Root>
        ) -> Instance<Root> {
            component
        }

        /// Selects the second branch of a conditional destination.
        public static func buildEither(
            second component: Instance<Root>
        ) -> Instance<Root> {
            component
        }

        /// Flattens destinations produced by a loop.
        public static func buildArray(
            _ components: [Instance<Root>]
        ) -> Instance<Root> {
            Instance.merging(components)
        }

        /// Preserves destinations guarded by an availability check.
        public static func buildLimitedAvailability(
            _ component: Instance<Root>
        ) -> Instance<Root> {
            component
        }
    }

    /// One or more JavaScript destinations backed by a per-runtime Swift root.
    public struct Instance<Root: AnyObject>: Sendable {
        internal var destinations: [RuntimeInstanceDestination<Root>] = []

        internal init() {}

        /// Declares root-backed functions and values on the global object.
        internal static func globals(
            @InstanceExportBuilder<Root> _ content: @Sendable () -> InstanceExport<Root>
        ) -> Self {
            var instance = Self()
            instance.destinations.append(.globals(content().members))
            return instance
        }

        /// Declares a named object backed by the per-runtime root.
        internal static func export(
            as name: String,
            documentation: TypeScriptDocumentation? = nil,
            @InstanceExportBuilder<Root> _ content: @Sendable () -> InstanceExport<Root>
        ) -> Self {
            var instance = Self()
            instance.destinations.append(
                .object(
                    name: name,
                    documentation: documentation,
                    members: content().members
                )
            )
            return instance
        }

        /// Declares a Swift-defined module backed by the per-runtime root.
        internal static func module(
            _ specifier: String,
            documentation: TypeScriptDocumentation? = nil,
            @InstanceExportBuilder<Root> _ content: @Sendable () -> InstanceExport<Root>
        ) -> Self {
            var instance = Self()
            instance.destinations.append(
                .module(
                    specifier: specifier,
                    documentation: documentation,
                    members: content().members
                )
            )
            return instance
        }

        internal static func merging(_ components: [Self]) -> Self {
            var result = Self()
            for component in components {
                result.destinations.append(contentsOf: component.destinations)
            }
            return result
        }
    }
}

internal enum RuntimeInstanceDestination<Root: AnyObject>: Sendable {
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

    internal func materialize(
        on runtime: isolated JavaScriptRuntime,
        rootIdentifier: UInt64
    ) async throws -> RuntimeTemplateDefinition {
        let definition: RuntimeTemplateDefinition
        switch self {
        case let .globals(members):
            definition = .globals(
                try await members.materialize(
                    on: runtime,
                    rootIdentifier: rootIdentifier
                )
            )
        case let .object(name, documentation, members):
            definition = .object(
                name: name,
                documentation: documentation,
                root: nil,
                members: try await members.materialize(
                    on: runtime,
                    rootIdentifier: rootIdentifier
                )
            )
        case let .module(specifier, documentation, members):
            definition = .module(
                specifier: specifier,
                documentation: documentation,
                members: try await members.materialize(
                    on: runtime,
                    rootIdentifier: rootIdentifier
                )
            )
        }
        return definition
    }
}

private extension Array {
    func materialize<Root: AnyObject>(
        on runtime: isolated JavaScriptRuntime,
        rootIdentifier: UInt64
    ) async throws -> [JavaScriptExportMemberDefinition]
    where Element == RuntimeInstanceMemberDefinition<Root> {
        var result: [JavaScriptExportMemberDefinition] = []
        result.reserveCapacity(count)
        for member in self {
            result.append(
                try await member.materialize(runtime, rootIdentifier)
            )
        }
        return result
    }
}
