/// Maintains a bounded supply of fully prepared, independently isolated runtimes.
///
/// A provisioner transfers each runtime permanently to its caller. Runtimes are
/// never returned, reset, or reused; background work creates replacements from
/// the immutable template. This preserves the same isolation guarantees as
/// calling ``JavaScriptRuntimeTemplate/makeRuntime()`` directly.
public actor JavaScriptRuntimeProvisioner {
    /// A snapshot of provisioner capacity and demand.
    public struct Status: Sendable, Hashable {
        /// The number of prepared runtimes available immediately.
        public let readyCount: Int

        /// The number of runtime creations currently in progress.
        public let provisioningCount: Int

        /// The number of callers waiting for a runtime.
        public let waitingCount: Int

        /// Whether the provisioner has been shut down.
        public let isShutdown: Bool

        internal init(
            readyCount: Int,
            provisioningCount: Int,
            waitingCount: Int,
            isShutdown: Bool
        ) {
            self.readyCount = readyCount
            self.provisioningCount = provisioningCount
            self.waitingCount = waitingCount
            self.isShutdown = isShutdown
        }
    }

    private struct RuntimeWaiter {
        internal let continuation: CheckedContinuation<JavaScriptRuntime, any Error>
    }

    private let template: JavaScriptRuntimeTemplate
    private let warmCapacity: Int
    private let maximumConcurrentCreations: Int

    private var ready: [JavaScriptRuntime] = []
    private var creationTasks: [UInt64: Task<Void, Never>] = [:]
    private var runtimeWaiters: [UInt64: RuntimeWaiter] = [:]
    private var runtimeWaiterOrder: [UInt64] = []
    private var warmUpWaiters: [UInt64: CheckedContinuation<Void, any Error>] = [:]
    private var nextIdentifier: UInt64 = 1
    private var pendingFailure: (any Error)?
    private var isActive = false
    private var hasCompletedWarmUp = false
    private var shutdownRequested = false

    /// Creates a one-shot prewarmed runtime provisioner.
    ///
    /// Construction performs no runtime work. Call ``warmUp()`` to establish a
    /// readiness boundary before serving latency-sensitive requests.
    ///
    /// - Parameters:
    ///   - template: The immutable template used for every runtime.
    ///   - warmCapacity: The number of prepared runtimes retained while active.
    ///   - maximumConcurrentCreations: The maximum number of simultaneous
    ///     creations. `nil` uses `min(warmCapacity, 4)`.
    /// - Throws: ``JavaScriptError`` when either capacity is not positive.
    public init(
        template: JavaScriptRuntimeTemplate,
        warmCapacity: Int,
        maximumConcurrentCreations: Int? = nil
    ) throws {
        guard warmCapacity > 0 else {
            throw JavaScriptError(
                kind: .conversion,
                message: "A runtime provisioner requires a positive warm capacity."
            )
        }
        let concurrency = maximumConcurrentCreations ?? min(warmCapacity, 4)
        guard concurrency > 0 else {
            throw JavaScriptError(
                kind: .conversion,
                message: "A runtime provisioner requires positive creation concurrency."
            )
        }
        self.template = template
        self.warmCapacity = warmCapacity
        self.maximumConcurrentCreations = concurrency
        ready.reserveCapacity(warmCapacity)
    }

    deinit {
        for task in creationTasks.values { task.cancel() }
        for waiter in runtimeWaiters.values {
            waiter.continuation.resume(throwing: CancellationError())
        }
        for continuation in warmUpWaiters.values {
            continuation.resume(throwing: CancellationError())
        }
    }

    /// Fills the configured warm capacity.
    ///
    /// Concurrent calls share provisioning. The first unsuccessful warm-up is
    /// transactional and releases every runtime prepared by that attempt.
    public func warmUp() async throws {
        guard !shutdownRequested else { throw CancellationError() }
        if ready.count >= warmCapacity {
            hasCompletedWarmUp = true
            return
        }

        pendingFailure = nil
        isActive = true
        let identifier = allocateIdentifier()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                warmUpWaiters[identifier] = continuation
                ensureProvisioning()
            }
        } onCancel: {
            Task { await self.cancelWarmUpWaiter(identifier) }
        }
    }

    /// Transfers one fully prepared runtime to the caller.
    ///
    /// A ready runtime is returned without creating QuickJS state on the caller's
    /// latency path. Background provisioning then restores warm capacity.
    public func makeRuntime() async throws -> JavaScriptRuntime {
        guard !shutdownRequested else { throw CancellationError() }
        isActive = true

        if !ready.isEmpty {
            let runtime = ready.removeLast()
            pendingFailure = nil
            scheduleReplenishment()
            return runtime
        }
        if let failure = pendingFailure {
            pendingFailure = nil
            throw failure
        }

        let identifier = allocateIdentifier()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                runtimeWaiters[identifier] = RuntimeWaiter(continuation: continuation)
                runtimeWaiterOrder.append(identifier)
                ensureProvisioning()
            }
        } onCancel: {
            Task { await self.cancelRuntimeWaiter(identifier) }
        }
    }

    /// Stops provisioning and releases runtimes not yet transferred.
    ///
    /// Runtimes already returned to callers remain independent and unaffected.
    public func shutdown() {
        guard !shutdownRequested else { return }
        shutdownRequested = true
        isActive = false
        pendingFailure = nil
        ready.removeAll()
        for task in creationTasks.values { task.cancel() }
        creationTasks.removeAll()
        failRuntimeWaiters(with: CancellationError())
        for continuation in warmUpWaiters.values {
            continuation.resume(throwing: CancellationError())
        }
        warmUpWaiters.removeAll()
    }

    /// Returns the provisioner's current capacity and demand.
    public var status: Status {
        Status(
            readyCount: ready.count,
            provisioningCount: creationTasks.count,
            waitingCount: runtimeWaiters.count,
            isShutdown: shutdownRequested
        )
    }

    private func ensureProvisioning() {
        guard isActive, !shutdownRequested, pendingFailure == nil else { return }
        let desiredCount = warmCapacity + runtimeWaiters.count
        while creationTasks.count < maximumConcurrentCreations,
              ready.count + creationTasks.count < desiredCount {
            startCreation()
        }
    }

    private func scheduleReplenishment() {
        Task { [weak self] in
            await self?.resumeProvisioning()
        }
    }

    private func resumeProvisioning() {
        ensureProvisioning()
    }

    private func startCreation() {
        let identifier = allocateIdentifier()
        let template = template
        let task = Task.detached { [weak self] in
            let result: Result<JavaScriptRuntime, any Error>
            do {
                result = .success(try await template.makeRuntime())
            } catch {
                result = .failure(error)
            }
            await self?.completeCreation(identifier, result: result)
        }
        creationTasks[identifier] = task
    }

    private func completeCreation(
        _ identifier: UInt64,
        result: Result<JavaScriptRuntime, any Error>
    ) {
        guard creationTasks.removeValue(forKey: identifier) != nil,
              !shutdownRequested else { return }

        switch result {
        case let .success(runtime):
            if let waiterIdentifier = runtimeWaiterOrder.first {
                runtimeWaiterOrder.removeFirst()
                runtimeWaiters.removeValue(forKey: waiterIdentifier)?
                    .continuation.resume(returning: runtime)
            } else {
                ready.append(runtime)
            }
            completeWarmUpIfReady()
            ensureProvisioning()

        case let .failure(error):
            let hasWaitingConsumer = !runtimeWaiters.isEmpty || !warmUpWaiters.isEmpty
            pendingFailure = hasWaitingConsumer ? nil : error
            if !hasCompletedWarmUp, !warmUpWaiters.isEmpty {
                ready.removeAll()
            }
            for continuation in warmUpWaiters.values {
                continuation.resume(throwing: error)
            }
            warmUpWaiters.removeAll()
            failRuntimeWaiters(with: error)
            for task in creationTasks.values { task.cancel() }
            creationTasks.removeAll()
        }
    }

    private func completeWarmUpIfReady() {
        guard ready.count >= warmCapacity, runtimeWaiters.isEmpty else { return }
        hasCompletedWarmUp = true
        for continuation in warmUpWaiters.values {
            continuation.resume()
        }
        warmUpWaiters.removeAll()
    }

    private func cancelRuntimeWaiter(_ identifier: UInt64) {
        guard let waiter = runtimeWaiters.removeValue(forKey: identifier) else { return }
        runtimeWaiterOrder.removeAll { $0 == identifier }
        waiter.continuation.resume(throwing: CancellationError())
        ensureProvisioning()
    }

    private func cancelWarmUpWaiter(_ identifier: UInt64) {
        guard let continuation = warmUpWaiters.removeValue(forKey: identifier) else {
            return
        }
        continuation.resume(throwing: CancellationError())
    }

    private func failRuntimeWaiters(with error: any Error) {
        for identifier in runtimeWaiterOrder {
            runtimeWaiters.removeValue(forKey: identifier)?
                .continuation.resume(throwing: error)
        }
        runtimeWaiterOrder.removeAll()
    }

    private func allocateIdentifier() -> UInt64 {
        defer { nextIdentifier &+= 1 }
        return nextIdentifier
    }
}
