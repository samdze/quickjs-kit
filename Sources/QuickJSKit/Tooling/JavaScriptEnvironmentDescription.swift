/// An immutable description of the Swift-provided JavaScript environment.
///
/// A description contains no runtime, closure, actor, live JavaScript value, or
/// QuickJS state. It remains usable after its originating runtime is released.
public struct JavaScriptEnvironmentDescription: Sendable, Hashable {
    internal let globals: [EnvironmentGlobalDescription]
    internal let modules: [EnvironmentModuleDescription]
    internal let additionalSchemas: [TypeScriptSchema]

    internal init(
        globals: [EnvironmentGlobalDescription],
        modules: [EnvironmentModuleDescription],
        additionalSchemas: [TypeScriptSchema]
    ) {
        self.globals = globals.map(\.normalized).sorted { $0.name < $1.name }
        self.modules = modules.map(\.normalized).sorted { $0.specifier < $1.specifier }
        self.additionalSchemas = additionalSchemas
    }

    /// Generates one deterministic ambient TypeScript declaration file.
    ///
    /// - Parameter options: Declaration rendering and completeness options.
    /// - Returns: The complete UTF-8 declaration source.
    /// - Throws: ``TypeScriptToolingError`` when metadata is incomplete or
    ///   inconsistent.
    public func typeScriptDeclarations(
        options: TypeScriptDeclarationOptions = .init()
    ) throws -> String {
        try TypeScriptRenderer(environment: self, options: options).render()
    }

}

private extension EnvironmentGlobalDescription {
    var normalized: Self {
        guard case let .object(name, members) = self else { return self }
        return .object(name: name, members: members.sorted { $0.name < $1.name })
    }
}

private extension EnvironmentModuleDescription {
    var normalized: Self {
        guard case let .swift(specifier, members) = self else { return self }
        return .swift(
            specifier: specifier,
            members: members.sorted { $0.name < $1.name }
        )
    }
}

extension JavaScriptRuntime {
    /// Captures the Swift-provided surface currently visible to JavaScript.
    ///
    /// JavaScript-created globals and future results from an open-ended module
    /// loader are intentionally excluded. The returned value is detached from
    /// this actor and does not change after capture.
    ///
    /// - Parameter additionalSchemas: Schemas to include even when no current
    ///   binding refers to them.
    /// - Returns: A deterministic, runtime-independent environment snapshot.
    public func environmentDescription(
        including additionalSchemas: [TypeScriptSchema] = []
    ) throws -> JavaScriptEnvironmentDescription {
        JavaScriptEnvironmentDescription(
            globals: engine.environmentGlobals.values.map(\.description),
            modules: Array(engine.environmentModules.values),
            additionalSchemas: additionalSchemas
        )
    }
}
