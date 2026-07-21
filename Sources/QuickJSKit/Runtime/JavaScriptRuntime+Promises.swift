extension JavaScriptRuntime {
    internal func decodeAwaitingPromise<T: Decodable & Sendable>(
        _ type: T.Type,
        from raw: ManagedQuickJSValue,
        maximumNestingDepth: Int,
        sourceURL: String? = nil,
        alreadyObserved: Bool = false,
        jobsAlreadyDrained: Bool = false,
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> T {
        if !alreadyObserved { engine.markPromiseObserved(raw) }
        defer { engine.unmarkPromiseObserved(raw) }
        if !jobsAlreadyDrained { try engine.drainPendingJobs() }
        guard let state = engine.promiseState(of: raw) else {
            return try decodeValue(
                type,
                from: raw,
                maximumNestingDepth: maximumNestingDepth,
                sourceURL: sourceURL,
                options: options
            )
        }
        if state == 1 {
            let result = engine.promiseResult(of: raw)
            return try decodeValue(
                type,
                from: result,
                maximumNestingDepth: maximumNestingDepth,
                sourceURL: sourceURL,
                options: options
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
                    poll: { engine, promise in
                        guard let state = engine.promiseState(of: promise), state != 0 else {
                            return false
                        }
                        if state == 2 {
                            continuation.resume(
                                throwing: engine.errorFromRejectedPromise(promise)
                                    .withSourceURL(sourceURL)
                            )
                            return true
                        }
                        do {
                            let result = engine.promiseResult(of: promise)
                            continuation.resume(
                                returning: try engine.withExecution(
                                    options: options,
                                    sourceURL: sourceURL
                                ) {
                                    try engine.decode(
                                        type,
                                        from: result,
                                        maximumNestingDepth: maximumNestingDepth
                                    )
                                }
                            )
                        } catch {
                            continuation.resume(throwing: error)
                        }
                        return true
                    },
                    cancel: {
                        continuation.resume(throwing: CancellationError())
                    }
                )
                engine.installHostPromiseWaiter(waiter, identifier: waiterIdentifier)
            }
        } onCancel: {
            Task { await self.cancelHostPromiseWaiter(waiterIdentifier) }
        }
    }

    internal func decodeImmediate<T: Decodable & Sendable>(
        _ type: T.Type,
        from raw: ManagedQuickJSValue,
        maximumNestingDepth: Int,
        sourceURL: String? = nil,
        alreadyObserved: Bool = false,
        jobsAlreadyDrained: Bool = false,
        options: JavaScriptExecutionOptions = .init()
    ) throws -> T {
        if !alreadyObserved { engine.markPromiseObserved(raw) }
        defer { engine.unmarkPromiseObserved(raw) }
        if !jobsAlreadyDrained { try engine.drainPendingJobs() }
        guard let state = engine.promiseState(of: raw) else {
            return try decodeValue(
                type,
                from: raw,
                maximumNestingDepth: maximumNestingDepth,
                sourceURL: sourceURL,
                options: options
            )
        }
        if state == 1 {
            return try decodeValue(
                type,
                from: engine.promiseResult(of: raw),
                maximumNestingDepth: maximumNestingDepth,
                sourceURL: sourceURL,
                options: options
            )
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

    private func decodeValue<T: Decodable & Sendable>(
        _ type: T.Type,
        from raw: ManagedQuickJSValue,
        maximumNestingDepth: Int,
        sourceURL: String?,
        options: JavaScriptExecutionOptions
    ) throws -> T {
        try engine.withExecution(options: options, sourceURL: sourceURL) {
            try engine.decode(
                type,
                from: raw,
                maximumNestingDepth: maximumNestingDepth
            )
        }
    }

    private func cancelHostPromiseWaiter(_ identifier: UInt64) {
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
