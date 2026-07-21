extension JavaScriptRuntime {
    /// Evaluates a JavaScript script and returns its general value.
    public func evaluate(
        _ source: String,
        sourceURL: String = "<eval>",
        options: JavaScriptExecutionOptions = .init()
    ) throws -> JavaScriptValue {
        try engine.withExecution(options: options, sourceURL: sourceURL) {
            let raw = try engine.evaluateRaw(source, sourceURL: sourceURL)
            engine.markPromiseObserved(raw)
            return try makeValue(engine.decodeUntyped(raw, sourceURL: sourceURL))
        }
    }

    /// Evaluates JavaScript and immediately decodes a result that does not
    /// require external asynchronous progress.
    ///
    /// This overload is selected from a synchronous ``perform(_:)`` closure.
    /// A Promise that remains pending after the immediate job checkpoint
    /// throws ``JavaScriptError/Kind/wouldSuspend``.
    public func evaluate<T: Decodable & Sendable>(
        _ source: String,
        as type: T.Type = T.self,
        sourceURL: String = "<eval>",
        options: JavaScriptExecutionOptions = .init()
    ) throws -> T {
        try engine.withExecution(options: options, sourceURL: sourceURL, checkpoint: false) {
            let raw = try engine.evaluateRaw(source, sourceURL: sourceURL)
            try engine.drainPendingJobs()
            return try decodeImmediate(
                type,
                from: raw,
                maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
                sourceURL: sourceURL,
                jobsAlreadyDrained: true,
                options: options
            )
        }
    }

    /// Evaluates JavaScript and directly decodes its result as a Swift type.
    ///
    /// The result type may be inferred from context or selected with `as:`.
    public func evaluate<T: Decodable & Sendable>(
        _ source: String,
        as type: T.Type = T.self,
        sourceURL: String = "<eval>",
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> T {
        let raw = try engine.withExecution(
            options: options,
            sourceURL: sourceURL,
            checkpoint: true
        ) {
            let raw = try engine.evaluateRaw(source, sourceURL: sourceURL)
            engine.markPromiseObserved(raw)
            return raw
        }
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

    /// Returns a snapshot of this runtime's JavaScript heap usage.
    public func memoryUsage() -> JavaScriptMemoryUsage {
        engine.memoryUsage(allocationLimit: configuration.memoryLimit)
    }

    /// Requests an immediate QuickJS garbage-collection cycle.
    public func collectGarbage() {
        engine.collectGarbage()
    }
}
