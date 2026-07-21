internal final class ModuleLoadOperation {
    internal var task: Task<Void, Never>?
    internal var waiters: [UInt64: CheckedContinuation<Void, any Error>] = [:]
}

internal enum ModuleLoadResult: Sendable {
    case success(JavaScriptModuleSource)
    case failure(JavaScriptError)
}

extension JavaScriptRuntime {
    /// Registers runtime-local ES module source.
    public func registerModule(
        _ source: String,
        as specifier: String,
        sourceURL: String? = nil
    ) throws {
        try engine.registerModuleSource(
            source,
            specifier: specifier,
            sourceURL: sourceURL ?? specifier
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
        try await preloadResolvedModule(canonical)
    }

    /// Imports an ES module and returns its canonical live namespace.
    public func importModule(
        _ specifier: String,
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> JavaScriptModule {
        let canonical = try engine.resolveModuleSpecifier(specifier, referrer: nil)
        try await preloadResolvedModule(canonical)
        return try await importResolvedModule(canonical, options: options)
    }

    /// Imports an ES module and decodes its namespace as a Swift type.
    public func importModule<T: Decodable & Sendable>(
        _ specifier: String,
        as type: T.Type = T.self,
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> T {
        let canonical = try engine.resolveModuleSpecifier(specifier, referrer: nil)
        try await preloadResolvedModule(canonical)
        let raw = try engine.loadModule(canonical, options: options)
        return try await decodeAwaitingPromise(
            type,
            from: raw,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            sourceURL: engine.moduleSources[canonical]?.sourceURL,
            alreadyObserved: true,
            jobsAlreadyDrained: true,
            options: options
        )
    }

    /// Imports a registered or preloaded module without suspending.
    ///
    /// A module whose top-level evaluation remains pending throws
    /// ``JavaScriptError/Kind/wouldSuspend``.
    public func importModule(
        _ specifier: String,
        options: JavaScriptExecutionOptions = .init()
    ) throws -> JavaScriptModule {
        let canonical = try engine.resolveModuleSpecifier(specifier, referrer: nil)
        return try importResolvedModuleImmediately(canonical, options: options)
    }

    /// Imports and immediately decodes a registered or preloaded namespace.
    public func importModule<T: Decodable & Sendable>(
        _ specifier: String,
        as type: T.Type = T.self,
        options: JavaScriptExecutionOptions = .init()
    ) throws -> T {
        let canonical = try engine.resolveModuleSpecifier(specifier, referrer: nil)
        let raw = try engine.loadModule(canonical, options: options)
        return try decodeImmediate(
            type,
            from: raw,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            sourceURL: engine.moduleSources[canonical]?.sourceURL,
            alreadyObserved: true,
            jobsAlreadyDrained: true,
            options: options
        )
    }

    /// Evaluates transient ES module source and returns its namespace.
    public func evaluateModule(
        _ source: String,
        sourceURL: String = "<module>",
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> JavaScriptModule {
        let specifier = engine.allocateTransientModuleSpecifier()
        try engine.registerModuleSource(source, specifier: specifier, sourceURL: sourceURL)
        try await preloadResolvedModule(specifier)
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
        try engine.registerModuleSource(source, specifier: specifier, sourceURL: sourceURL)
        try await preloadResolvedModule(specifier)
        let raw = try engine.loadModule(specifier, options: options)
        return try await decodeAwaitingPromise(
            type,
            from: raw,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            sourceURL: sourceURL,
            alreadyObserved: true,
            jobsAlreadyDrained: true,
            options: options
        )
    }

    /// Evaluates transient ES module source without suspending.
    public func evaluateModule(
        _ source: String,
        sourceURL: String = "<module>",
        options: JavaScriptExecutionOptions = .init()
    ) throws -> JavaScriptModule {
        let specifier = engine.allocateTransientModuleSpecifier()
        try engine.registerModuleSource(source, specifier: specifier, sourceURL: sourceURL)
        return try importResolvedModuleImmediately(specifier, options: options)
    }

    /// Evaluates and immediately decodes transient ES module source.
    public func evaluateModule<T: Decodable & Sendable>(
        _ source: String,
        as type: T.Type = T.self,
        sourceURL: String = "<module>",
        options: JavaScriptExecutionOptions = .init()
    ) throws -> T {
        let specifier = engine.allocateTransientModuleSpecifier()
        try engine.registerModuleSource(source, specifier: specifier, sourceURL: sourceURL)
        let raw = try engine.loadModule(specifier, options: options)
        return try decodeImmediate(
            type,
            from: raw,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            sourceURL: sourceURL,
            alreadyObserved: true,
            jobsAlreadyDrained: true,
            options: options
        )
    }

    private func preloadResolvedModule(_ specifier: String) async throws {
        if engine.preloadedModuleSpecifiers.contains(specifier) { return }
        if !engine.hasModuleSource(specifier) {
            try await loadModuleSource(
                JavaScriptModuleRequest(specifier: specifier, referrer: nil)
            )
        }

        while true {
            let discovery = try engine.withExecution(
                options: .init(),
                sourceURL: engine.moduleSources[specifier]?.sourceURL,
                checkpoint: false
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
                let operation: ModuleLoadOperation
                if let existing = moduleLoadOperations[request.specifier] {
                    operation = existing
                } else {
                    operation = ModuleLoadOperation()
                    moduleLoadOperations[request.specifier] = operation
                    operation.task = Task { [weak self] in
                        let result: ModuleLoadResult
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
                }
                operation.waiters[waiterIdentifier] = continuation
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
        result: ModuleLoadResult
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
        guard let operation = moduleLoadOperations[specifier],
              let continuation = operation.waiters.removeValue(forKey: identifier) else {
            return
        }
        continuation.resume(throwing: CancellationError())
        if operation.waiters.isEmpty {
            operation.task?.cancel()
            moduleLoadOperations.removeValue(forKey: specifier)
        }
    }

    private func importResolvedModule(
        _ specifier: String,
        options: JavaScriptExecutionOptions
    ) async throws -> JavaScriptModule {
        let raw = try engine.loadModule(specifier, options: options)
        let value = try await valueAwaitingPromise(raw, sourceURL: engine.moduleSources[specifier]?.sourceURL)
        return try module(specifier: specifier, from: value)
    }

    private func importResolvedModuleImmediately(
        _ specifier: String,
        options: JavaScriptExecutionOptions
    ) throws -> JavaScriptModule {
        let raw = try engine.loadModule(specifier, options: options)
        return try module(
            specifier: specifier,
            from: valueImmediately(
                raw,
                sourceURL: engine.moduleSources[specifier]?.sourceURL
            )
        )
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

    private func valueImmediately(
        _ raw: ManagedQuickJSValue,
        sourceURL: String?
    ) throws -> JavaScriptValue {
        defer { engine.unmarkPromiseObserved(raw) }
        guard let state = engine.promiseState(of: raw) else {
            return makeValue(try engine.decodeUntyped(raw, sourceURL: sourceURL))
        }
        if state == 1 {
            return makeValue(
                try engine.decodeUntyped(engine.promiseResult(of: raw), sourceURL: sourceURL)
            )
        }
        if state == 2 {
            throw engine.errorFromRejectedPromise(raw).withSourceURL(sourceURL)
        }
        throw JavaScriptError(
            kind: .wouldSuspend,
            message: "The module requires asynchronous progress.",
            sourceURL: sourceURL
        )
    }

    private func valueAwaitingPromise(
        _ raw: ManagedQuickJSValue,
        sourceURL: String?
    ) async throws -> JavaScriptValue {
        defer { engine.unmarkPromiseObserved(raw) }
        guard let state = engine.promiseState(of: raw) else {
            return makeValue(try engine.decodeUntyped(raw, sourceURL: sourceURL))
        }
        if state == 1 {
            return makeValue(
                try engine.decodeUntyped(engine.promiseResult(of: raw), sourceURL: sourceURL)
            )
        }
        if state == 2 {
            throw engine.errorFromRejectedPromise(raw).withSourceURL(sourceURL)
        }

        let waiterIdentifier = engine.allocateHostWaiterIdentifier()
        let producer = engine.producerOperationIdentifier(for: raw)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let waiter = HostPromiseWaiter(
                    promise: raw,
                    producerOperationIdentifier: producer,
                    poll: { [weak self] engine, promise in
                        guard let self,
                              let state = engine.promiseState(of: promise),
                              state != 0 else {
                            return false
                        }
                        if state == 2 {
                            continuation.resume(
                                throwing: engine.errorFromRejectedPromise(promise)
                                    .withSourceURL(sourceURL)
                            )
                        } else {
                            do {
                                continuation.resume(
                                    returning: self.makeValue(
                                        try engine.decodeUntyped(
                                            engine.promiseResult(of: promise),
                                            sourceURL: sourceURL
                                        )
                                    )
                                )
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        }
                        return true
                    },
                    cancel: { continuation.resume(throwing: CancellationError()) }
                )
                engine.installHostPromiseWaiter(waiter, identifier: waiterIdentifier)
            }
        } onCancel: {
            Task { await self.cancelModulePromiseWaiter(waiterIdentifier) }
        }
    }

    private func cancelModulePromiseWaiter(_ identifier: UInt64) {
        do {
            try engine.withExecution(options: .init()) {
                engine.cancelHostPromiseWaiter(identifier)
            }
        } catch let error as JavaScriptError {
            engine.unhandledRejectionHandler?(error)
        } catch {
            engine.unhandledRejectionHandler?(
                JavaScriptError(kind: .internalFailure, message: String(describing: error))
            )
        }
    }
}
