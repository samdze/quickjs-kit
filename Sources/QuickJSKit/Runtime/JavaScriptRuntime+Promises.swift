extension JavaScriptRuntime {
    internal func decodeRoot<T: Decodable & Sendable>(
        _ type: T.Type,
        maximumNestingDepth: Int,
        sourceURL: String? = nil,
        options: JavaScriptExecutionOptions = .init(),
        produce: () throws -> ManagedQuickJSValue
    ) async throws -> T {
        try await readRoot(
            sourceURL: sourceURL,
            options: options,
            produce: produce
        ) { value in
            try self.engine.decode(
                type,
                from: value,
                maximumNestingDepth: maximumNestingDepth
            )
        }
    }

    internal func decodeRootImmediately<T: Decodable & Sendable>(
        _ type: T.Type,
        maximumNestingDepth: Int,
        sourceURL: String? = nil,
        options: JavaScriptExecutionOptions = .init(),
        produce: () throws -> ManagedQuickJSValue
    ) throws -> T {
        try readRootImmediately(
            sourceURL: sourceURL,
            options: options,
            produce: produce
        ) { value in
            try engine.decode(
                type,
                from: value,
                maximumNestingDepth: maximumNestingDepth
            )
        }
    }

    internal func readRoot<Result: Sendable>(
        sourceURL: String? = nil,
        options: JavaScriptExecutionOptions = .init(),
        produce: () throws -> ManagedQuickJSValue,
        transform: @escaping (ManagedQuickJSValue) throws -> Result
    ) async throws -> Result {
        let waiterIdentifier = engine.allocateHostWaiterIdentifier()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                do {
                    try engine.withEngineEntry(
                        options: options,
                        sourceURL: sourceURL,
                        drainJobs: false
                    ) {
                        let raw = try produce()
                        engine.markPromiseObserved(raw)
                        do {
                            try engine.drainPendingJobs()
                            guard let state = engine.promiseState(of: raw) else {
                                let result = try transform(raw)
                                engine.unmarkPromiseObserved(raw)
                                continuation.resume(returning: result)
                                return
                            }
                            switch state {
                            case .fulfilled:
                                let result = try transform(engine.promiseResult(of: raw))
                                engine.unmarkPromiseObserved(raw)
                                continuation.resume(returning: result)
                                return
                            case .rejected:
                                let error = engine.errorFromRejectedPromise(raw)
                                    .withSourceURL(sourceURL)
                                engine.unmarkPromiseObserved(raw)
                                continuation.resume(throwing: error)
                                return
                            case .pending:
                                break
                            }

                            let waiter = HostPromiseWaiter(
                                promise: raw,
                                poll: { engine, promise in
                                    guard let state = engine.promiseState(of: promise) else {
                                        return false
                                    }
                                    switch state {
                                    case .pending:
                                        return false
                                    case .fulfilled:
                                        defer { engine.unmarkPromiseObserved(promise) }
                                        do {
                                            continuation.resume(
                                                returning: try transform(
                                                    engine.promiseResult(of: promise)
                                                )
                                            )
                                        } catch {
                                            continuation.resume(throwing: error)
                                        }
                                        return true
                                    case .rejected:
                                        defer { engine.unmarkPromiseObserved(promise) }
                                        continuation.resume(
                                            throwing: engine.errorFromRejectedPromise(promise)
                                                .withSourceURL(sourceURL)
                                        )
                                        return true
                                    }
                                },
                                cancel: { engine in
                                    engine.unmarkPromiseObserved(raw)
                                    continuation.resume(throwing: CancellationError())
                                }
                            )
                            engine.installHostPromiseWaiter(
                                waiter,
                                identifier: waiterIdentifier
                            )
                        } catch {
                            engine.unmarkPromiseObserved(raw)
                            throw error
                        }
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            Task { await self.cancelRootWaiter(waiterIdentifier) }
        }
    }

    internal func readRootImmediately<Result>(
        sourceURL: String? = nil,
        options: JavaScriptExecutionOptions = .init(),
        produce: () throws -> ManagedQuickJSValue,
        transform: (ManagedQuickJSValue) throws -> Result
    ) throws -> Result {
        try engine.withEngineEntry(
            options: options,
            sourceURL: sourceURL,
            drainJobs: false
        ) {
            let raw = try produce()
            engine.markPromiseObserved(raw)
            defer { engine.unmarkPromiseObserved(raw) }
            try engine.drainPendingJobs()
            guard let state = engine.promiseState(of: raw) else {
                return try transform(raw)
            }
            switch state {
            case .fulfilled:
                return try transform(engine.promiseResult(of: raw))
            case .rejected:
                throw engine.errorFromRejectedPromise(raw).withSourceURL(sourceURL)
            case .pending:
                throw JavaScriptError(
                    kind: .wouldSuspend,
                    message: "The JavaScript result requires asynchronous progress.",
                    sourceURL: sourceURL
                )
            }
        }
    }

    private func cancelRootWaiter(_ identifier: UInt64) {
        reportEngineEntryFailure {
            engine.cancelHostPromiseWaiter(identifier)
        }
    }
}
