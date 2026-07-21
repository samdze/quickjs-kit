import QuickJSKit
import Testing

@Suite("Swift-defined modules")
struct SwiftModuleExamplesTests {
    @Test("a Swift module exports typed functions and snapshot values")
    func swiftModuleExportsFunctionsAndValues() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.defineModule("swift:math") { module in
            module.function(
                "sum",
                options: .init(
                    parameterNames: ["a", "b"],
                    documentation: "Adds two integers."
                )
            ) { (a: Int, b: Int) in
                a + b
            }
            module.value("1.0", as: "version", documentation: "API version.")
        }

        let result: Int = try await runtime.evaluateModule(
            "import { sum } from 'swift:math'; export const answer = sum(20, 22);"
        ).value(forExport: "answer")
        let module = try await runtime.importModule("swift:math")
        let version: String = try await module.value(forExport: "version")

        #expect(result == 42)
        #expect(version == "1.0")
    }

    @Test("an asynchronous Swift module function returns a native promise")
    func asynchronousFunctionReturnsPromise() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.defineModule("swift:async") { module in
            module.function("answer") { () async -> Int in 42 }
        }

        let module = try await runtime.evaluateModule(
            "import { answer } from 'swift:async'; export const value = await answer();"
        )
        let value: Int = try await module.value(forExport: "value")
        #expect(value == 42)
    }

    @Test("default exports are supported")
    func defaultExportsAreSupported() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.defineModule("swift:default") { module in
            module.value(42, as: "default")
        }

        let module = try await runtime.evaluateModule(
            "import answer from 'swift:default'; export { answer };"
        )
        let answer: Int = try await module.value(forExport: "answer")
        #expect(answer == 42)
    }

    @Test("invalid Swift module definitions do not become importable")
    func invalidDefinitionRollsBack() async throws {
        let runtime = try JavaScriptRuntime()

        await #expect(throws: JavaScriptError.self) {
            try await runtime.defineModule("swift:invalid") { module in
                module.value(1, as: "duplicate")
                module.value(2, as: "duplicate")
            }
        }

        await #expect(throws: JavaScriptError.self) {
            try await runtime.importModule("swift:invalid")
        }
    }

    @Test("Swift modules preserve throwing effects and Void results")
    func swiftModulesPreserveEffectsAndVoid() async throws {
        enum ExampleError: Error { case rejected }

        let runtime = try JavaScriptRuntime()
        try await runtime.defineModule("swift:effects") { module in
            module.function("notify") { () -> Void in }
            module.function("rejectSync") { () throws -> Int in
                throw ExampleError.rejected
            }
            module.function("rejectAsync") { () async throws -> Int in
                throw ExampleError.rejected
            }
        }

        let notified: Bool = try await runtime.evaluateModule(
            """
            import { notify } from 'swift:effects';
            export const value = notify() === undefined;
            """
        ).value(forExport: "value")
        #expect(notified)

        let syncError: String = try await runtime.evaluateModule(
            """
            import { rejectSync } from 'swift:effects';
            let value;
            try { rejectSync(); } catch (error) { value = error.name; }
            export { value };
            """
        ).value(forExport: "value")
        #expect(syncError == "SwiftError")

        let asyncError: String = try await runtime.evaluateModule(
            """
            import { rejectAsync } from 'swift:effects';
            let value;
            try { await rejectAsync(); } catch (error) { value = error.name; }
            export { value };
            """
        ).value(forExport: "value")
        #expect(asyncError == "SwiftError")
    }
}
