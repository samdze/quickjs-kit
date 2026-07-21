/// A declarative builder for a reusable JavaScript runtime environment.
///
/// Definitions are validated when their enclosing ``JavaScriptRuntimeTemplate``
/// is created. The builder never creates a QuickJS runtime or evaluates source.
public struct JavaScriptRuntimeTemplateBuilder {
    internal var definitions: [RuntimeTemplateDefinition] = []
    internal var moduleSources: [RuntimeTemplateModuleSource] = []
    internal var moduleLoaders: [JavaScriptModuleLoader] = []
    internal var instances: [RuntimeTemplateInstanceDefinition] = []
    internal var programs: [JavaScriptProgram] = []
    internal var startupActions: [RuntimeTemplateStartupAction] = []

    internal init() {}

    /// Adds functions and snapshot values to the JavaScript global object.
    ///
    /// Snapshot values are encoded separately for every runtime created from
    /// the template.
    public mutating func globals(
        _ configure: @Sendable (inout JavaScriptExportBuilder) -> Void
    ) {
        var builder = JavaScriptExportBuilder()
        configure(&builder)
        definitions.append(.globals(builder.members))
    }

    /// Adds a shared Swift object explicitly exported to JavaScript.
    ///
    /// The root is shared by every runtime created from the template. Use
    /// ``instance(factory:_:)`` when each runtime needs independent Swift state.
    public mutating func export<Root: AnyObject & Sendable>(
        _ root: Root,
        as name: String,
        documentation: TypeScriptDocumentation? = nil,
        _ configure: @Sendable (Root, inout JavaScriptExportBuilder) -> Void
    ) {
        var builder = JavaScriptExportBuilder()
        configure(root, &builder)
        definitions.append(
            .object(
                name: name,
                documentation: documentation,
                root: root,
                members: builder.members
            )
        )
    }

    /// Adds a reusable Swift-defined ES module.
    public mutating func defineModule(
        _ specifier: String,
        documentation: TypeScriptDocumentation? = nil,
        _ configure: @Sendable (inout JavaScriptExportBuilder) -> Void
    ) {
        var builder = JavaScriptExportBuilder()
        configure(&builder)
        definitions.append(
            .module(
                specifier: specifier,
                documentation: documentation,
                members: builder.members
            )
        )
    }

    /// Adds canonical ES module source and optional TypeScript metadata.
    public mutating func registerModule(
        _ source: String,
        as specifier: String,
        sourceURL: String? = nil,
        documentation: TypeScriptDocumentation? = nil,
        typeScriptDeclarations: TypeScriptModuleDeclarations? = nil
    ) {
        moduleSources.append(
            RuntimeTemplateModuleSource(
                source: source,
                specifier: specifier,
                sourceURL: sourceURL ?? specifier,
                documentation: documentation,
                typeScriptDeclarations: typeScriptDeclarations,
                compiledArtifact: nil
            )
        )
    }

    /// Precompiles a program into every runtime without executing it.
    ///
    /// Repeated preparation of the same program value is deduplicated.
    public mutating func prepare(_ program: JavaScriptProgram) {
        programs.append(program)
    }

    /// Precompiles and evaluates a program during runtime creation.
    ///
    /// Startup actions run in declaration order after every shared and
    /// per-runtime Swift definition has been installed. Native Promise results
    /// are awaited before the runtime is returned.
    public mutating func runAtStartup(
        _ program: JavaScriptProgram,
        options: JavaScriptExecutionOptions = .init()
    ) {
        programs.append(program)
        startupActions.append(.program(program, options: options))
    }

    /// Resolves and links a module graph during runtime creation.
    ///
    /// Module bodies remain unevaluated until they are imported.
    public mutating func preloadModule(_ specifier: String) {
        startupActions.append(.preloadModule(specifier))
    }

    /// Imports and evaluates a module during runtime creation.
    ///
    /// Top-level `await` completes before the runtime is returned.
    public mutating func importModuleAtStartup(
        _ specifier: String,
        options: JavaScriptExecutionOptions = .init()
    ) {
        startupActions.append(.importModule(specifier, options: options))
    }

    /// Sets the resolver and asynchronous source loader used by created runtimes.
    ///
    /// Defining more than one loader is a template validation error.
    public mutating func moduleLoader(_ loader: JavaScriptModuleLoader) {
        moduleLoaders.append(loader)
    }

    /// Adds Swift state created independently for every JavaScript runtime.
    ///
    /// The factory may suspend or throw. Its root is retained by the created
    /// runtime until that runtime is released.
    public mutating func instance<Root: AnyObject & Sendable>(
        factory: @escaping @Sendable () async throws -> Root,
        _ configure: @Sendable (
            inout JavaScriptRuntimeInstanceBuilder<Root>
        ) -> Void
    ) {
        var builder = JavaScriptRuntimeInstanceBuilder<Root>()
        configure(&builder)
        let destinations = builder.destinations
        instances.append(
            RuntimeTemplateInstanceDefinition(
                globals: destinations.flatMap(\.environmentGlobals),
                modules: destinations.compactMap(\.environmentModule),
                validationMessages: destinations.compactMap(\.validationMessage),
                instantiate: {
                    let root = try await factory()
                    var definitions: [RuntimeTemplateDefinition] = []
                    definitions.reserveCapacity(destinations.count)
                    for destination in destinations {
                        definitions.append(try await destination.materialize(root))
                    }
                    return MaterializedRuntimeTemplateInstance(
                        root: root,
                        definitions: definitions
                    )
                }
            )
        )
    }
}
