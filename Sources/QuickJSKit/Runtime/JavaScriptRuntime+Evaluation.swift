extension JavaScriptRuntime {
    /// Compiles a reusable program into this runtime without executing it.
    ///
    /// Repeated preparation of the same program value is idempotent. Compiled
    /// state belongs exclusively to this runtime and is released at teardown.
    public func prepare(_ program: JavaScriptProgram) throws {
        try engine.withEngineEntry(drainJobs: false) {
            try engine.prepareProgram(program)
        }
    }

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

    /// Evaluates a prepared program and returns its general value.
    ///
    /// The first call compiles the program when it was not installed by a
    /// runtime template. Later calls reuse the retained compiled function.
    public func evaluate(
        _ program: JavaScriptProgram,
        options: JavaScriptExecutionOptions = .init()
    ) throws -> JavaScriptValue {
        try engine.withEngineEntry(
            options: options,
            sourceURL: program.sourceURL
        ) {
            let raw = try engine.evaluatePreparedProgram(program)
            engine.markPromiseObserved(raw)
            return try makeValue(
                engine.decodeUntyped(raw, sourceURL: program.sourceURL)
            )
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

    /// Evaluates a prepared program and immediately decodes its result.
    ///
    /// A Promise that remains pending after the immediate job checkpoint
    /// throws ``JavaScriptError/Kind/wouldSuspend``.
    public func evaluate<T: Decodable & Sendable>(
        _ program: JavaScriptProgram,
        as type: T.Type = T.self,
        options: JavaScriptExecutionOptions = .init()
    ) throws -> T {
        try decodeRootImmediately(
            type,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            sourceURL: program.sourceURL,
            options: options
        ) {
            try engine.evaluatePreparedProgram(program)
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

    /// Evaluates a prepared program and asynchronously decodes its result.
    ///
    /// Native Promise results are awaited through the runtime's ordinary root
    /// result path, including cancellation and rejection translation.
    public func evaluate<T: Decodable & Sendable>(
        _ program: JavaScriptProgram,
        as type: T.Type = T.self,
        options: JavaScriptExecutionOptions = .init()
    ) async throws -> T {
        try await decodeRoot(
            type,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth,
            sourceURL: program.sourceURL,
            options: options
        ) {
            try engine.evaluatePreparedProgram(program)
        }
    }

    /// Returns a snapshot of this runtime's resource usage.
    public func resourceUsage() -> JavaScriptResourceUsage {
        do {
            return try engine.withEngineEntry(drainJobs: false) {
                let usage = engine.resourceUsage(
                    allocationLimit: configuration.memoryLimit,
                    pendingHostCallLimit: configuration.maximumPendingHostCallCount
                )
                return JavaScriptResourceUsage(
                    allocatedBytes: usage.allocatedBytes,
                    allocationLimit: usage.allocationLimit,
                    usedBytes: usage.usedBytes,
                    hostObjectCount: UInt64(runtimeState.hostRootIdentifiers.count),
                    hostObjectLimit: configuration.maximumHostObjectCount,
                    pendingHostCallCount: usage.pendingHostCallCount,
                    pendingHostCallLimit: configuration.maximumPendingHostCallCount
                )
            }
        } catch {
            assertionFailure("Resource reporting unexpectedly failed: \(error)")
            return JavaScriptResourceUsage(
                allocatedBytes: 0,
                allocationLimit: configuration.memoryLimit,
                usedBytes: 0,
                hostObjectLimit: configuration.maximumHostObjectCount,
                pendingHostCallLimit: configuration.maximumPendingHostCallCount
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
