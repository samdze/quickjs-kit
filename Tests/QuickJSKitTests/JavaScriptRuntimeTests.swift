import Testing
@testable import QuickJSKit

@Suite("JavaScript runtime")
struct JavaScriptRuntimeTests {
    @Test("evaluates primitive values")
    func evaluatesPrimitiveValues() async throws {
        let runtime = try JavaScriptRuntime()

        let undefined = try await runtime.evaluate("undefined")
        let null = try await runtime.evaluate("null")
        let boolean = try await runtime.evaluate("true")
        let number = try await runtime.evaluate("6 * 7")
        let string = try await runtime.evaluate("'Quick' + 'JS'")

        #expect(undefined == .undefined)
        #expect(null == .null)
        #expect(boolean.booleanValue == true)
        #expect(number.numberValue == 42)
        #expect(string.stringValue == "QuickJS")
    }

    @Test("preserves syntax error diagnostics")
    func preservesSyntaxErrorDiagnostics() async throws {
        let runtime = try JavaScriptRuntime()

        do {
            _ = try await runtime.evaluate("const =", sourceURL: "broken.js")
            Issue.record("Expected evaluation to throw")
        } catch let error as JavaScriptError {
            #expect(error.kind == .syntax)
            #expect(error.name == "SyntaxError")
            #expect(error.sourceURL == "broken.js")
            #expect(error.stack?.contains("broken.js") == true)
        }
    }

    @Test("preserves thrown error details")
    func preservesThrownErrorDetails() async throws {
        let runtime = try JavaScriptRuntime()

        do {
            _ = try await runtime.evaluate(
                "throw new TypeError('wrong value')",
                sourceURL: "example.js"
            )
            Issue.record("Expected evaluation to throw")
        } catch let error as JavaScriptError {
            #expect(error.kind == .exception)
            #expect(error.name == "TypeError")
            #expect(error.message == "wrong value")
            #expect(error.stack?.contains("example.js") == true)
        }
    }

    @Test("rejects live object results until handles are implemented")
    func rejectsUnsupportedValues() async throws {
        let runtime = try JavaScriptRuntime()

        do {
            _ = try await runtime.evaluate("({ answer: 42 })")
            Issue.record("Expected evaluation to throw")
        } catch let error as JavaScriptError {
            #expect(error.kind == .conversion)
        }
    }

    @Test("serializes access from concurrent tasks")
    func serializesConcurrentEvaluation() async throws {
        let runtime = try JavaScriptRuntime()

        let values = try await withThrowingTaskGroup(of: Double.self) { group in
            for value in 0..<32 {
                group.addTask {
                    let result = try await runtime.evaluate("\(value) * \(value)")
                    return try #require(result.numberValue)
                }
            }

            var results: [Double] = []
            for try await result in group {
                results.append(result)
            }
            return results
        }

        #expect(values.count == 32)
        #expect(Set(values).contains(31 * 31))
    }

    @Test("retains its immutable configuration")
    func retainsConfiguration() throws {
        let configuration = JavaScriptRuntime.Configuration(
            memoryLimit: 8 * 1_024 * 1_024,
            maximumStackSize: 512 * 1_024
        )
        let runtime = try JavaScriptRuntime(configuration: configuration)

        #expect(runtime.configuration == configuration)
    }
}
