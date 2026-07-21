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
                            if state == 1 {
                                let result = try transform(engine.promiseResult(of: raw))
                                engine.unmarkPromiseObserved(raw)
                                continuation.resume(returning: result)
                                return
                            }
                            if state == 2 {
                                let error = engine.errorFromRejectedPromise(raw)
                                    .withSourceURL(sourceURL)
                                engine.unmarkPromiseObserved(raw)
                                continuation.resume(throwing: error)
                                return
                            }

                            let waiter = HostPromiseWaiter(
                                promise: raw,
                                poll: { engine, promise in
                                    guard let state = engine.promiseState(of: promise),
                                          state != 0 else {
                                        return false
                                    }
                                    defer { engine.unmarkPromiseObserved(promise) }
                                    if state == 2 {
                                        continuation.resume(
                                            throwing: engine.errorFromRejectedPromise(promise)
                                                .withSourceURL(sourceURL)
                                        )
                                    } else {
                                        do {
                                            continuation.resume(
                                                returning: try transform(
                                                    engine.promiseResult(of: promise)
                                                )
                                            )
                                        } catch {
                                            continuation.resume(throwing: error)
                                        }
                                    }
                                    return true
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
            if state == 1 {
                return try transform(engine.promiseResult(of: raw))
            }
            if state == 2 {
                throw engine.errorFromRejectedPromise(raw).withSourceURL(sourceURL)
            }
            throw JavaScriptError(
                kind: .wouldSuspend,
                message: "The JavaScript result requires asynchronous progress.",
                sourceURL: sourceURL
            )
        }
    }

    private func cancelRootWaiter(_ identifier: UInt64) {
        reportEngineEntryFailure {
            engine.cancelHostPromiseWaiter(identifier)
        }
    }
}
