import Testing
import QuickJSKit

@Suite("Native promise interoperability examples")
struct PromiseExamplesTests {
    @Test("typed reads automatically await native promises")
    func typedReadsAwaitPromises() async throws {
        let runtime = try JavaScriptRuntime()
        let rootValue = try await runtime.evaluate("""
            ({
              property: Promise.resolve(40),
              array: [Promise.resolve(41)],
              function() { return Promise.resolve(42) }
            })
            """)
        let root = try #require(rootValue.objectValue)

        let property: Int = try await root.value(forProperty: "property")
        let array: JavaScriptValue = try await root.value(forProperty: "array")
        let element: Int = try await #require(array.arrayValue).value(at: 0)
        let function: JavaScriptValue = try await root.value(forProperty: "function")
        let called: Int = try await #require(function.functionValue).call()
        let evaluated: Int = try await runtime.evaluate("Promise.resolve(43)")

        #expect([property, element, called, evaluated] == [40, 41, 42, 43])
    }

    @Test("the decoder awaits a raw promise while thenables remain ordinary objects")
    func decoderAwaitsOnlyNativePromises() async throws {
        struct Thenable: Codable, Sendable, Equatable {
            let then: String
            let value: Int
        }

        let runtime = try JavaScriptRuntime()
        let promise = try await runtime.evaluate("Promise.resolve({ then: 'value', value: 42 })")
        let decoded = try await runtime.decoder.decode(Thenable.self, from: promise)
        let ordinary: Thenable = try await runtime.evaluate("({ then: 'value', value: 42 })")

        #expect(decoded == ordinary)
    }

    @Test("a checkpoint drains recursively scheduled promise jobs")
    func drainsRecursiveJobs() async throws {
        let runtime = try JavaScriptRuntime()

        let result: Int = try await runtime.evaluate("""
            Promise.resolve(1)
              .then(value => value + 1)
              .then(value => Promise.resolve(value + 1))
              .then(value => value + 39)
            """)

        #expect(result == 42)
    }

    @Test("an asynchronous Swift binding may re-enter its runtime after suspension")
    func asyncBindingReentersRuntime() async throws {
        let runtime = try JavaScriptRuntime()
        let binding = try await runtime.function("answer") { [weak runtime] () async throws -> Int in
            await Task.yield()
            guard let runtime else { return 0 }
            return try await runtime.evaluate("40 + 2")
        }

        let answer: Int = try await runtime.evaluate("answer()")
        #expect(answer == 42)
        try await binding.remove()
    }

