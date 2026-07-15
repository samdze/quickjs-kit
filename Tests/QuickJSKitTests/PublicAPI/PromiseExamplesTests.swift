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

        try await binding.remove(cancellingInFlight: true)

        await #expect(throws: JavaScriptError.self) {
            let _: Int = try await runtime.decoder.decode(Int.self, from: promise)
        }
        await gate.open()
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

    @Test("cancelling a direct Swift promise wait cancels the shared producer")
    func cancellationPropagatesToSwiftProducer() async throws {
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
        await #expect(throws: JavaScriptError.self) { _ = try await second.value }
        await gate.open()
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
}
