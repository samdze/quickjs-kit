import Testing
@testable import QuickJSKit

@Suite("Runtime provisioner invariants")
struct RuntimeProvisionerInvariantTests {
    @Test("runtime creation never exceeds configured concurrency")
    func creationIsBounded() async throws {
        let gate = ProvisioningGate()
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { try await gate.makeRoot() }) {}
        }
        let provisioner = try JavaScriptRuntimeProvisioner(
            template: template,
            warmCapacity: 3,
            maximumConcurrentCreations: 2
        )
        let warming = Task { try await provisioner.warmUp() }

        await gate.waitForCallCount(2)
        #expect(await gate.maximumActiveCount == 2)
        #expect(await provisioner.status.provisioningCount == 2)

        await gate.releaseAll()
        await gate.waitForCallCount(3)
        await gate.releaseAll()
        try await warming.value

        #expect(await provisioner.status.readyCount == 3)
        #expect(await gate.maximumActiveCount == 2)
        await provisioner.shutdown()
    }

    @Test("cancelling one FIFO waiter preserves shared provisioning")
    func waiterCancellationIsLocal() async throws {
        let gate = ProvisioningGate()
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { try await gate.makeRoot() }) {}
        }
        let provisioner = try JavaScriptRuntimeProvisioner(
            template: template,
            warmCapacity: 1,
            maximumConcurrentCreations: 1
        )

        let first = Task { try await provisioner.makeRuntime() }
        await gate.waitForCallCount(1)
        let second = Task { try await provisioner.makeRuntime() }
        await waitForWaitingCount(2, in: provisioner)

        first.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await first.value
        }
        await gate.releaseOne()
        let runtime = try await second.value

        let answer: Int = try await runtime.evaluate("42")
        #expect(answer == 42)
        await provisioner.shutdown()
        await gate.releaseAll()
    }

    @Test("the first failed warm-up releases its partial ready capacity")
    func initialWarmUpIsTransactional() async throws {
        let factory = FailingWarmUpFactory()
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { try await factory.makeRoot() }) {}
        }
        let provisioner = try JavaScriptRuntimeProvisioner(
            template: template,
            warmCapacity: 2,
            maximumConcurrentCreations: 1
        )

        await #expect(throws: ExpectedProvisioningFailure.self) {
            try await provisioner.warmUp()
        }
        await Task.yield()

        #expect(await provisioner.status.readyCount == 0)
        #expect(await factory.hasReleasedRoot)
        await provisioner.shutdown()
    }

    @Test("shutdown cancels waiting consumers and in-progress creation")
    func shutdownCancelsPendingWork() async throws {
        let gate = ProvisioningGate()
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { try await gate.makeRoot() }) {}
        }
        let provisioner = try JavaScriptRuntimeProvisioner(
            template: template,
            warmCapacity: 1
        )
        let waiting = Task { try await provisioner.makeRuntime() }
        await gate.waitForCallCount(1)

        await provisioner.shutdown()
        await #expect(throws: CancellationError.self) {
            _ = try await waiting.value
        }
        await gate.releaseAll()

        let status = await provisioner.status
        #expect(status.isShutdown)
        #expect(status.readyCount == 0)
        #expect(status.provisioningCount == 0)
        #expect(status.waitingCount == 0)
    }

    private func waitForWaitingCount(
        _ expected: Int,
        in provisioner: JavaScriptRuntimeProvisioner
    ) async {
        while await provisioner.status.waitingCount < expected {
            await Task.yield()
        }
    }

    private final class Root: Sendable {}

    private enum ExpectedProvisioningFailure: Error {
        case failed
    }

    private actor FailingWarmUpFactory {
        private var callCount = 0
        private weak var root: Root?

        var hasReleasedRoot: Bool { root == nil }

        func makeRoot() throws -> Root {
            callCount += 1
            if callCount == 1 {
                let value = Root()
                root = value
                return value
            }
            throw ExpectedProvisioningFailure.failed
        }
    }

    private actor ProvisioningGate {
        private var callCount = 0
        private var activeCount = 0
        private(set) var maximumActiveCount = 0
        private var nextIdentifier: UInt64 = 1
        private var continuations: [UInt64: CheckedContinuation<Void, Never>] = [:]
        private var cancelledIdentifiers: Set<UInt64> = []
        private var callCountWaiters: [
            (Int, CheckedContinuation<Void, Never>)
        ] = []

        func makeRoot() async throws -> Root {
            let identifier = nextIdentifier
            nextIdentifier += 1
            callCount += 1
            activeCount += 1
            maximumActiveCount = max(maximumActiveCount, activeCount)
            resumeCallCountWaiters()

            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    if cancelledIdentifiers.remove(identifier) != nil {
                        continuation.resume()
                    } else {
                        continuations[identifier] = continuation
                    }
                }
            } onCancel: {
                Task { await self.cancel(identifier) }
            }
            activeCount -= 1
            try Task.checkCancellation()
            return Root()
        }

        func waitForCallCount(_ expected: Int) async {
            if callCount >= expected { return }
            await withCheckedContinuation { continuation in
                callCountWaiters.append((expected, continuation))
            }
        }

        func releaseOne() {
            guard let identifier = continuations.keys.sorted().first,
                  let continuation = continuations.removeValue(forKey: identifier) else {
                return
            }
            continuation.resume()
        }

        func releaseAll() {
            let values = Array(continuations.values)
            continuations.removeAll()
            for continuation in values { continuation.resume() }
        }

        private func cancel(_ identifier: UInt64) {
            if let continuation = continuations.removeValue(forKey: identifier) {
                continuation.resume()
            } else {
                cancelledIdentifiers.insert(identifier)
            }
        }

        private func resumeCallCountWaiters() {
            var retained: [(Int, CheckedContinuation<Void, Never>)] = []
            for (expected, continuation) in callCountWaiters {
                if callCount >= expected {
                    continuation.resume()
                } else {
                    retained.append((expected, continuation))
                }
            }
            callCountWaiters = retained
        }
    }
}
