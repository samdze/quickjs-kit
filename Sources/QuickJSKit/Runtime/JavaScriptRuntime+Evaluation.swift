extension JavaScriptRuntime {
    /// Evaluates a JavaScript script and returns its general value.
    public func evaluate(
        _ source: String,
        sourceURL: String = "<eval>",
        options: JavaScriptExecutionOptions = .init()
    ) throws -> JavaScriptValue {
        try engine.withEngineEntry(options: options, sourceURL: sourceURL) {
            let raw = try engine.evaluateRaw(source, sourceURL: sourceURL)
            engine.markPromiseObserved(raw)
            return try makeValue(engine.decodeUntyped(raw, sourceURL: sourceURL))
        }
    }

    /// Evaluates JavaScript and immediately decodes a result that does not
    /// require external asynchronous progress.
    ///
    /// This overload is selected from a synchronous ``run(_:)`` closure.
    /// A Promise that remains pending after the immediate job checkpoint
    /// throws ``JavaScriptError/Kind/wouldSuspend``.
    public func evaluate<T: Decodable & Sendable>(
        _ source: String,
        as type: T.Type = T.self,
        sourceURL: String = "<eval>",
        options: JavaScriptExecutionOptions = .init()
    ) throws -> T {
        try decodeRootImmediately(
            type,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            sourceURL: sourceURL,
            options: options
        ) {
            try engine.evaluateRaw(source, sourceURL: sourceURL)
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
        try await decodeRoot(
            type,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            sourceURL: sourceURL,
            options: options
        ) {
            try engine.evaluateRaw(source, sourceURL: sourceURL)
        }
    }

    /// Returns a snapshot of this runtime's JavaScript heap usage.
    public func memoryUsage() -> JavaScriptMemoryUsage {
        do {
            return try engine.withEngineEntry(drainJobs: false) {
                engine.memoryUsage(allocationLimit: configuration.memoryLimit)
            }
        } catch {
            assertionFailure("Memory reporting unexpectedly failed: \(error)")
            return JavaScriptMemoryUsage(
                allocatedBytes: 0,
                allocationLimit: configuration.memoryLimit,
                usedBytes: 0
            )
        }
    }

    /// Requests an immediate QuickJS garbage-collection cycle.
    public func collectGarbage() {
        do {
            try engine.withEngineEntry(drainJobs: false) {
                engine.collectGarbage()
            }
        } catch {
            assertionFailure("Garbage collection unexpectedly failed: \(error)")
        }
    }
}
