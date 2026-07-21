internal struct ModuleLoadOperation: Sendable {
    internal var task: Task<Void, Never>?
    internal var waiters: [UInt64: CheckedContinuation<Void, any Error>] = [:]
}

extension JavaScriptRuntime {
    /// Registers runtime-local ES module source and optional tooling metadata.
    ///
    /// Companion declarations describe the body inside the ambient module
    /// block generated for the canonical specifier. QuickJSKit never infers
    /// declarations from JavaScript source.
    ///
    /// - Parameters:
    ///   - source: ES module source code.
    ///   - specifier: The canonical runtime-local module specifier.
    ///   - sourceURL: An optional diagnostic and `import.meta.url` identity.
    ///   - documentation: Structured TSDoc for the source module container.
    ///   - typeScriptDeclarations: Optional declarations for tooling snapshots.
    public func registerModule(
        _ source: String,
        as specifier: String,
        sourceURL: String? = nil,
        documentation: TypeScriptDocumentation? = nil,
        typeScriptDeclarations: TypeScriptModuleDeclarations? = nil
    ) throws {
        if let message = TypeScriptDocumentationValidation.message(for: documentation) {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        try engine.registerModuleSource(
            source,
            specifier: specifier,
            sourceURL: sourceURL ?? specifier,
            documentation: documentation,
            typeScriptDeclarations: typeScriptDeclarations
        )
    }

    /// Configures the resolver and asynchronous source loader.
    ///
    /// Configuration becomes immutable when the first module compilation
    /// begins.
    public func setModuleLoader(_ loader: JavaScriptModuleLoader?) throws {
        try engine.configureModuleResolver(loader?.resolveClosure)
        moduleLoader = loader
    }

    /// Loads and compiles a module's complete static dependency graph without
    /// evaluating it intentionally.
    public func preloadModule(_ specifier: String) async throws {
        let canonical = try engine.resolveModuleSpecifier(specifier, referrer: nil)
        try await prepareModule(canonical)
    }

    /// Imports an ES module and returns its canonical live namespace.
    public func importModule(
        _ specifier: String,
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> JavaScriptModule {
        let canonical = try engine.resolveModuleSpecifier(specifier, referrer: nil)
        try await prepareModule(canonical)
        return try await importResolvedModule(canonical, options: options)
    }

    /// Imports an ES module and decodes its namespace as a Swift type.
    public func importModule<T: Decodable & Sendable>(
        _ specifier: String,
        as type: T.Type = T.self,
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> T {
        let canonical = try engine.resolveModuleSpecifier(specifier, referrer: nil)
        try await prepareModule(canonical)
        return try await decodeRoot(
            type,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            sourceURL: engine.moduleSources[canonical]?.sourceURL,
            options: options
        ) {
            try engine.loadModule(canonical)
        }
    }

    /// Evaluates transient ES module source and returns its namespace.
    public func evaluateModule(
        _ source: String,
        sourceURL: String = "<module>",
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> JavaScriptModule {
        let specifier = engine.allocateTransientModuleSpecifier()
        try engine.registerModuleSource(
            source,
            specifier: specifier,
            sourceURL: sourceURL,
            isEnvironmentModule: false
        )
        try await prepareModule(specifier)
        return try await importResolvedModule(specifier, options: options)
    }

    /// Evaluates transient ES module source and decodes its namespace.
    public func evaluateModule<T: Decodable & Sendable>(
        _ source: String,
        as type: T.Type = T.self,
        sourceURL: String = "<module>",
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> T {
        let specifier = engine.allocateTransientModuleSpecifier()
        try engine.registerModuleSource(
            source,
            specifier: specifier,
            sourceURL: sourceURL,
            isEnvironmentModule: false
        )
        try await prepareModule(specifier)
        return try await decodeRoot(
            type,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            sourceURL: sourceURL,
            options: options
        ) {
            try engine.loadModule(specifier)
        }
    }

    private func prepareModule(_ specifier: String) async throws {
        if engine.preloadedModuleSpecifiers.contains(specifier) { return }
        if !engine.hasModuleSource(specifier) {
            try await loadModuleSource(
                JavaScriptModuleRequest(specifier: specifier, referrer: nil)
            )
        }

        while true {
            let discovery = try engine.withEngineEntry(
                options: .init(),
                sourceURL: engine.moduleSources[specifier]?.sourceURL,
                drainJobs: false
            ) {
                try engine.discoverModule(specifier)
            }
            switch discovery {
            case .ready:
                engine.preloadedModuleSpecifiers.insert(specifier)
                return
            case let .missing(request):
                try await loadModuleSource(request)
            }
        }
    }

    private func loadModuleSource(_ request: JavaScriptModuleRequest) async throws {
        if engine.hasModuleSource(request.specifier) { return }
        guard let loader = moduleLoader else {
            throw JavaScriptError(
                kind: .module,
                message: "No source or custom loader is available for module '\(request.specifier)'."
            )
        }

        let waiterIdentifier = nextModuleLoadWaiterIdentifier
        nextModuleLoadWaiterIdentifier &+= 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if moduleLoadOperations[request.specifier] == nil {
                    let task = Task { [weak self] in
                        let result: Result<JavaScriptModuleSource, JavaScriptError>
                        do {
                            result = .success(try await loader.loadClosure(request))
                        } catch is CancellationError {
                            result = .failure(
                                JavaScriptError(
                                    kind: .cancelled,
                                    name: "CancellationError",
                                    message: "Module loading was cancelled."
                                )
                            )
                        } catch {
                            result = .failure(
                                JavaScriptError(
                                    kind: .module,
                                    message: "The loader failed for module '\(request.specifier)': \(error)"
                                )
                            )
                        }
                        await self?.completeModuleLoad(
                            specifier: request.specifier,
                            result: result
                        )
                    }
                    moduleLoadOperations[request.specifier] = ModuleLoadOperation(
                        task: task
                    )
                }
                moduleLoadOperations[request.specifier]?.waiters[waiterIdentifier] = continuation
            }
        } onCancel: {
            Task {
                await self.cancelModuleLoadWaiter(
                    specifier: request.specifier,
                    identifier: waiterIdentifier
                )
            }
        }
    }

    private func completeModuleLoad(
        specifier: String,
        result: Result<JavaScriptModuleSource, JavaScriptError>
    ) {
        guard let operation = moduleLoadOperations.removeValue(forKey: specifier) else {
            return
        }
        let completion: Result<Void, any Error>
        switch result {
        case let .success(source):
            do {
                try engine.registerLoadedModuleSource(source, specifier: specifier)
                completion = .success(())
            } catch {
                completion = .failure(error)
            }
        case let .failure(error):
            completion = .failure(error)
        }
        for continuation in operation.waiters.values {
            continuation.resume(with: completion)
        }
    }

    private func cancelModuleLoadWaiter(specifier: String, identifier: UInt64) {
        guard var operation = moduleLoadOperations[specifier],
              let continuation = operation.waiters.removeValue(forKey: identifier) else {
            return
        }
        continuation.resume(throwing: CancellationError())
        if operation.waiters.isEmpty {
            operation.task?.cancel()
            moduleLoadOperations.removeValue(forKey: specifier)
        } else {
            moduleLoadOperations[specifier] = operation
        }
    }

    private func importResolvedModule(
        _ specifier: String,
        options: JavaScriptExecutionOptions
    ) async throws -> JavaScriptModule {
        let sourceURL = engine.moduleSources[specifier]?.sourceURL
        let value = try await readRoot(
            sourceURL: sourceURL,
            options: options,
            produce: { try engine.loadModule(specifier) }
        ) { raw in
            self.makeValue(try self.engine.decodeUntyped(raw, sourceURL: sourceURL))
        }
        return try module(specifier: specifier, from: value)
    }

    private func module(
        specifier: String,
        from value: JavaScriptValue
    ) throws -> JavaScriptModule {
        guard let namespace = value.objectValue else {
            throw JavaScriptError(
                kind: .module,
                message: "Module '\(specifier)' did not produce a namespace object."
            )
        }
        return JavaScriptModule(specifier: specifier, namespace: namespace)
    }

}
