import Testing
import QuickJSKit

@Suite("Runtime concurrency examples")
struct ConcurrencyExamplesTests {
    @Test("one runtime safely serializes concurrent callers")
    func runtimeSerializesConcurrentEvaluation() async throws {
        let runtime = try JavaScriptRuntime()

        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for value in 0..<32 {
                group.addTask {
                    try await runtime.evaluate("\(value) * \(value)", as: Int.self)
                }
            }

            var values: [Int] = []
            for try await value in group { values.append(value) }
            return values
        }

        #expect(results.count == 32)
        #expect(Set(results).contains(31 * 31))
    }

    @Test("independent runtimes can make concurrent progress")
    func independentRuntimesOperateConcurrently() async throws {
        let first = try JavaScriptRuntime()
        let second = try JavaScriptRuntime()

        async let firstValue: Int = first.evaluate("40 + 2")
        async let secondValue: String = second.evaluate("'Quick' + 'JS'")
        let values = try await (firstValue, secondValue)

        #expect(values.0 == 42)
        #expect(values.1 == "QuickJS")
    }
}
