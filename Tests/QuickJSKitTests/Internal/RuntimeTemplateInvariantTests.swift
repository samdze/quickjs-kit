import Testing
@testable import QuickJSKit

@Suite("Runtime template invariants")
struct RuntimeTemplateInvariantTests {
    @Test("registered module source is compiled once and read into every runtime")
    func moduleArtifactsAreReused() async throws {
        let template = try JavaScriptRuntimeTemplate {
            SourceModule(
                "export const answer = 42",
                as: "cached:answer"
            )
        }
        #expect(template.compiledModuleArtifactCountForTesting == 1)

        let first = try await template.makeRuntime()
        let second = try await template.makeRuntime()
        #expect(await first.cachedModuleReadCountForTesting == 1)
        #expect(await second.cachedModuleReadCountForTesting == 1)
        #expect(await first.sourceModuleCompilationCountForTesting == 0)
        #expect(await second.sourceModuleCompilationCountForTesting == 0)

        let firstAnswer: Int = try await first.importModule("cached:answer")
            .value(forExport: "answer")
        let secondAnswer: Int = try await second.importModule("cached:answer")
            .value(forExport: "answer")
        #expect(firstAnswer == 42)
        #expect(secondAnswer == 42)
    }

    @Test("prepared program bytecode is read independently into every runtime")
    func programArtifactsAreReused() async throws {
        let program = JavaScriptProgram("40 + 2", sourceURL: "Scripts/answer.js")
        let template = try JavaScriptRuntimeTemplate {
            Prepare(program)
        }
        #expect(template.compiledProgramArtifactCountForTesting == 1)

        let first = try await template.makeRuntime()
        let second = try await template.makeRuntime()
        #expect(await first.cachedProgramReadCountForTesting == 1)
        #expect(await second.cachedProgramReadCountForTesting == 1)
        #expect(await first.preparedProgramCompilationCountForTesting == 0)
        #expect(await second.preparedProgramCompilationCountForTesting == 0)

        let firstAnswer: Int = try await first.evaluate(program)
        let secondAnswer: Int = try await second.evaluate(program)
        #expect(firstAnswer == 42)
        #expect(secondAnswer == 42)
        #expect(await first.preparedProgramCompilationCountForTesting == 0)
        #expect(await second.preparedProgramCompilationCountForTesting == 0)
    }

