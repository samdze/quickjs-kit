/// An immutable description of a reusable JavaScript runtime environment.
///
/// A template contains Swift definitions, source modules, tooling metadata,
/// and per-runtime factories. It contains no QuickJS heap or live JavaScript
/// value. Every call to ``makeRuntime()`` creates a fully independent runtime.
public struct JavaScriptRuntimeTemplate: Sendable {
    /// The resource and execution configuration applied to every created runtime.
    public let configuration: JavaScriptRuntime.Configuration

    private let plan: RuntimeTemplateProvisioningPlan

    internal var compiledModuleArtifactCountForTesting: Int {
        plan.moduleSources.lazy.compactMap(\.compiledArtifact).count
    }

    internal var compiledProgramArtifactCountForTesting: Int {
        plan.programs.lazy.compactMap(\.compiledArtifact).count
    }

    internal func corruptingFirstCompiledArtifactForTesting() -> Self {
        Self(
            configuration: configuration,
            plan: plan.replacingFirstCompiledArtifactForTesting(with: [0, 1, 2, 3])
        )
    }

    internal func corruptingFirstCompiledProgramForTesting() -> Self {
        Self(
            configuration: configuration,
            plan: plan.replacingFirstCompiledProgramForTesting(with: [0, 1, 2, 3])
        )
    }

    /// Creates and validates a reusable runtime template.
    ///
    /// The configuration closure is synchronous and declarative. It does not
    /// create a runtime, invoke per-runtime factories, load asynchronous module
    /// source, or evaluate JavaScript.
    ///
    /// - Parameters:
    ///   - configuration: Configuration copied to every created runtime.
    ///   - content: Declarative components describing the reusable environment.
    /// - Throws: ``JavaScriptError`` when definitions conflict, metadata is
    ///   invalid, a live JavaScript value is present, or registered module
    ///   source contains a syntax error.
    public init(
        configuration: JavaScriptRuntime.Configuration = .init(),
        @ContentBuilder _ content: @Sendable () -> Component
    ) throws {
        let component = content()
        self.configuration = configuration
        self.plan = try RuntimeTemplateProvisioningPlan(
            configuration: configuration,
            component: component
        ).compilingArtifacts()
    }

    /// Creates one fully configured, independently isolated runtime.
    ///
    /// Per-runtime factories execute sequentially in declaration order. Calls
    /// to this method may run concurrently and never share QuickJS heap state.
    ///
    /// - Returns: A runtime whose initial Swift-provided environment matches
    ///   this template's environment description.
    /// - Throws: A factory error, `CancellationError`, or ``JavaScriptError``
    ///   produced while creating or publishing the environment.
    public func makeRuntime() async throws -> JavaScriptRuntime {
        try Task.checkCancellation()
        do {
            return try await makeRuntime(usingCompiledArtifacts: true)
        } catch is RuntimeTemplateArtifactReadError {
            try Task.checkCancellation()
            return try await makeRuntime(
                usingCompiledArtifacts: false,
                usedSourceFallback: true
            )
        }
    }

    /// Describes the environment without constructing a JavaScript runtime.
    ///
    /// The snapshot contains the same globals, modules, documentation, and
    /// schemas installed into an unchanged runtime created by this template.
    public func environmentDescription(
        including additionalSchemas: [TypeScriptSchema] = []
    ) throws -> JavaScriptEnvironmentDescription {
        plan.environmentDescription(including: additionalSchemas)
    }

    private func makeRuntime(
        usingCompiledArtifacts: Bool,
        usedSourceFallback: Bool = false
    ) async throws -> JavaScriptRuntime {
        let runtime = try JavaScriptRuntime(configuration: configuration)
        try await runtime.installTemplatePrelude(
            plan,
            usingCompiledArtifacts: usingCompiledArtifacts,
            usedSourceFallback: usedSourceFallback
        )

        for instance in plan.instances {
            try Task.checkCancellation()
            try await runtime.installTemplateInstance(instance)
        }

        for action in plan.startupActions {
            try Task.checkCancellation()
            try await runtime.performTemplateStartup(action)
        }
        return runtime
    }

    private init(
        configuration: JavaScriptRuntime.Configuration,
        plan: RuntimeTemplateProvisioningPlan
    ) {
        self.configuration = configuration
        self.plan = plan
    }
}
