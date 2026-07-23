internal final class JavaScriptRuntimeState {
    internal let engine: QuickJSEngine
    internal var nextRootIdentifier: UInt64 = 1
    internal var roots: [UInt64: AnyObject] = [:]
    internal var rootRetainCounts: [UInt64: UInt64] = [:]
    internal var hostRootIdentifiers: Set<UInt64> = []

    internal init(engine: QuickJSEngine) {
        self.engine = engine
    }

    deinit {
        // Runtime-local Swift roots must disappear before the engine releases
        // callbacks and destroys the QuickJS context.
        roots.removeAll()
        rootRetainCounts.removeAll()
    }
}

/// An isolated JavaScript engine and its associated object heap.
///
/// Every QuickJS operation is serialized by this actor. Independent runtimes
/// may execute concurrently, while live values always route operations back to
/// the runtime that owns them.
public actor JavaScriptRuntime {
    /// Resource limits applied when a runtime is created.
    public struct Configuration: Sendable, Hashable {
        /// The maximum number of bytes the JavaScript heap may allocate.
        public var memoryLimit: UInt64?

        /// The maximum number of bytes available to the JavaScript stack.
        public var maximumStackSize: UInt64?

        /// The default deadline for active JavaScript execution.
        ///
        /// Suspended Swift work and host Promise waiting do not consume this
        /// duration. `nil` disables execution deadlines by default.
        public var defaultExecutionTimeout: Duration?

        /// The maximum number of live Swift class or actor instances wrapped
        /// by JavaScript in this runtime.
        public var maximumHostObjectCount: UInt64?

        /// The maximum number of asynchronous JavaScript-to-Swift calls that
        /// may be pending at once.
        ///
        /// Synchronous callbacks are not counted because they complete inside
        /// the active QuickJS call. A value of zero rejects every asynchronous
        /// host call with JavaScript `RangeError`.
        public var maximumPendingHostCallCount: UInt64?

        /// Creates a runtime configuration.
        public init(
            memoryLimit: UInt64? = nil,
            maximumStackSize: UInt64? = nil,
            defaultExecutionTimeout: Duration? = nil,
            maximumHostObjectCount: UInt64? = nil,
            maximumPendingHostCallCount: UInt64? = nil
        ) {
            self.memoryLimit = memoryLimit
            self.maximumStackSize = maximumStackSize
            self.defaultExecutionTimeout = defaultExecutionTimeout
            self.maximumHostObjectCount = maximumHostObjectCount
            self.maximumPendingHostCallCount = maximumPendingHostCallCount
        }

        /// A constrained starting point for executing untrusted JavaScript.
        ///
        /// This configuration limits QuickJS memory to 64 MiB, its stack to
        /// 512 KiB, active JavaScript execution to one second, live Swift host
        /// objects to 1,024, and pending asynchronous host calls to 256.
        ///
        /// This is not an operating-system sandbox. QuickJS and exported Swift
        /// code still execute inside the application process. Use process
        /// isolation for hostile code and customize these limits for the
        /// application's workload.
        public static let restricted = Configuration(
            memoryLimit: 64 * 1_024 * 1_024,
            maximumStackSize: 512 * 1_024,
            defaultExecutionTimeout: .seconds(1),
            maximumHostObjectCount: 1_024,
            maximumPendingHostCallCount: 256
        )
    }

    /// The immutable configuration used to create this runtime.
    public nonisolated let configuration: Configuration

    internal let runtimeState: JavaScriptRuntimeState
    internal var engine: QuickJSEngine { runtimeState.engine }
    internal var moduleLoader: JavaScriptModuleLoader?
    internal var moduleLoadOperations: [String: ModuleLoadOperation] = [:]
    internal var nextModuleLoadWaiterIdentifier: UInt64 = 1

    /// Creates an isolated JavaScript runtime.
    public init(configuration: Configuration = Configuration()) throws {
        self.configuration = configuration
        let engine = try QuickJSEngine(configuration: configuration)
        self.runtimeState = JavaScriptRuntimeState(engine: engine)
        engine.attachOwner(self)
    }

    deinit {
        for operation in moduleLoadOperations.values {
            operation.task?.cancel()
            for continuation in operation.waiters.values {
                continuation.resume(throwing: CancellationError())
            }
        }
        moduleLoadOperations.removeAll()
    }

    /// A codec that directly creates JavaScript values in this runtime.
    public nonisolated var encoder: JavaScriptEncoder {
        JavaScriptEncoder(runtime: self)
    }

    /// A codec that directly reads JavaScript values from this runtime.
    public nonisolated var decoder: JavaScriptDecoder {
        JavaScriptDecoder(runtime: self)
    }

    /// A live handle to this runtime's global object.
    public nonisolated var global: JavaScriptObject {
        JavaScriptObject(
            reference: JavaScriptReference(
                runtime: self,
                identifier: 0,
                kind: .object,
                releasesOnDeinit: false
            )
        )
    }

    /// Installs or clears the observer for JavaScript promise rejections that
    /// remain unhandled after a complete microtask checkpoint.
    ///
    /// The handler executes on this runtime's actor and should return quickly.
    /// Launch a separate task for long-running work.
    public func setUnhandledPromiseRejectionHandler(
        _ handler: (@Sendable (JavaScriptError) -> Void)?
    ) {
        engine.unhandledRejectionHandler = handler
    }

    /// Installs or clears a synchronous JavaScript interruption predicate.
    ///
    /// The predicate runs while QuickJS is executing. It must return quickly,
    /// must not suspend, and must not call back into this runtime. Returning
    /// `true` interrupts the current JavaScript operation.
    public func setInterruptHandler(_ handler: (@Sendable () -> Bool)?) {
        engine.interruptHandler = handler
    }

    /// Runs a non-suspending operation while isolated to this runtime.
    ///
    /// The closure executes as one uninterrupted actor turn. Individual
    /// JavaScript calls still establish their own execution checkpoints.
    public func run<Result: Sendable>(
        _ operation: @Sendable (isolated JavaScriptRuntime) throws -> Result
    ) rethrows -> Result {
        try operation(self)
    }

    /// Runs an asynchronous operation while isolated to this runtime.
    ///
    /// The closure may suspend and is actor-reentrant at every suspension
    /// point; this overload is therefore not a transaction.
    public func run<Result: Sendable>(
        _ operation: @Sendable (isolated JavaScriptRuntime) async throws -> Result
    ) async rethrows -> Result {
        try await operation(self)
    }

    internal func releaseReference(_ identifier: UInt64) {
        do {
            try engine.withEngineEntry(drainJobs: false) {
                engine.releaseReference(identifier)
            }
        } catch {
            assertionFailure("Reference release unexpectedly failed: \(error)")
        }
    }

    internal func performBindingOperation(
        _ operation: @Sendable (
            isolated JavaScriptRuntime
        ) async -> BindingCompletion
    ) async -> BindingCompletion {
        await operation(self)
    }

    internal func retainRuntimeRoot<Root: AnyObject>(_ root: sending Root) throws -> UInt64 {
        guard runtimeState.nextRootIdentifier < UInt64.max else {
            throw JavaScriptError(
                kind: .resourceLimit,
                message: "The runtime-local root identifier space is exhausted."
            )
        }
        let identifier = runtimeState.nextRootIdentifier
        runtimeState.nextRootIdentifier += 1
        runtimeState.roots[identifier] = root
        runtimeState.rootRetainCounts[identifier] = 1
        return identifier
    }

    internal func runtimeRoot<Root: AnyObject>(
        _ identifier: UInt64,
        as type: Root.Type = Root.self
    ) throws -> Root {
        guard let root = runtimeState.roots[identifier] as? Root else {
            throw JavaScriptError(
                kind: .internalFailure,
                message: "A runtime-local Swift root is no longer available."
            )
        }
        return root
    }

    internal func retainRuntimeRootForOperation(
        from source: RuntimeRootSource,
        receiver: ManagedQuickJSValue?
    ) throws -> UInt64 {
        let identifier = try runtimeRootIdentifier(
            from: source,
            receiver: receiver
        )
        try retainRuntimeRoot(identifier)
        return identifier
    }

    internal func retainRuntimeRootForOperation(_ identifier: UInt64) throws {
        try retainRuntimeRoot(identifier)
    }

    private func retainRuntimeRoot(_ identifier: UInt64) throws {
        guard let count = runtimeState.rootRetainCounts[identifier],
              count < UInt64.max else {
            throw JavaScriptError(
                kind: .resourceLimit,
                message: "The runtime-local root retain count is exhausted."
            )
        }
        runtimeState.rootRetainCounts[identifier] = count + 1
    }

    internal func runtimeRootIdentifier(
        from source: RuntimeRootSource,
        receiver: ManagedQuickJSValue?
    ) throws -> UInt64 {
        switch source {
        case let .fixed(identifier):
            return identifier
        case let .receiver(hostTypeIdentifier):
            guard let receiver else {
                throw JavaScriptError(
                    kind: .internalFailure,
                    message: "A JavaScript receiver is required for this host member."
                )
            }
            return try engine.hostRootIdentifier(
                from: receiver.raw,
                expectedTypeIdentifier: hostTypeIdentifier
            )
        }
    }

    internal func runtimeRoot<Root: AnyObject>(
        from source: RuntimeRootSource,
        receiver: ManagedQuickJSValue?,
        as type: Root.Type = Root.self
    ) throws -> Root {
        try runtimeRoot(
            runtimeRootIdentifier(from: source, receiver: receiver),
            as: type
        )
    }

    internal func releaseRuntimeRoot(_ identifier: UInt64) {
        guard let count = runtimeState.rootRetainCounts[identifier] else {
            return
        }
        if count > 1 {
            runtimeState.rootRetainCounts[identifier] = count - 1
            return
        }
        runtimeState.rootRetainCounts.removeValue(forKey: identifier)
        runtimeState.roots.removeValue(forKey: identifier)
        runtimeState.hostRootIdentifiers.remove(identifier)
        engine.hostObjectIdentitiesByRootIdentifier.removeValue(forKey: identifier)
    }

    internal func runtimeRootObjectIdentifier(_ identifier: UInt64) throws -> ObjectIdentifier {
        guard let root = runtimeState.roots[identifier] else {
            throw JavaScriptError(
                kind: .internalFailure,
                message: "A runtime-local Swift root is no longer available."
            )
        }
        return ObjectIdentifier(root)
    }

    internal func retainHostObject<Root: AnyObject>(
        _ root: sending Root
    ) throws -> UInt64 {
        let identity = ObjectIdentifier(root)
        if let existing = engine.hostObjectsBySwiftIdentity[identity] {
            try retainRuntimeRoot(existing.rootIdentifier)
            return existing.rootIdentifier
        }
        if let limit = configuration.maximumHostObjectCount,
           UInt64(runtimeState.hostRootIdentifiers.count) >= limit {
            throw JavaScriptError(
                kind: .resourceLimit,
                message: "The runtime host object limit has been reached."
            )
        }
        let identifier = try retainRuntimeRoot(root)
        runtimeState.hostRootIdentifiers.insert(identifier)
        engine.hostObjectIdentitiesByRootIdentifier[identifier] = identity
        return identifier
    }

    internal var retainedReferenceCountForTesting: Int {
        engine.retainedReferenceCount
    }

    internal var bindingCountForTesting: Int { engine.swiftBindings.count }

    internal var pendingPromiseCountForTesting: Int { engine.pendingSwiftPromises.count }

    internal var hostWaiterCountForTesting: Int { engine.hostPromiseWaiters.count }

    internal var callbackDepthForTesting: Int { engine.callbackDepth }

    internal var stackTopRefreshCountForTesting: Int {
        engine.stackTopRefreshCountForTesting
    }

    internal var checkpointCountForTesting: Int {
        engine.checkpointCountForTesting
    }

    internal var sourceModuleCompilationCountForTesting: Int {
        engine.sourceModuleCompilationCountForTesting
    }

    internal var cachedModuleReadCountForTesting: Int {
        engine.cachedModuleReadCountForTesting
    }

    internal var preparedProgramCompilationCountForTesting: Int {
        engine.preparedProgramCompilationCountForTesting
    }

    internal var cachedProgramReadCountForTesting: Int {
        engine.cachedProgramReadCountForTesting
    }

    internal var templateCacheFallbackCountForTesting: Int {
        engine.templateCacheFallbackCountForTesting
    }

    internal var bindingDescriptionsForTesting: [BindingDescription] {
        engine.swiftBindings.values.compactMap(\.function?.description)
    }

    internal func isBindingActive(_ identifier: UInt64) -> Bool {
        engine.isBindingActive(identifier)
    }

    internal func removeBinding(
        _ identifier: UInt64,
        cancellingInFlight: Bool
    ) throws -> Bool {
        try engine.withEngineEntry() {
            try engine.removeBinding(
                identifier,
                cancellingInFlight: cancellingInFlight
            )
        }
    }

}
