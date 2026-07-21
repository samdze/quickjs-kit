import QuickJSKit
import Testing

@Suite("Scoped runtime execution")
struct ExecutionExamplesTests {
    @Test("perform batches synchronous typed evaluations")
    func performBatchesSynchronousEvaluation() async throws {
        let runtime = try JavaScriptRuntime()

        let result = try await runtime.perform { runtime in
            let first: Int = try runtime.evaluate("Promise.resolve(20)")
            let second: Int = try runtime.evaluate("22")
            return first + second
        }

        #expect(result == 42)
    }

    @Test("perform supports asynchronous runtime operations")
    func performSupportsAsynchronousOperations() async throws {
        let runtime = try JavaScriptRuntime()

        let result = try await runtime.perform { runtime in
            let first: Int = try await runtime.evaluate("Promise.resolve(20)")
            let second: Int = try await runtime.evaluate("Promise.resolve(22)")
            return first + second
        }

        #expect(result == 42)
    }

    @Test("synchronous evaluation rejects a pending promise")
    func synchronousEvaluationRejectsPendingPromise() async throws {
        let runtime = try JavaScriptRuntime()

        do {
            try await runtime.perform { runtime in
                let _: Int = try runtime.evaluate("new Promise(() => {})")
            }
            Issue.record("Expected synchronous evaluation to require suspension.")
        } catch let error as JavaScriptError {
            #expect(error.kind == .wouldSuspend)
        }
    }

    @Test("operation options can disable the runtime's default timeout")
    func operationOptionsOverrideDefaultTimeout() async throws {
        let runtime = try JavaScriptRuntime(configuration: .init(
            defaultExecutionTimeout: .zero
        ))

        do {
            _ = try await runtime.evaluate("while (true) {}")
            Issue.record("Expected the runtime default timeout to interrupt execution.")
        } catch let error as JavaScriptError {
            #expect(error.kind == .timeout)
        }

        let answer: Int = try await runtime.evaluate(
            "42",
            options: .init(timeout: .disabled)
        )
        #expect(answer == 42)
    }

    @Test("execution deadlines interrupt JavaScript and leave the runtime reusable")
    func deadlinesInterruptExecution() async throws {
        let runtime = try JavaScriptRuntime()

        do {
            _ = try await runtime.evaluate(
                "while (true) {}",
                options: .init(timeout: .after(.milliseconds(1)))
            )
            Issue.record("Expected JavaScript execution to time out.")
        } catch let error as JavaScriptError {
            #expect(error.kind == .timeout)
        }

        let answer: Int = try await runtime.evaluate("40 + 2")
        #expect(answer == 42)
    }

    @Test("a custom interrupt handler stops execution")
    func customInterruptStopsExecution() async throws {
        let runtime = try JavaScriptRuntime()
        await runtime.setInterruptHandler { true }

        do {
            _ = try await runtime.evaluate("while (true) {}")
            Issue.record("Expected JavaScript execution to be interrupted.")
        } catch let error as JavaScriptError {
            #expect(error.kind == .interrupted)
        }

        await runtime.setInterruptHandler(nil)
        let answer: Int = try await runtime.evaluate("42")
        #expect(answer == 42)
    }

    @Test("task cancellation interrupts active JavaScript")
    func taskCancellationInterruptsExecution() async throws {
        let runtime = try JavaScriptRuntime()
        let task = Task {
            try await runtime.evaluate("while (true) {}")
        }

        await Task.yield()
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected JavaScript execution to be cancelled.")
        } catch let error as JavaScriptError {
            #expect(error.kind == .cancelled)
        }
    }

    @Test("function calls accept per-operation execution options")
    func functionCallsAcceptOptions() async throws {
        let runtime = try JavaScriptRuntime()
        let value = try await runtime.evaluate("() => { while (true) {} }")
        let function = try #require(value.functionValue)

        do {
            _ = try await function.call(
                options: .init(timeout: .after(.milliseconds(1)))
            )
            Issue.record("Expected the JavaScript function to time out.")
        } catch let error as JavaScriptError {
            #expect(error.kind == .timeout)
        }
    }

    @Test("live-value operations inherit the runtime execution policy")
    func liveValuesInheritRuntimeExecutionPolicy() async throws {
        let runtime = try JavaScriptRuntime(configuration: .init(
            defaultExecutionTimeout: .milliseconds(1)
        ))
        let value = try await runtime.evaluate(
            "({ get blocked() { while (true) {} } })",
            options: .init(timeout: .disabled)
        )
        let object = try #require(value.objectValue)

        do {
            let _: Int = try await object.value(forProperty: "blocked")
            Issue.record("Expected the property getter to time out.")
        } catch let error as JavaScriptError {
            #expect(error.kind == .timeout)
        }

        let answer: Int = try await runtime.evaluate(
            "42",
            options: .init(timeout: .disabled)
        )
        #expect(answer == 42)
    }

    @Test("memory usage is observable and garbage collection is explicit")
    func memoryUsageIsObservable() async throws {
        let runtime = try JavaScriptRuntime(configuration: .init(memoryLimit: 8_000_000))

        let before = await runtime.memoryUsage()
        _ = try await runtime.evaluate("Array.from({ length: 1_000 }, (_, i) => ({ i }))")
        let after = await runtime.memoryUsage()
        await runtime.collectGarbage()

        #expect(before.allocationLimit == 8_000_000)
        #expect(before.allocatedBytes > 0)
        #expect(after.usedBytes > 0)
    }
}
