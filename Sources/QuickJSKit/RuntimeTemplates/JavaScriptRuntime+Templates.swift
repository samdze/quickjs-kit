extension JavaScriptRuntime {
    internal func installTemplateInstance(
        _ instance: RuntimeTemplateInstanceDefinition
    ) async throws {
        try await instance.install(self)
    }

    internal func installTemplatePrelude(
        _ plan: RuntimeTemplateProvisioningPlan,
        usingCompiledArtifacts: Bool,
        usedSourceFallback: Bool
    ) throws {
        if let loader = plan.moduleLoader {
            try setModuleLoader(loader)
        }

        try engine.withEngineEntry(drainJobs: false) {
            reserveCapacity(for: plan)
            for source in plan.moduleSources {
                try engine.registerModuleSource(
                    source.source,
                    specifier: source.specifier,
                    sourceURL: source.sourceURL,
                    documentation: source.documentation,
                    typeScriptDeclarations: source.typeScriptDeclarations
                )
            }

            if usingCompiledArtifacts {
                for source in plan.moduleSources {
                    guard let artifact = source.compiledArtifact else { continue }
                    try engine.installCompiledModuleArtifact(
                        artifact,
                        specifier: source.specifier,
                        sourceURL: source.sourceURL
                    )
                }
            }

            for program in plan.programs {
                if usingCompiledArtifacts, let artifact = program.compiledArtifact {
                    try engine.installCompiledProgramArtifact(
                        artifact,
                        for: program.program
                    )
                } else {
                    try engine.prepareProgram(program.program)
                }
            }

            if usedSourceFallback {
                engine.templateCacheFallbackCountForTesting += 1
            }

            for definition in plan.definitions {
                try installTemplateDefinition(definition)
            }
        }
    }

    internal func installTemplateInstance(
        _ definitions: [RuntimeTemplateDefinition],
        rootIdentifier: UInt64
    ) throws {
        do {
            try engine.withEngineEntry(drainJobs: false) {
                reserveCapacity(for: definitions)
                for definition in definitions {
                    try installTemplateDefinition(definition)
                }
            }
        } catch {
            releaseRuntimeRoot(rootIdentifier)
            throw error
        }
    }

    internal func performTemplateStartup(
        _ action: RuntimeTemplateStartupAction
    ) async throws {
        switch action {
        case let .program(program, options):
            _ = try await readRoot(
                sourceURL: program.sourceURL,
                options: options,
                produce: { try engine.evaluatePreparedProgram(program) },
                transform: { _ in () }
            )
        case let .preloadModule(specifier):
            try await preloadModule(specifier)
        case let .importModule(specifier, options):
            _ = try await importModule(specifier, options: options)
        }
    }

    private func installTemplateDefinition(
        _ definition: RuntimeTemplateDefinition
    ) throws {
        switch definition {
        case let .globals(members):
            for member in members {
                try installTemplateGlobal(member)
            }
        case let .object(name, documentation, root, members):
            try engine.withEngineEntry {
                _ = try engine.registerExport(
                    named: name,
                    documentation: documentation,
                    root: root,
                    members: members,
                    settle: bindingSettlement
                )
            }
        case let .module(specifier, documentation, members):
            try engine.withEngineEntry {
                try engine.registerSwiftModule(
                    specifier: specifier,
                    documentation: documentation,
                    members: members,
                    settle: bindingSettlement
                )
            }
        }
    }

    private func installTemplateGlobal(
        _ member: JavaScriptExportMemberDefinition
    ) throws {
        switch member.storage {
        case let .function(definition):
            let function = definition.bind(
                location: .global,
                order: engine.nextBindingIdentifier,
                settle: bindingSettlement
            )
            _ = try engine.registerGlobalBinding(
                named: member.name,
                function: function
            )
        case let .runtimeFunction(definition):
            let function = definition.bind(
                location: .global,
                order: engine.nextBindingIdentifier,
                settle: bindingSettlement
            )
            _ = try engine.registerGlobalBinding(
                named: member.name,
                function: function
            )
        case let .property(type, getter, setter):
            let global = engine.globalObject()
            _ = try engine.defineBoundProperty(
                member.name,
                on: global.raw,
                getter: getter.bind(
                    location: .global,
                    order: engine.nextBindingIdentifier,
                    settle: bindingSettlement
                ),
                setter: setter?.bind(
                    location: .global,
                    order: engine.nextBindingIdentifier + 1,
                    settle: bindingSettlement
                )
            )
            engine.environmentGlobals[member.name] = RegisteredEnvironmentGlobal(
                bindingIdentifier: nil,
                description: .value(
                    EnvironmentValueDescription(
                        name: member.name,
                        type: type,
                        documentation: member.documentation,
                        isReadOnly: setter == nil
                    )
                )
            )
        case let .runtimeProperty(type, getter, setter):
            let global = engine.globalObject()
            _ = try engine.defineBoundProperty(
                member.name,
                on: global.raw,
                getter: getter.bind(
                    location: .global,
                    order: engine.nextBindingIdentifier,
                    settle: bindingSettlement
                ),
                setter: setter?.bind(
                    location: .global,
                    order: engine.nextBindingIdentifier + 1,
                    settle: bindingSettlement
                )
            )
            engine.environmentGlobals[member.name] = RegisteredEnvironmentGlobal(
                bindingIdentifier: nil,
                description: .value(
                    EnvironmentValueDescription(
                        name: member.name,
                        type: type,
                        documentation: member.documentation,
                        isReadOnly: setter == nil
                    )
                )
            )
        case let .value(type, encode):
            try engine.withEngineEntry {
                let value = try encode(engine)
                try engine.setProperty(named: member.name, on: 0, to: value)
                engine.environmentGlobals[member.name] = RegisteredEnvironmentGlobal(
                    bindingIdentifier: nil,
                    description: .value(
                        EnvironmentValueDescription(
                            name: member.name,
                            type: type,
                            documentation: member.documentation,
                            isReadOnly: false
                        )
                    )
                )
            }
        case .liveValue:
            throw JavaScriptError(
                kind: .internalFailure,
                message: "A validated runtime template contained a live JavaScript value."
            )
        }
    }

    private func reserveCapacity(for plan: RuntimeTemplateProvisioningPlan) {
        reserveCapacity(for: plan.definitions)
        engine.reserveProvisioningCapacity(
            bindings: 0,
            globals: 0,
            modules: 0,
            moduleSources: plan.moduleSources.count,
            programs: plan.programs.count
        )
    }

    private func reserveCapacity(for definitions: [RuntimeTemplateDefinition]) {
        engine.reserveProvisioningCapacity(
            bindings: definitions.reduce(0) { $0 + $1.bindingCount },
            globals: definitions.reduce(0) { $0 + $1.globalCount },
            modules: definitions.reduce(0) { $0 + $1.moduleCount },
            moduleSources: 0,
            programs: 0
        )
    }
}

private extension RuntimeTemplateDefinition {
    var members: [JavaScriptExportMemberDefinition] {
        switch self {
        case let .globals(value), let .object(_, _, _, value), let .module(_, _, value):
            return value
        }
    }

    var bindingCount: Int {
        members.reduce(0) { count, member in
            if case .function = member.storage { return count + 1 }
            return count
        }
    }

    var globalCount: Int {
        switch self {
        case let .globals(value): return value.count
        case .object: return 1
        case .module: return 0
        }
    }

    var moduleCount: Int {
        if case .module = self { return 1 }
        return 0
    }
}
