import Testing
import QuickJSKit

@Suite("Typed Swift binding examples")
struct SwiftBindingExamplesTests {
    @Test("JavaScript calls a synchronous typed Swift function")
    func callsSynchronousFunction() async throws {
        let runtime = try JavaScriptRuntime()
        let binding = try await runtime.function(
            "sum",
            options: .init(
                parameterNames: ["left", "right"],
                documentation: "Adds two integers."
            )
        ) { (left: Int, right: Int) in
            left + right
        }

        let result: Int = try await runtime.evaluate("sum(20, 22)")
        let arity: Int = try await runtime.evaluate("sum.length")

        #expect(result == 42)
        #expect(arity == 2)
        #expect(binding.name == "sum")
        #expect(binding.value.isFunction)
        #expect(await binding.isActive)
    }

    @Test("missing arguments decode as undefined and extra arguments are ignored")
    func handlesJavaScriptArity() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.function("greet") { (name: String?, punctuation: String?) in
            (name ?? "world") + (punctuation ?? "!")
        }

        let result: [String] = try await runtime.evaluate("[greet(), greet('Ada', '!', 123)]")
        #expect(result == ["world!", "Ada!"])
    }

    @Test("all Swift closure effects preserve their JavaScript semantics")
    func supportsEveryClosureEffect() async throws {
        struct ExampleError: Error {}

        let runtime = try JavaScriptRuntime()
        try await runtime.function("sync") { (value: Int) in value + 1 }
        try await runtime.function("throwing") { (value: Int) throws -> Int in
            if value < 0 { throw ExampleError() }
            return value
        }
        try await runtime.function("async") { (value: Int) async in value + 2 }
        try await runtime.function("asyncThrowing") { (value: Int) async throws -> Int in
            if value < 0 { throw ExampleError() }
            return value + 3
        }

        let values: [Int]
        do {
            values = try await runtime.evaluate("""
                Promise.all([sync(1), throwing(2), async(3), asyncThrowing(4)])
                """)
        } catch let error as JavaScriptError {
            Issue.record("Promise interoperability failed: \(error.stack ?? error.description)")
            return
        }
        #expect(values == [2, 2, 5, 7])

        let errorName: String = try await runtime.evaluate("""
            asyncThrowing(-1).catch(error => error.name)
            """)
        #expect(errorName == "SwiftError")
    }

    @Test("Void functions produce undefined")
    func voidProducesUndefined() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.function("notify") { () -> Void in }

        let isUndefined: Bool = try await runtime.evaluate("notify() === undefined")
        #expect(isUndefined)
    }

    @Test("binding removal is explicit and idempotent")
    func removalIsExplicit() async throws {
        let runtime = try JavaScriptRuntime()
        let binding = try await runtime.function("answer") { 42 }
        let staleValue = try await runtime.evaluate("answer")
        let staleFunction = try #require(staleValue.functionValue)

        #expect(try await binding.remove())
        #expect(!(try await binding.remove()))
        #expect(!(await binding.isActive))

        await #expect(throws: JavaScriptError.self) {
            let _: Int = try await staleFunction.call()
        }
    }

    @Test("invalid parameter metadata fails before registration")
    func validatesMetadata() async throws {
        let runtime = try JavaScriptRuntime()

        await #expect(throws: JavaScriptError.self) {
            try await runtime.function(
                "invalid",
                options: .init(parameterNames: ["onlyOne"])
            ) { (first: Int, second: Int) in
                first + second
            }
        }

        let absent: Bool = try await runtime.evaluate("typeof invalid === 'undefined'")
        #expect(absent)
    }

    @Test("global replacement preserves stale references without removing the replacement")
    func globalReplacementPreservesReferences() async throws {
        let runtime = try JavaScriptRuntime()
        let firstBinding = try await runtime.function("version") { 1 }
        let firstValue = try await runtime.evaluate("version")
        let firstFunction = try #require(firstValue.functionValue)
        let secondBinding = try await runtime.function("version") { 2 }

        let current: Int = try await runtime.evaluate("version()")
        let stale: Int = try await firstFunction.call()
        #expect(current == 2)
        #expect(stale == 1)

        try await firstBinding.remove()
        let stillCurrent: Int = try await runtime.evaluate("version()")
        #expect(stillCurrent == 2)
        #expect(await secondBinding.isActive)
    }

    @Test("argument conversion failures become TypeError values")
    func argumentFailuresBecomeTypeErrors() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.function("increment") { (value: Int) in value + 1 }

        let name: String = try await runtime.evaluate("""
            try { increment('not an integer') } catch (error) { error.name }
            """)

        #expect(name == "TypeError")
    }

    @Test("asynchronous result encoding failures reject their promises")
    func resultEncodingFailuresRejectPromises() async throws {
        struct ExpectedFailure: Error {}
        struct InvalidResult: Encodable, Sendable {
            func encode(to encoder: any Encoder) throws { throw ExpectedFailure() }
        }

        let runtime = try JavaScriptRuntime()
        try await runtime.function("invalidResult") { () async in InvalidResult() }

        let metadata: [String] = try await runtime.evaluate("""
            invalidResult().catch(error => [error.name, error.swiftType])
            """)
        #expect(metadata.first == "SwiftError")
        #expect(metadata.last?.contains("ExpectedFailure") == true)
    }
}
