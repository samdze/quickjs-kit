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

        /// Creates a runtime configuration.
        public init(
            memoryLimit: UInt64? = nil,
            maximumStackSize: UInt64? = nil,
            defaultExecutionTimeout: Duration? = nil
        ) {
            self.memoryLimit = memoryLimit
            self.maximumStackSize = maximumStackSize
            self.defaultExecutionTimeout = defaultExecutionTimeout
        }
    }

    /// The immutable configuration used to create this runtime.
    public nonisolated let configuration: Configuration

    internal let engine: QuickJSEngine
    internal var moduleLoader: JavaScriptModuleLoader?
    internal var moduleLoadOperations: [String: ModuleLoadOperation] = [:]
    internal var nextModuleLoadWaiterIdentifier: UInt64 = 1
    internal var templateRoots: [any AnyObject & Sendable] = []

    /// Creates an isolated JavaScript runtime.
    public init(configuration: Configuration = Configuration()) throws {
        self.configuration = configuration
        self.engine = try QuickJSEngine(configuration: configuration)
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
