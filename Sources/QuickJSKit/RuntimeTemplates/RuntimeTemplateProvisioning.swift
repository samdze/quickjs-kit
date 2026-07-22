internal struct RuntimeTemplateModuleSource: Sendable {
    internal let source: String
    internal let specifier: String
    internal let sourceURL: String
    internal let documentation: TypeScriptDocumentation?
    internal let typeScriptDeclarations: TypeScriptModuleDeclarations?
    internal var compiledArtifact: [UInt8]?

    internal var environmentDescription: EnvironmentModuleDescription {
        .source(
            specifier: specifier,
            documentation: documentation,
            declarations: typeScriptDeclarations
        )
    }
}

internal struct RuntimeTemplateProgram: Sendable {
    internal let program: JavaScriptProgram
    internal var compiledArtifact: [UInt8]?
}

internal enum RuntimeTemplateStartupAction: Sendable {
    case program(JavaScriptProgram, options: JavaScriptExecutionOptions)
    case preloadModule(String)
    case importModule(String, options: JavaScriptExecutionOptions)
}

internal enum RuntimeTemplateDefinition: Sendable {
    case globals(
        members: [JavaScriptExportMemberDefinition],
        types: [AnyJavaScriptTypeDefinition]
    )
    case object(
        name: String,
        documentation: TypeScriptDocumentation?,
        root: (any AnyObject & Sendable)?,
        members: [JavaScriptExportMemberDefinition],
        types: [AnyJavaScriptTypeDefinition]
    )
    case module(
        specifier: String,
        documentation: TypeScriptDocumentation?,
        members: [JavaScriptExportMemberDefinition],
        types: [AnyJavaScriptTypeDefinition]
    )
}

internal extension RuntimeTemplateDefinition {
    var containsHostTypes: Bool {
        let types: [AnyJavaScriptTypeDefinition] = switch self {
        case let .globals(_, types), let .object(_, _, _, _, types),
             let .module(_, _, _, types): types
        }
        return types.contains {
            if case .host = $0 { return true }
            return false
        }
    }
}

internal struct RuntimeTemplateInstanceDefinition: Sendable {
    internal let globals: [EnvironmentGlobalDescription]
    internal let modules: [EnvironmentModuleDescription]
    internal let validationMessages: [String]
    internal let install: @Sendable (
        isolated JavaScriptRuntime
    ) async throws -> Void
}

internal struct RuntimeTemplateProvisioningPlan: Sendable {
    internal let configuration: JavaScriptRuntime.Configuration
    internal let definitions: [RuntimeTemplateDefinition]
    internal let moduleSources: [RuntimeTemplateModuleSource]
    internal let moduleLoader: JavaScriptModuleLoader?
    internal let instances: [RuntimeTemplateInstanceDefinition]
    internal let programs: [RuntimeTemplateProgram]
    internal let startupActions: [RuntimeTemplateStartupAction]
    internal let environment: JavaScriptEnvironmentDescription

    internal init(
        configuration: JavaScriptRuntime.Configuration,
        component: JavaScriptRuntimeTemplate.Component
    ) throws {
        guard component.moduleLoaders.count <= 1 else {
            throw JavaScriptError(
                kind: .conversion,
                message: "A runtime template can define only one module loader."
            )
        }

        try Self.validateDefinitions(component.definitions)
        try Self.validateModuleSources(component.moduleSources)
        if let message = component.instances.lazy
            .flatMap(\.validationMessages)
            .first {
            throw JavaScriptError(kind: .conversion, message: message)
        }

        let definitionGlobals = component.definitions.flatMap(\.environmentGlobals)
        let instanceGlobals = component.instances.flatMap(\.globals)
        try Self.validateUniqueNames(
            (definitionGlobals + instanceGlobals).map(\.name),
            message: "A runtime template cannot contain duplicate global names."
        )

        let definitionModules = component.definitions.compactMap(\.environmentModule)
        let instanceModules = component.instances.flatMap(\.modules)
        let sourceModules = component.moduleSources.map(\.environmentDescription)
        let modules = definitionModules + instanceModules + sourceModules
        try Self.validateUniqueNames(
            modules.map(\.specifier),
            message: "A runtime template cannot contain duplicate module specifiers."
        )

        let programs = try Self.normalizedPrograms(component.programs)
        try Self.validateStartupActions(
            component.startupActions,
            knownModuleSpecifiers: Set(modules.map(\.specifier)),
            hasModuleLoader: component.moduleLoaders.first != nil
        )

        self.configuration = configuration
        self.definitions = component.definitions
        self.moduleSources = component.moduleSources
        self.moduleLoader = component.moduleLoaders.first
        self.instances = component.instances
        self.programs = programs.map {
            RuntimeTemplateProgram(program: $0, compiledArtifact: nil)
        }
        self.startupActions = component.startupActions
        self.environment = JavaScriptEnvironmentDescription(
            globals: definitionGlobals + instanceGlobals,
            modules: modules,
            additionalSchemas: []
        )
    }

    internal func environmentDescription(
        including additionalSchemas: [TypeScriptSchema]
    ) -> JavaScriptEnvironmentDescription {
        JavaScriptEnvironmentDescription(
            globals: environment.globals,
            modules: environment.modules,
            additionalSchemas: additionalSchemas
        )
    }