    @Test("an unreadable program artifact retries before factories and startup run")
    func invalidProgramArtifactFallsBackToSource() async throws {
        let probe = FactoryProbe()
        let program = JavaScriptProgram(
            "globalThis.didStart = hostAnswer()",
            sourceURL: "Scripts/start.js"
        )
        let original = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: {
                await probe.recordCreation()
                return Root()
            }) {
                RuntimeGlobals {
                    InstanceFunction("hostAnswer") { (_: Root) -> Int in 42 }
                }
            }
            Startup {
                Run(program)
            }
        }
        let template = original.corruptingFirstCompiledProgramForTesting()

        let runtime = try await template.makeRuntime()
        #expect(await probe.creationCount == 1)
        #expect(await runtime.templateCacheFallbackCountForTesting == 1)
        #expect(await runtime.cachedProgramReadCountForTesting == 0)
        #expect(await runtime.preparedProgramCompilationCountForTesting == 1)
        let answer: Int = try await runtime.evaluate("didStart")
        #expect(answer == 42)
    }

    @Test("static template publication uses one destination engine entry")
    func staticPublicationUsesOneEngineEntry() async throws {
        let program = JavaScriptProgram("42")
        let template = try JavaScriptRuntimeTemplate {
            Globals {
                Function("first") { 1 }
                Function("second") { 2 }
                Value(3, as: "third")
            }
            SwiftModule("host:values") {
                Value(4, as: "fourth")
            }
            SourceModule("export const fifth = 5", as: "app:values")
            Prepare(program)
        }

        let runtime = try await template.makeRuntime()
        #expect(await runtime.stackTopRefreshCountForTesting == 1)
        #expect(await runtime.checkpointCountForTesting == 0)
    }

    @Test("cached modules preserve relative imports and execute only on import")
    func cachedModulesPreserveNativeSemantics() async throws {
        let template = try JavaScriptRuntimeTemplate {
            Globals {
                Value(0, as: "moduleExecutions")
            }
            SourceModule(
                "export const base = 40",
                as: "app/base.js"
            )
            SourceModule(
                """
                import { base } from './base.js';
                globalThis.moduleExecutions += 1;
                export const answer = base + 2;
                """,
                as: "app/main.js"
            )
        }
        let runtime = try await template.makeRuntime()
        let before: Int = try await runtime.evaluate("moduleExecutions")
        #expect(before == 0)

        let first = try await runtime.importModule("app/main.js")
        let second = try await runtime.importModule("app/main.js")
        let answer: Int = try await first.value(forExport: "answer")
        let after: Int = try await runtime.evaluate("moduleExecutions")

        #expect(answer == 42)
        #expect(first == second)
        #expect(after == 1)
    }

    @Test("an unreadable artifact retries from canonical source before factories run")
    func invalidArtifactFallsBackToSource() async throws {
        let probe = FactoryProbe()
        let original = try JavaScriptRuntimeTemplate {
            SourceModule(
                "export const answer = 42",
                as: "cached:fallback"
            )
            RuntimeInstance(factory: {
                await probe.recordCreation()
                return Root()
            }) {
                RuntimeGlobals {
                    InstanceFunction("hostAnswer") { (_: Root) -> Int in 42 }
                }
            }
        }
        let template = original.corruptingFirstCompiledArtifactForTesting()

        let runtime = try await template.makeRuntime()
        #expect(await probe.creationCount == 1)
        #expect(await runtime.templateCacheFallbackCountForTesting == 1)
        #expect(await runtime.cachedModuleReadCountForTesting == 0)

        let answer: Int = try await runtime.importModule("cached:fallback")
            .value(forExport: "answer")
        #expect(answer == 42)
        #expect(await runtime.sourceModuleCompilationCountForTesting > 0)
    }

    @Test("template validation rejects duplicates before invoking a factory")
    func validationPrecedesFactories() async throws {
        let probe = FactoryProbe()

        #expect(throws: JavaScriptError.self) {
            _ = try JavaScriptRuntimeTemplate {
                Globals {
                    Value(1, as: "duplicate")
                }
                RuntimeInstance(factory: {
                    await probe.recordCreation()
                    return Root()
                }) {
                    RuntimeGlobals {
                        InstanceValue(as: "duplicate") { _ in 2 }
                    }
                }
            }
        }
        #expect(await probe.creationCount == 0)
    }

    @Test("runtime templates reject live values from an existing heap")
    func templatesRejectLiveValues() async throws {
        let runtime = try JavaScriptRuntime()
        let live = try await runtime.evaluate("({ answer: 42 })")
        let component: JavaScriptRuntimeTemplate.Component = {
            var builder = JavaScriptExportBuilder()
            builder.value(live, as: "live")
            var component = JavaScriptRuntimeTemplate.Component()
            component.definitions = [
                .globals(members: builder.members, types: []),
            ]
            return component
        }()

        #expect(throws: JavaScriptError.self) {
            _ = try JavaScriptRuntimeTemplate {
                component
            }
        }
    }

    @Test("registered source syntax is validated before runtime creation")
    func sourceSyntaxIsValidatedEarly() {
        #expect(throws: JavaScriptError.self) {
            _ = try JavaScriptRuntimeTemplate {
                SourceModule(
                    "export const = broken",
                    as: "invalid:syntax",
                    sourceURL: "Scripts/invalid.js"
                )
            }
        }
    }

    @Test("prepared program syntax is validated before runtime creation")
    func programSyntaxIsValidatedEarly() {
        let invalid = JavaScriptProgram(
            "const = broken",
            sourceURL: "Scripts/invalid-program.js"
        )

        #expect(throws: JavaScriptError.self) {
            _ = try JavaScriptRuntimeTemplate {
                Prepare(invalid)
            }
        }
    }

    @Test("factory groups are created sequentially in declaration order")
    func factoriesUseDeclarationOrder() async throws {
        let recorder = FactoryOrderRecorder()
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: {
                await recorder.append(1)
                return Root()
            }) {}
            RuntimeInstance(factory: {
                await recorder.append(2)
                return Root()
            }) {}
            RuntimeInstance(factory: {
                await recorder.append(3)
                return Root()
            }) {}
        }

        _ = try await template.makeRuntime()
        #expect(await recorder.values == [1, 2, 3])
    }

    @Test("factory failure releases a root without publishing a runtime")
    func factoryFailureReleasesRoot() async throws {
        enum ExpectedFailure: Error { case failed }
        let tracker = WeakRootTracker()
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: {
                let root = Root()
                await tracker.record(root)
                return root
            }) {
                RuntimeGlobals {
                    InstanceValue(as: "failure") { (_: Root) async throws -> Int in
                        throw ExpectedFailure.failed
                    }
                }
            }
        }

        await #expect(throws: ExpectedFailure.self) {
            _ = try await template.makeRuntime()
        }
        await Task.yield()
        #expect(await tracker.hasReleasedRoot)
    }

    @Test("cancellation after a factory returns releases its unpublished root")
    func cancellationReleasesFactoryRoot() async throws {
        let gate = CancellableFactoryGate()
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: {
                let root = Root()
                await gate.pause(root)
                return root
            }) {
                RuntimeGlobals {
                    InstanceFunction("answer") { (_: Root) -> Int in 42 }
                }
            }
        }
        let creation = Task { try await template.makeRuntime() }
        await gate.waitUntilPaused()

        creation.cancel()
        await gate.resume()

        await #expect(throws: CancellationError.self) {
            _ = try await creation.value
        }
        await Task.yield()
        #expect(await gate.hasReleasedRoot)
    }

    private final class Root: Sendable {}

    private actor FactoryProbe {
        private(set) var creationCount = 0

        func recordCreation() {
            creationCount += 1
        }
    }

    private actor WeakRootTracker {
        private weak var root: Root?

        var hasReleasedRoot: Bool { root == nil }

        func record(_ root: Root) {
            self.root = root
        }
    }

    private actor FactoryOrderRecorder {
        private(set) var values: [Int] = []

        func append(_ value: Int) {
            values.append(value)
        }
    }

    private actor CancellableFactoryGate {
        private weak var root: Root?
        private var isPaused = false
        private var pauseWaiters: [CheckedContinuation<Void, Never>] = []
        private var resumeContinuation: CheckedContinuation<Void, Never>?

        var hasReleasedRoot: Bool { root == nil }

        func pause(_ root: Root) async {
            self.root = root
            isPaused = true
            for waiter in pauseWaiters { waiter.resume() }
            pauseWaiters.removeAll()
            await withCheckedContinuation { continuation in
                resumeContinuation = continuation
            }
        }

        func waitUntilPaused() async {
            if isPaused { return }
            await withCheckedContinuation { continuation in
                pauseWaiters.append(continuation)
            }
        }

        func resume() {
            resumeContinuation?.resume()
            resumeContinuation = nil
        }
    }
}
