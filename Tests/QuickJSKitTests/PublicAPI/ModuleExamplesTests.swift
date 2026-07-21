import QuickJSKit
import Testing

@Suite("ES module APIs")
struct ModuleExamplesTests {
    @Test("registered modules import relative dependencies")
    func registeredModulesImportDependencies() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.registerModule(
            "export const value = 40;",
            as: "app/value.js"
        )
        try await runtime.registerModule(
            "import { value } from './value.js'; export const answer = value + 2;",
            as: "app/main.js"
        )

        let module = try await runtime.importModule("app/main.js")
        let answer: Int = try await module.value(forExport: "answer")

        #expect(answer == 42)
        #expect(try await module.exportNames() == ["answer"])
    }

    @Test("typed module import decodes the namespace")
    func typedImportDecodesNamespace() async throws {
        struct Exports: Decodable, Sendable, Equatable {
            let answer: Int
            let name: String
        }

        let runtime = try JavaScriptRuntime()
        try await runtime.registerModule(
            "export const answer = 42; export const name = 'QuickJSKit';",
            as: "sdk"
        )

        let exports: Exports = try await runtime.importModule("sdk")
        #expect(exports == Exports(answer: 42, name: "QuickJSKit"))
    }

    @Test("module evaluation supports top-level await")
    func moduleEvaluationSupportsTopLevelAwait() async throws {
        let runtime = try JavaScriptRuntime()

        let module = try await runtime.evaluateModule(
            "export const answer = await Promise.resolve(42);",
            sourceURL: "memory:///answer.js"
        )

        let answer: Int = try await module.value(forExport: "answer")
        #expect(answer == 42)
    }

    @Test("import meta uses the registered source URL")
    func importMetaUsesSourceURL() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.registerModule(
            "export const url = import.meta.url;",
            as: "meta",
            sourceURL: "memory:///meta.js"
        )

        let module = try await runtime.importModule("meta")
        let url: String = try await module.value(forExport: "url")
        #expect(url == "memory:///meta.js")
    }

    @Test("a custom asynchronous loader supplies a complete graph")
    func customLoaderSuppliesGraph() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.setModuleLoader(
            JavaScriptModuleLoader { request in
                switch request.specifier {
                case "remote/main.js":
                    JavaScriptModuleSource(
                        source: "import { value } from './value.js'; export const answer = value + 2;",
                        sourceURL: "memory:///remote/main.js"
                    )
                case "remote/value.js", "memory:///remote/value.js":
                    JavaScriptModuleSource(
                        source: "export const value = 40;",
                        sourceURL: "memory:///remote/value.js"
                    )
                default:
                    throw LoaderError.unknown(request.specifier)
                }
            }
        )

        let module = try await runtime.importModule("remote/main.js")
        let answer: Int = try await module.value(forExport: "answer")
        #expect(answer == 42)
    }

    @Test("perform imports an immediately settled module synchronously")
    func performImportsModuleSynchronously() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.registerModule("export const answer = 42;", as: "answer")

        let answer = try await runtime.perform { runtime in
            let module = try runtime.importModule("answer")
            return try runtime.evaluate(
                "globalThis.answerNamespace = undefined; 42",
                as: Int.self
            ) + (module.specifier == "answer" ? 0 : 1)
        }

        #expect(answer == 42)
    }

    @Test("repeated imports preserve module and namespace identity")
    func repeatedImportsPreserveIdentity() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.registerModule("export const answer = 42;", as: "identity")

        let first = try await runtime.importModule("identity")
        let second = try await runtime.importModule("identity")

        #expect(first == second)
        #expect(first.namespace == second.namespace)
    }

    @Test("cycles and re-exports follow native ES module semantics")
    func cyclesAndReexportsWork() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.registerModule(
            "import { right } from './right.js'; export function left() { return 20; } export const answer = left() + right();",
            as: "cycle/left.js"
        )
        try await runtime.registerModule(
            "import { left } from './left.js'; export function right() { return left() + 2; }",
            as: "cycle/right.js"
        )
        try await runtime.registerModule(
            "export { answer } from './left.js';",
            as: "cycle/index.js"
        )

        let module = try await runtime.importModule("cycle/index.js")
        let answer: Int = try await module.value(forExport: "answer")
        #expect(answer == 42)
    }

    @Test("dynamic import uses registered source")
    func dynamicImportUsesRegisteredSource() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.registerModule("export const value = 42;", as: "dynamic/value.js")
        try await runtime.registerModule(
            "export const answer = (await import('./value.js')).value;",
            as: "dynamic/main.js"
        )

        let module = try await runtime.importModule("dynamic/main.js")
        let answer: Int = try await module.value(forExport: "answer")
        #expect(answer == 42)
    }

    @Test("concurrent imports coalesce custom source loading")
    func concurrentImportsCoalesceLoading() async throws {
        let runtime = try JavaScriptRuntime()
        let gate = LoaderGate()
        try await runtime.setModuleLoader(
            JavaScriptModuleLoader { request in
                await gate.enter()
                return JavaScriptModuleSource(
                    source: "export const answer = 42;",
                    sourceURL: "memory:///\(request.specifier)"
                )
            }
        )

        async let first = runtime.importModule("coalesced")
        async let second = runtime.importModule("coalesced")
        await gate.waitUntilEntered()
        await gate.open()
        let modules = try await [first, second]

        #expect(modules[0] == modules[1])
        #expect(await gate.entryCount == 1)
    }

    @Test("cancelling one loader consumer preserves shared work")
    func cancellationPreservesSharedLoading() async throws {
        let runtime = try JavaScriptRuntime()
        let gate = LoaderGate()
        try await runtime.setModuleLoader(
            JavaScriptModuleLoader { request in
                await gate.enter()
                return JavaScriptModuleSource(
                    source: "export const answer = 42;",
                    sourceURL: "memory:///\(request.specifier)"
                )
            }
        )

        let surviving = Task { try await runtime.importModule("shared") }
        await gate.waitUntilEntered()
        let cancelled = Task { try await runtime.importModule("shared") }
        await Task.yield()
        _ = await runtime.memoryUsage()
        cancelled.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }
        let module = try await surviving.value
        let answer: Int = try await module.value(forExport: "answer")
        #expect(answer == 42)
        #expect(await gate.entryCount == 1)
    }

    @Test("a custom resolver maps canonical module identities")
    func customResolverMapsCanonicalIdentity() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.setModuleLoader(
            JavaScriptModuleLoader(
                resolve: { request in
                    request.specifier == "alias" ? "canonical" : request.specifier
                },
                load: { request in
                    JavaScriptModuleSource(
                        source: "export const answer = 42;",
                        sourceURL: "memory:///\(request.specifier).js"
                    )
                }
            )
        )

        let alias = try await runtime.importModule("alias")
        let canonical = try await runtime.importModule("canonical")

        #expect(alias == canonical)
        #expect(alias.specifier == "canonical")
    }

    @Test("loader configuration locks after compilation begins")
    func loaderConfigurationLocks() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.registerModule("export {};", as: "compiled")
        _ = try await runtime.importModule("compiled")

        await #expect(throws: JavaScriptError.self) {
            try await runtime.setModuleLoader(
                JavaScriptModuleLoader { _ in
                    JavaScriptModuleSource(source: "export {};", sourceURL: "memory:///late.js")
                }
            )
        }
    }

    @Test("module failures preserve syntax and loading error categories")
    func moduleFailuresPreserveCategories() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.registerModule("export const = ;", as: "broken")

        do {
            _ = try await runtime.importModule("broken")
            Issue.record("Expected invalid module syntax to fail.")
        } catch let error as JavaScriptError {
            #expect(error.kind == .syntax)
        }

        let otherRuntime = try JavaScriptRuntime()
        do {
            _ = try await otherRuntime.importModule("missing")
            Issue.record("Expected the unavailable module to fail.")
        } catch let error as JavaScriptError {
            #expect(error.kind == .module)
        }
    }

    private enum LoaderError: Error {
        case unknown(String)
    }

    private actor LoaderGate {
        private(set) var entryCount = 0
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func enter() async {
            entryCount += 1
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func waitUntilEntered() async {
            while entryCount == 0 { await Task.yield() }
        }

        func open() {
            isOpen = true
            let pending = waiters
            waiters.removeAll()
            for waiter in pending { waiter.resume() }
        }
    }
}