    private static func validateDefinitions(
        _ definitions: [RuntimeTemplateDefinition]
    ) throws {
        var publishedTypeIdentities: Set<ObjectIdentifier> = []
        for definition in definitions {
            switch definition {
            case let .globals(members, types):
                try validateMembers(members, container: "global definitions")
                try validateTypes(types, location: .global)
                try validateUniqueNames(
                    members.map(\.name) + types.map(\.name),
                    message: "A global JavaScript name cannot be published more than once."
                )
                try collectUniqueTypeIdentities(
                    types,
                    into: &publishedTypeIdentities
                )
            case let .object(name, documentation, _, members, types):
                if let message = BindingValidation.nameMessage(name, role: "Export names") {
                    throw JavaScriptError(kind: .conversion, message: message)
                }
                try validateDocumentation(documentation)
                try validateMembers(members, container: "an object export")
                guard types.isEmpty else {
                    throw JavaScriptError(
                        kind: .conversion,
                        message: "JavaScript types can be published only as globals or module exports."
                    )
                }
            case let .module(specifier, documentation, members, types):
                try validateModuleSpecifier(specifier)
                try validateDocumentation(documentation)
                try validateMembers(members, container: "a Swift module")
                try validateTypes(types, location: .module(specifier))
                try validateUniqueNames(
                    members.map(\.name) + types.map(\.name),
                    message: "A Swift module export name cannot be published more than once."
                )
                try collectUniqueTypeIdentities(
                    types,
                    into: &publishedTypeIdentities
                )
            }
        }
    }

    private static func collectUniqueTypeIdentities(
        _ types: [AnyJavaScriptTypeDefinition],
        into identities: inout Set<ObjectIdentifier>
    ) throws {
        for type in types {
            guard identities.insert(type.swiftIdentity).inserted else {
                throw JavaScriptError(
                    kind: .conversion,
                    message: "A Swift type can have only one runtime location in a JavaScript environment."
                )
            }
        }
    }

    private static func validateTypes(
        _ types: [AnyJavaScriptTypeDefinition],
        location: JavaScriptTypeLocation
    ) throws {
        try validateUniqueNames(
            types.map(\.name),
            message: "A JavaScript environment cannot publish the same type name more than once."
        )
        for type in types {
            if let message = BindingValidation.nameMessage(
                type.name,
                role: "JavaScript type names"
            ) {
                throw JavaScriptError(kind: .conversion, message: message)
            }
            let scope: TypeScriptDeclarationScope?
            switch type {
            case let .value(definition): scope = definition.schema.scope
            case let .host(definition): scope = definition.scope
            }
            guard let scope else { continue }
            let matches: Bool
            switch (scope, location) {
            case (.global, .global): matches = true
            case let (.module(expected), .module(actual)): matches = expected == actual
            default: matches = false
            }
            guard matches else {
                throw JavaScriptError(
                    kind: .conversion,
                    message: "JavaScript type '\(type.name)' has a TypeScript scope that does not match its runtime location."
                )
            }
        }
    }

    private static func validateModuleSources(
        _ sources: [RuntimeTemplateModuleSource]
    ) throws {
        for source in sources {
            try validateModuleSpecifier(source.specifier)
            try validateDocumentation(source.documentation)
        }
        try validateUniqueNames(
            sources.map(\.specifier),
            message: "A runtime template cannot register one source module more than once."
        )
    }

