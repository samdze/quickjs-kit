import QuickJSKit
import Testing

@Suite("Prepared JavaScript program examples")
struct PreparedProgramExamplesTests {
    @Test("a reusable program compiles once and evaluates repeatedly")
    func reusableProgramEvaluatesRepeatedly() async throws {
        let program = JavaScriptProgram(
            """
            globalThis.programRuns = (globalThis.programRuns ?? 0) + 1;
            programRuns;
            """,
            sourceURL: "Scripts/counter.js"
        )
        let runtime = try JavaScriptRuntime()

        try await runtime.prepare(program)
        let first: Int = try await runtime.evaluate(program)
        let second: Int = try await runtime.evaluate(program)

        #expect(first == 1)
        #expect(second == 2)
    }

    @Test("prepared programs preserve synchronous and asynchronous typed evaluation")
    func preparedProgramsPreserveTypedEvaluation() async throws {
        let immediate = JavaScriptProgram("20 + 22")
        let promised = JavaScriptProgram("Promise.resolve(42)")
        let runtime = try JavaScriptRuntime()

        let synchronous = try await runtime.run { runtime in
            try runtime.evaluate(immediate, as: Int.self)
        }
        let asynchronous: Int = try await runtime.evaluate(promised)

        #expect(synchronous == 42)
        #expect(asynchronous == 42)
    }

    @Test("prepared program errors preserve their diagnostic source")
    func preparedProgramErrorsPreserveSource() async throws {
        let program = JavaScriptProgram(
            "throw new Error('prepared failure')",
            sourceURL: "Scripts/failure.js"
        )
        let runtime = try JavaScriptRuntime()

        do {
            let _: Int = try await runtime.evaluate(program)
            Issue.record("Expected prepared program evaluation to throw.")
        } catch let error as JavaScriptError {
            #expect(error.kind == .exception)
            #expect(error.message == "prepared failure")
            #expect(error.sourceURL == "Scripts/failure.js")
            #expect(error.stack?.contains("Scripts/failure.js") == true)
        }
    }

    @Test("execution controls interrupt prepared programs without poisoning their runtime")
    func preparedProgramsRespectExecutionControls() async throws {
        let program = JavaScriptProgram(
            "while (true) {}",
            sourceURL: "Scripts/infinite.js"
        )
        let runtime = try JavaScriptRuntime()

        do {
            let _: Int = try await runtime.evaluate(
                program,
                options: .init(timeout: .after(.milliseconds(1)))
            )
            Issue.record("Expected prepared program execution to time out.")
        } catch let error as JavaScriptError {
            #expect(error.kind == .timeout)
            #expect(error.sourceURL == "Scripts/infinite.js")
        }

        let answer: Int = try await runtime.evaluate(JavaScriptProgram("42"))
        #expect(answer == 42)
    }

    @Test("template startup runs after per-runtime Swift exports are installed")
    func startupRunsAfterFactoryExports() async throws {
        let startup = JavaScriptProgram(
            """
            startupValue().then(value => {
                globalThis.bootstrappedValue = value;
                return value;
            })
            """,
            sourceURL: "Scripts/startup.js"
        )
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { StartupRoot() }) {
                RuntimeGlobals {
                    InstanceFunction("startupValue") { (_: StartupRoot) async -> Int in
                        42
                    }
                }
            }
            Startup {
                Run(startup)
            }
        }

        let runtime = try await template.makeRuntime()
        let value: Int = try await runtime.evaluate("bootstrappedValue")

        #expect(value == 42)
    }

    @Test("templates distinguish linked modules from startup imports")
    func templatesDistinguishModulePreparation() async throws {
        let preloaded = try JavaScriptRuntimeTemplate {
            Globals {
                Value(0, as: "executions")
            }
            SourceModule(
                "globalThis.executions += 1; export const value = executions;",
                as: "app:preloaded"
            )
            Startup {
                PreloadModule("app:preloaded")
            }
        }
        let preloadedRuntime = try await preloaded.makeRuntime()
        let beforeImport: Int = try await preloadedRuntime.evaluate("executions")
        let preloadedModule = try await preloadedRuntime.importModule("app:preloaded")
        let afterImport: Int = try await preloadedModule.value(forExport: "value")

        let started = try JavaScriptRuntimeTemplate {
            Globals {
                Value(0, as: "executions")
            }
            SourceModule(
                "globalThis.executions += 1; export function answer() { return 42; }",
                as: "app:started"
            )
            Startup {
                ImportModule("app:started")
            }
        }
        let startedRuntime = try await started.makeRuntime()
        let startupExecutions: Int = try await startedRuntime.evaluate("executions")
        let module = try await startedRuntime.importModule("app:started")
        let answer = try await module.function(forExport: "answer")
        let result: Int = try await answer.call()

        #expect(beforeImport == 0)
        #expect(afterImport == 1)
        #expect(startupExecutions == 1)
        #expect(result == 42)
    }

    @Test("startup module imports await top-level asynchronous initialization")
    func startupModuleAwaitsTopLevelInitialization() async throws {
        let template = try JavaScriptRuntimeTemplate {
            SourceModule(
                """
                export const answer = await Promise.resolve(42);
                globalThis.topLevelStartupFinished = true;
                """,
                as: "app:async-startup"
            )
            Startup {
                ImportModule("app:async-startup")
            }
        }

        let runtime = try await template.makeRuntime()
        let finished: Bool = try await runtime.evaluate("topLevelStartupFinished")
        let module = try await runtime.importModule("app:async-startup")
        let answer: Int = try await module.value(forExport: "answer")

        #expect(finished)
        #expect(answer == 42)
    }

    @Test("startup JavaScript does not change the declared tooling environment")
    func startupPreservesDeclaredEnvironment() async throws {
        let startup = JavaScriptProgram("globalThis.scriptOnlyValue = 42")
        let template = try JavaScriptRuntimeTemplate {
            Globals {
                Value("host", as: "declaredValue")
            }
            Startup {
                Run(startup)
            }
        }
        let expected = try template.environmentDescription()

        let runtime = try await template.makeRuntime()
        let actual = try await runtime.environmentDescription()
        let scriptOnlyValue: Int = try await runtime.evaluate("scriptOnlyValue")

        #expect(actual == expected)
        #expect(scriptOnlyValue == 42)
    }

    private final class StartupRoot: Sendable {}
}