    @Test("cancelling removal rejects active Swift promises")
    func cancellingRemovalRejectsPromise() async throws {
        let runtime = try JavaScriptRuntime()
        let gate = Gate()
        let binding = try await runtime.function("slow") { () async throws -> Int in
            await gate.wait()
            try Task.checkCancellation()
            return 42
        }
        let promise = try await runtime.evaluate("slow()")
        await gate.waitUntilEntered()
        #expect(await runtime.resourceUsage().pendingHostCallCount == 1)

        try await binding.remove(cancellingInFlight: true)
        #expect(await runtime.resourceUsage().pendingHostCallCount == 0)

        await #expect(throws: JavaScriptError.self) {
            let _: Int = try await runtime.decoder.decode(Int.self, from: promise)
        }
        await gate.open()
    }

    @Test("concurrent host calls never exceed their admission limit")
    func concurrentHostCallsStayWithinLimit() async throws {
        let runtime = try JavaScriptRuntime(configuration: .init(
            maximumPendingHostCallCount: 4
        ))
        let gate = MultiGate()
        try await runtime.function("limited") { () async -> Int in
            await gate.wait()
            return 42
        }

        var admitted: [JavaScriptValue] = []
        var rejected = 0
        for _ in 0..<8 {
            let result = try await runtime.evaluate("""
                try {
                    limited()
                } catch (error) {
                    error instanceof RangeError
                }
                """)
            if result.booleanValue == true {
                rejected += 1
            } else {
                admitted.append(result)
            }
        }

        #expect(admitted.count == 4)
        #expect(rejected == 4)
        #expect(await runtime.resourceUsage().pendingHostCallCount == 4)

        await gate.open()
        for promise in admitted {
            let answer = try await runtime.decoder.decode(Int.self, from: promise)
            #expect(answer == 42)
        }
        #expect(await runtime.resourceUsage().pendingHostCallCount == 0)
    }

    @Test("cancelling a native JavaScript promise wait removes only the Swift waiter")
    func cancelsNativePromiseWaiter() async throws {
        let runtime = try JavaScriptRuntime()
        let promise = try await runtime.evaluate("new Promise(() => {})")
        let waiter = Task {
            try await runtime.decoder.decode(Int.self, from: promise)
        }
        await Task.yield()

        waiter.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await waiter.value
        }
    }

    @Test("cancelling one Swift promise waiter preserves the shared producer")
    func cancellationRemainsLocalToWaiter() async throws {
        let runtime = try JavaScriptRuntime()
        let gate = Gate()
        try await runtime.function("slow") { () async throws -> Int in
            await gate.wait()
            try Task.checkCancellation()
            return 42
        }
        let promise = try await runtime.evaluate("slow()")
        await gate.waitUntilEntered()
        let first = Task { try await runtime.decoder.decode(Int.self, from: promise) }
        let second = Task { try await runtime.decoder.decode(Int.self, from: promise) }
        await Task.yield()

        first.cancel()

        await #expect(throws: CancellationError.self) { _ = try await first.value }
        await gate.open()
        #expect(try await second.value == 42)
    }

    @Test("non-cancelling removal lets an active call finish")
    func removalPreservesActiveCall() async throws {
        let runtime = try JavaScriptRuntime()
        let gate = Gate()
        let binding = try await runtime.function("delayedAnswer") { () async -> Int in
            await gate.wait()
            return 42
        }
        let promise = try await runtime.evaluate("delayedAnswer()")
        await gate.waitUntilEntered()

        try await binding.remove()
        await gate.open()

        let answer = try await runtime.decoder.decode(Int.self, from: promise)
        #expect(answer == 42)
    }

    @Test("pending asynchronous host calls respect runtime backpressure")
    func pendingHostCallsRespectLimit() async throws {
        let runtime = try JavaScriptRuntime(configuration: .init(
            maximumPendingHostCallCount: 1
        ))
        let gate = Gate()
        try await runtime.function("slow") { () async -> Int in
            await gate.wait()
            return 42
        }
        try await runtime.function("syncAnswer") { 42 }

        let first = try await runtime.evaluate("slow()")
        await gate.waitUntilEntered()

        let pending = await runtime.resourceUsage()
        #expect(pending.pendingHostCallCount == 1)
        #expect(pending.pendingHostCallLimit == 1)

        let rejected: Bool = try await runtime.evaluate("""
            try {
                slow();
                false;
            } catch (error) {
                error instanceof RangeError
                    && error.message.includes("pending host-call limit");
            }
            """)
        let synchronous: Int = try await runtime.evaluate("syncAnswer()")
        #expect(rejected)
        #expect(synchronous == 42)
        #expect(await runtime.resourceUsage().pendingHostCallCount == 1)

        await gate.open()
        let answer = try await runtime.decoder.decode(Int.self, from: first)
        #expect(answer == 42)
        #expect(await runtime.resourceUsage().pendingHostCallCount == 0)
    }

    @Test("a zero pending-host-call limit rejects before starting Swift work")
    func zeroPendingHostCallLimit() async throws {
        actor Counter {
            var value = 0
            func increment() { value += 1 }
        }

        let runtime = try JavaScriptRuntime(configuration: .init(
            maximumPendingHostCallCount: 0
        ))
        let counter = Counter()
        try await runtime.function("blocked") { () async -> Int in
            await counter.increment()
            return 42
        }

        let rejected: Bool = try await runtime.evaluate("""
            try {
                blocked();
                false;
            } catch (error) {
                error instanceof RangeError;
            }
            """)

        #expect(rejected)
        #expect(await counter.value == 0)
        #expect(await runtime.resourceUsage().pendingHostCallCount == 0)
    }

    @Test("unhandled rejections are reported after a checkpoint")
    func reportsUnhandledRejections() async throws {
        actor Recorder {
            var errors: [JavaScriptError] = []
            func record(_ error: JavaScriptError) { errors.append(error) }
        }

        let runtime = try JavaScriptRuntime()
        let recorder = Recorder()
        await runtime.setUnhandledPromiseRejectionHandler { error in
            Task { await recorder.record(error) }
        }

        _ = try await runtime.evaluate("""
            Promise.reject(new Error('unobserved'));
            undefined
            """)
        await Task.yield()
        await Task.yield()

        let errors = await recorder.errors
        #expect(errors.count == 1)
        #expect(errors.first?.message == "unobserved")
    }

    @Test("same-checkpoint handlers and host results suppress rejection reports")
    func suppressesObservedRejections() async throws {
        actor Counter {
            var value = 0
            func increment() { value += 1 }
        }

        let runtime = try JavaScriptRuntime()
        let counter = Counter()
        await runtime.setUnhandledPromiseRejectionHandler { _ in
            Task { await counter.increment() }
        }

        _ = try await runtime.evaluate("Promise.reject(new Error('handled')).catch(() => 1)")
        _ = try await runtime.evaluate("Promise.reject(new Error('returned'))")
        await Task.yield()
        await Task.yield()

        #expect(await counter.value == 0)
    }

    private actor Gate {
        private var isEntered = false
        private var releaseContinuation: CheckedContinuation<Void, Never>?
        private var entryContinuations: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            isEntered = true
            for continuation in entryContinuations { continuation.resume() }
            entryContinuations.removeAll()
            await withCheckedContinuation { releaseContinuation = $0 }
        }

        func waitUntilEntered() async {
            guard !isEntered else { return }
            await withCheckedContinuation { entryContinuations.append($0) }
        }

        func open() {
            releaseContinuation?.resume()
            releaseContinuation = nil
        }
    }

    private actor MultiGate {
        private var isOpen = false
        private var continuations: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            guard !isOpen else { return }
            await withCheckedContinuation { continuations.append($0) }
        }

        func open() {
            isOpen = true
            let pending = continuations
            continuations.removeAll()
            for continuation in pending {
                continuation.resume()
            }
        }
    }
}
