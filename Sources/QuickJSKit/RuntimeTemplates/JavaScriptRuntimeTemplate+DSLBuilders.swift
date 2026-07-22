extension JavaScriptRuntimeTemplate {
    /// Composes the declarations of a reusable JavaScript environment.
    @resultBuilder
    public enum ContentBuilder {
        /// Accepts one contextual template declaration.
        internal static func buildExpression(_ expression: Component) -> Component {
            expression
        }

        /// Combines declarations in lexical order.
        public static func buildBlock(_ components: Component...) -> Component {
            Component.merging(components)
        }

        /// Includes a declaration produced by an optional branch.
        public static func buildOptional(_ component: Component?) -> Component {
            component ?? Component()
        }

        /// Selects the first branch of a conditional declaration.
        public static func buildEither(first component: Component) -> Component {
            component
        }

        /// Selects the second branch of a conditional declaration.
        public static func buildEither(second component: Component) -> Component {
            component
        }

        /// Flattens declarations produced by a loop.
        public static func buildArray(_ components: [Component]) -> Component {
            Component.merging(components)
        }

        /// Preserves a declaration guarded by an availability check.
        public static func buildLimitedAvailability(
            _ component: Component
        ) -> Component {
            component
        }
    }

    /// One concrete declaration group in a runtime template.
    ///
    /// Values of this type are assembled from declarations such as ``Globals``,
    /// ``SwiftModule``, and ``RuntimeInstance`` inside a template.
    public struct Component: Sendable {
        internal var definitions: [RuntimeTemplateDefinition] = []
        internal var moduleSources: [RuntimeTemplateModuleSource] = []
        internal var moduleLoaders: [JavaScriptModuleLoader] = []
        internal var instances: [RuntimeTemplateInstanceDefinition] = []
        internal var programs: [JavaScriptProgram] = []
        internal var startupActions: [RuntimeTemplateStartupAction] = []

        internal init() {}

        /// Declares functions and snapshot values on the global object.
        internal static func globals(
            @ExportBuilder _ content: @Sendable () -> Export
        ) -> Self {
            var component = Self()
            let export = content()
            component.definitions.append(
                .globals(members: export.members, types: export.types)
            )
            return component
        }

        /// Declares a shared Swift object exported to JavaScript.
        ///
        /// The root is shared by every runtime created from the template. Use
        /// ``instance(factory:_:)`` for independent per-runtime Swift state.
        internal static func export<Root: AnyObject & Sendable>(
            _ root: Root,
            as name: String,
            documentation: TypeScriptDocumentation? = nil,
            @ExportBuilder _ content: @Sendable (Root) -> Export
        ) -> Self {
            var component = Self()
            let export = content(root)
            component.definitions.append(
                .object(
                    name: name,
                    documentation: documentation,
                    root: root,
                    members: export.members,
                    types: export.types
                )
            )
            return component
        }

        /// Declares a reusable Swift-defined ES module.
        internal static func module(
            _ specifier: String,
            documentation: TypeScriptDocumentation? = nil,
            @ExportBuilder _ content: @Sendable () -> Export
        ) -> Self {
            var component = Self()
            let export = content()
            component.definitions.append(
                .module(
                    specifier: specifier,
                    documentation: documentation,
                    members: export.members,
                    types: export.types
                )
            )
            return component
        }

        /// Registers canonical ES module source and optional TypeScript metadata.
        internal static func sourceModule(
            _ source: String,
            as specifier: String,
            sourceURL: String? = nil,
            documentation: TypeScriptDocumentation? = nil,
            declarations: TypeScriptModuleDeclarations? = nil
        ) -> Self {
            var component = Self()
            component.moduleSources.append(
                RuntimeTemplateModuleSource(
                    source: source,
                    specifier: specifier,
                    sourceURL: sourceURL ?? specifier,
                    documentation: documentation,
                    typeScriptDeclarations: declarations,
                    compiledArtifact: nil
                )
            )
            return component
        }

        /// Configures the resolver and asynchronous source loader.
        internal static func moduleLoader(_ loader: JavaScriptModuleLoader) -> Self {
            var component = Self()
            component.moduleLoaders.append(loader)
            return component
        }

        /// Declares Swift state created independently for every runtime.
        internal static func instance<Root: AnyObject>(
            factory: @escaping @Sendable () async throws -> sending Root,
            @InstanceBuilder<Root> _ content: @Sendable () -> Instance<Root>
        ) -> Self {
            let destinations = content().destinations
            var component = Self()
            component.instances.append(
                RuntimeTemplateInstanceDefinition(
                    globals: destinations.flatMap(\.environmentGlobals),
                    modules: destinations.compactMap(\.environmentModule),
                    validationMessages: destinations.compactMap(\.validationMessage),
                    install: { runtime in
                        let root = try await factory()
                        try Task.checkCancellation()
                        let rootIdentifier = try runtime.retainRuntimeRoot(root)
                        var definitions: [RuntimeTemplateDefinition] = []
                        definitions.reserveCapacity(destinations.count)
                        do {
                            for destination in destinations {
                                definitions.append(
                                    try await destination.materialize(
                                        on: runtime,
                                        rootIdentifier: rootIdentifier
                                    )
                                )
                            }
                            try await runtime.installTemplateInstance(
                                definitions,
                                rootIdentifier: rootIdentifier
                            )
                        } catch {
                            runtime.releaseRuntimeRoot(rootIdentifier)
                            throw error
                        }
                    }
                )
            )
            return component
        }

        /// Precompiles a program into every runtime without executing it.
        internal static func prepare(_ program: JavaScriptProgram) -> Self {
            var component = Self()
            component.programs.append(program)
            return component
        }

        /// Declares ordered work performed after the environment is installed.
        internal static func startup(
            @StartupBuilder _ content: @Sendable () -> Startup
        ) -> Self {
            let startup = content()
            var component = Self()
            component.programs = startup.programs
            component.startupActions = startup.actions
            return component
        }

        internal static func merging(_ components: [Self]) -> Self {
            var result = Self()
            result.definitions.reserveCapacity(
                components.reduce(0) { $0 + $1.definitions.count }
            )
            for component in components {
                result.definitions.append(contentsOf: component.definitions)
                result.moduleSources.append(contentsOf: component.moduleSources)
                result.moduleLoaders.append(contentsOf: component.moduleLoaders)
                result.instances.append(contentsOf: component.instances)
                result.programs.append(contentsOf: component.programs)
                result.startupActions.append(contentsOf: component.startupActions)
            }
            return result
        }
    }

    /// Composes ordinary functions and snapshot values for one destination.
    @resultBuilder
    public enum ExportBuilder {
        /// Accepts one contextual export declaration.
        internal static func buildExpression(_ expression: Export) -> Export {
            expression
        }

        /// Accepts a published Swift type declaration.
        public static func buildExpression(_ expression: JavaScriptType) -> Export {
            expression.export
        }

        /// Combines members in lexical order.
        public static func buildBlock(_ components: Export...) -> Export {
            Export.merging(components)
        }

        /// Includes members produced by an optional branch.
        public static func buildOptional(_ component: Export?) -> Export {
            component ?? Export()
        }

        /// Selects the first branch of a conditional member declaration.
        public static func buildEither(first component: Export) -> Export {
            component
        }

        /// Selects the second branch of a conditional member declaration.
        public static func buildEither(second component: Export) -> Export {
            component
        }

        /// Flattens members produced by a loop.
        public static func buildArray(_ components: [Export]) -> Export {
            Export.merging(components)
        }

        /// Preserves members guarded by an availability check.
        public static func buildLimitedAvailability(_ component: Export) -> Export {
            component
        }
    }

    /// One or more ordinary members declared by the template DSL.
    public struct Export: Sendable {
        internal var members: [JavaScriptExportMemberDefinition] = []
        internal var types: [AnyJavaScriptTypeDefinition] = []

        internal init() {}

        internal init(members: [JavaScriptExportMemberDefinition]) {
            self.members = members
        }

        internal init(types: [AnyJavaScriptTypeDefinition]) {
            self.types = types
        }

        /// Declares a synchronous typed function.
        internal static func function<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (repeat each Argument) -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: Encodable & Sendable {
            makeMember { $0.function(name, options: options, body) }
        }

        /// Declares a throwing synchronous typed function.
        internal static func function<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (repeat each Argument) throws -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: Encodable & Sendable {
            makeMember { $0.function(name, options: options, body) }
        }

        /// Declares an asynchronous typed function backed by a native promise.
        internal static func function<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (repeat each Argument) async -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: Encodable & Sendable {
            makeMember { $0.function(name, options: options, body) }
        }

        /// Declares an asynchronous throwing function backed by a native promise.
        internal static func function<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (repeat each Argument) async throws -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: Encodable & Sendable {
            makeMember { $0.function(name, options: options, body) }
        }

        /// Declares a synchronous function returning JavaScript `undefined`.
        internal static func function<each Argument>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (repeat each Argument) -> Void
        ) -> Self where repeat each Argument: Decodable & Sendable {
            makeMember { $0.function(name, options: options, body) }
        }

        /// Declares a throwing synchronous function returning `undefined`.
        internal static func function<each Argument>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (repeat each Argument) throws -> Void
        ) -> Self where repeat each Argument: Decodable & Sendable {
            makeMember { $0.function(name, options: options, body) }
        }

        /// Declares an asynchronous function fulfilling with `undefined`.
        internal static func function<each Argument>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (repeat each Argument) async -> Void
        ) -> Self where repeat each Argument: Decodable & Sendable {
            makeMember { $0.function(name, options: options, body) }
        }

        /// Declares an asynchronous throwing function fulfilling with `undefined`.
        internal static func function<each Argument>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (repeat each Argument) async throws -> Void
        ) -> Self where repeat each Argument: Decodable & Sendable {
            makeMember { $0.function(name, options: options, body) }
        }

        /// Declares an Encodable snapshot value.
        internal static func value<Value: Encodable & Sendable>(
            _ value: Value,
            as name: String,
            documentation: TypeScriptDocumentation? = nil
        ) -> Self {
            makeMember {
                $0.value(value, as: name, documentation: documentation)
            }
        }

        private static func makeMember(
            _ configure: (inout JavaScriptExportBuilder) -> Void
        ) -> Self {
            var builder = JavaScriptExportBuilder()
            configure(&builder)
            var result = Self()
            result.members = builder.members
            return result
        }

        internal static func merging(_ components: [Self]) -> Self {
            var result = Self()
            result.members.reserveCapacity(
                components.reduce(0) { $0 + $1.members.count }
            )
            for component in components {
                result.members.append(contentsOf: component.members)
                result.types.append(contentsOf: component.types)
            }
            return result
        }
    }

    /// Composes startup work in execution order.
    @resultBuilder
    public enum StartupBuilder {
        /// Accepts one contextual startup declaration.
        internal static func buildExpression(_ expression: Startup) -> Startup {
            expression
        }

        /// Combines startup actions in lexical order.
        public static func buildBlock(_ components: Startup...) -> Startup {
            Startup.merging(components)
        }

        /// Includes startup work produced by an optional branch.
        public static func buildOptional(_ component: Startup?) -> Startup {
            component ?? Startup()
        }

        /// Selects the first branch of conditional startup work.
        public static func buildEither(first component: Startup) -> Startup {
            component
        }

        /// Selects the second branch of conditional startup work.
        public static func buildEither(second component: Startup) -> Startup {
            component
        }

        /// Flattens startup work produced by a loop.
        public static func buildArray(_ components: [Startup]) -> Startup {
            Startup.merging(components)
        }

        /// Preserves startup work guarded by an availability check.
        public static func buildLimitedAvailability(_ component: Startup) -> Startup {
            component
        }
    }

    /// One or more ordered startup actions.
    public struct Startup: Sendable {
        internal var programs: [JavaScriptProgram] = []
        internal var actions: [RuntimeTemplateStartupAction] = []

        internal init() {}

        /// Runs a prepared program and awaits a native Promise result.
        internal static func run(
            _ program: JavaScriptProgram,
            options: JavaScriptExecutionOptions = .init()
        ) -> Self {
            var startup = Self()
            startup.programs.append(program)
            startup.actions.append(.program(program, options: options))
            return startup
        }

        /// Resolves and links a module without evaluating its body.
        internal static func preloadModule(_ specifier: String) -> Self {
            var startup = Self()
            startup.actions.append(.preloadModule(specifier))
            return startup
        }

        /// Imports a module and awaits top-level asynchronous initialization.
        internal static func importModule(
            _ specifier: String,
            options: JavaScriptExecutionOptions = .init()
        ) -> Self {
            var startup = Self()
            startup.actions.append(.importModule(specifier, options: options))
            return startup
        }

        internal static func merging(_ components: [Self]) -> Self {
            var result = Self()
            for component in components {
                result.programs.append(contentsOf: component.programs)
                result.actions.append(contentsOf: component.actions)
            }
            return result
        }
    }
}