    private static func validateMembers(
        _ members: [JavaScriptExportMemberDefinition],
        container: String
    ) throws {
        if let message = members.lazy.compactMap(\.validationMessage).first {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        try validateUniqueNames(
            members.map(\.name),
            message: "A runtime template cannot contain duplicate member names in \(container)."
        )
        for member in members {
            if case .liveValue = member.storage {
                throw JavaScriptError(
                    kind: .conversion,
                    message: "Runtime templates cannot contain live JavaScript values."
                )
            }
        }
    }

    private static func validateDocumentation(
        _ documentation: TypeScriptDocumentation?
    ) throws {
        if let message = TypeScriptDocumentationValidation.message(for: documentation) {
            throw JavaScriptError(kind: .conversion, message: message)
        }
    }

    private static func validateModuleSpecifier(_ specifier: String) throws {
        if let message = BindingValidation.nameMessage(
            specifier,
            role: "Module specifiers"
        ) {
            throw JavaScriptError(kind: .module, message: message)
        }
    }

    private static func validateUniqueNames(
        _ names: [String],
        message: String
    ) throws {
        guard !BindingValidation.hasDuplicateNames(names) else {
            throw JavaScriptError(kind: .conversion, message: message)
        }
    }

    private static func normalizedPrograms(
        _ programs: [JavaScriptProgram]
    ) throws -> [JavaScriptProgram] {
        var identifiers: Set<ObjectIdentifier> = []
        var result: [JavaScriptProgram] = []
        result.reserveCapacity(programs.count)
        for program in programs {
            guard !program.sourceURL.isEmpty, !program.sourceURL.contains("\0") else {
                throw JavaScriptError(
                    kind: .conversion,
                    message: "Program source URLs must be non-empty and contain no NUL characters."
                )
            }
            if identifiers.insert(ObjectIdentifier(program.identity)).inserted {
                result.append(program)
            }
        }
        return result
    }

    private static func validateStartupActions(
        _ actions: [RuntimeTemplateStartupAction],
        knownModuleSpecifiers: Set<String>,
        hasModuleLoader: Bool
    ) throws {
        for action in actions {
            let specifier: String?
            switch action {
            case .program:
                specifier = nil
            case let .preloadModule(value), let .importModule(value, _):
                specifier = value
            }
            guard let specifier else { continue }
            try validateModuleSpecifier(specifier)
            guard knownModuleSpecifiers.contains(specifier) || hasModuleLoader else {
                throw JavaScriptError(
                    kind: .module,
                    message: "Startup module '\(specifier)' is not defined by the template and no module loader is configured."
                )
            }
        }
    }
}

extension RuntimeTemplateProvisioningPlan {
    internal func compilingArtifacts() throws -> Self {
        guard !moduleSources.isEmpty || !programs.isEmpty else { return self }
        let compiler = try QuickJSEngine(configuration: .init())
        var compiledSources: [RuntimeTemplateModuleSource] = []
        compiledSources.reserveCapacity(moduleSources.count)

        for var source in moduleSources {
            source.compiledArtifact = try compiler.withEngineEntry(drainJobs: false) {
                try compiler.compileModuleArtifact(
                    source: source.source,
                    specifier: source.specifier,
                    sourceURL: source.sourceURL
                )
            }
            compiledSources.append(source)
        }

        var compiledPrograms: [RuntimeTemplateProgram] = []
        compiledPrograms.reserveCapacity(programs.count)
        for var program in programs {
            program.compiledArtifact = try compiler.withEngineEntry(drainJobs: false) {
                try compiler.compileProgramArtifact(program.program)
            }
            compiledPrograms.append(program)
        }

        return RuntimeTemplateProvisioningPlan(
            configuration: configuration,
            definitions: definitions,
            moduleSources: compiledSources,
            moduleLoader: moduleLoader,
            instances: instances,
            programs: compiledPrograms,
            startupActions: startupActions,
            environment: environment
        )
    }

    internal func replacingFirstCompiledArtifactForTesting(
        with bytes: [UInt8]
    ) -> Self {
        var sources = moduleSources
        guard !sources.isEmpty else { return self }
        sources[0].compiledArtifact = bytes
        return RuntimeTemplateProvisioningPlan(
            configuration: configuration,
            definitions: definitions,
            moduleSources: sources,
            moduleLoader: moduleLoader,
            instances: instances,
            programs: programs,
            startupActions: startupActions,
            environment: environment
        )
    }

    internal func replacingFirstCompiledProgramForTesting(
        with bytes: [UInt8]
    ) -> Self {
        var values = programs
        guard !values.isEmpty else { return self }
        values[0].compiledArtifact = bytes
        return RuntimeTemplateProvisioningPlan(
            configuration: configuration,
            definitions: definitions,
            moduleSources: moduleSources,
            moduleLoader: moduleLoader,
            instances: instances,
            programs: values,
            startupActions: startupActions,
            environment: environment
        )
    }

    private init(
        configuration: JavaScriptRuntime.Configuration,
        definitions: [RuntimeTemplateDefinition],
        moduleSources: [RuntimeTemplateModuleSource],
        moduleLoader: JavaScriptModuleLoader?,
        instances: [RuntimeTemplateInstanceDefinition],
        programs: [RuntimeTemplateProgram],
        startupActions: [RuntimeTemplateStartupAction],
        environment: JavaScriptEnvironmentDescription
    ) {
        self.configuration = configuration
        self.definitions = definitions
        self.moduleSources = moduleSources
        self.moduleLoader = moduleLoader
        self.instances = instances
        self.programs = programs
        self.startupActions = startupActions
        self.environment = environment
    }
}

private extension RuntimeTemplateDefinition {
    var environmentGlobals: [EnvironmentGlobalDescription] {
        switch self {
        case let .globals(members, types):
            return members.map(\.environmentGlobalDescription)
                + types.map { .type($0.environmentDescription(at: .global)) }
        case let .object(name, documentation, _, members, _):
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

    var environmentModule: EnvironmentModuleDescription? {
        guard case let .module(specifier, documentation, members, types) = self else {
            return nil
        }
        return .swift(
            specifier: specifier,
            documentation: documentation,
            members: members.map(\.environmentDescription)
                + types.map {
                    .type($0.environmentDescription(at: .module(specifier)))
                }
        )
    }
}

private extension JavaScriptExportMemberDefinition {
    var environmentGlobalDescription: EnvironmentGlobalDescription {
        switch environmentDescription {
        case let .function(function):
            return .function(function)
        case let .type(type):
            return .type(type)
        case let .value(value):
            return .value(
                EnvironmentValueDescription(
                    name: value.name,
                    type: value.type,
                    documentation: value.documentation,
                    isReadOnly: false
                )
            )
        }
    }
}
