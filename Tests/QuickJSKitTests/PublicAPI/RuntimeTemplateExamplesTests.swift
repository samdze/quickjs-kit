import QuickJSKit
import Testing

@Suite("Declarative runtime templates")
struct RuntimeTemplateExamplesTests {
    @Test("a template installs globals objects and modules into an independent runtime")
    func templateInstallsCompleteEnvironment() async throws {
        let shared = SharedGreeting()
        let template = try JavaScriptRuntimeTemplate {
            Globals {
                Function(
                    "sum",
                    options: .init(parameterNames: ["left", "right"])
                ) { (left: Int, right: Int) in
                    left + right
                }
                Value("1.0", as: "version")
            }
            SharedObject(shared, as: "greeting") { shared in
                Function("message") { () async -> String in
                    await shared.message()
                }
            }
            SwiftModule("host:math") {
                Function("double") { (value: Int) in value * 2 }
            }
            SourceModule(
                "export const answer = 42",
                as: "app:answer",
                sourceURL: "Scripts/answer.js",
                declarations: .init("export const answer: number;")
            )
        }

        let runtime = try await template.makeRuntime()
        let sum: Int = try await runtime.evaluate("sum(20, 22)")
        let version: String = try await runtime.evaluate("version")
        let message: String = try await runtime.evaluate("greeting.message()")
        let doubled: Int = try await runtime.evaluateModule(
            "import { double } from 'host:math'; export const value = double(21);"
        ).value(forExport: "value")
        let answer: Int = try await runtime.importModule("app:answer")
            .value(forExport: "answer")

        #expect(sum == 42)
        #expect(version == "1.0")
        #expect(message == "hello")
        #expect(doubled == 42)
        #expect(answer == 42)
    }

    @Test("a template describes TypeScript tooling before creating a runtime")
    func templateDescribesToolingWithoutRuntime() async throws {
        let probe = FactoryProbe()
        let template = try JavaScriptRuntimeTemplate {
            Globals {
                Function(
                    "lookup",
                    options: .init(
                        parameterNames: ["id"],
                        documentation: .init(
                            summary: "Looks up one value.",
                            parameters: ["id": "The stable identifier."],
                            returns: "The matching value."
                        )
                    )
                ) { (id: Int) -> String in String(id) }
            }
            RuntimeInstance(factory: {
                await probe.recordCreation()
                return Counter()
            }) {
                RuntimeObject(as: "counter", documentation: "An isolated counter.") {
                    InstanceFunction("next") { (root: Counter) async -> Int in
                        await root.next()
                    }
                }
            }
        }

        let before = try template.environmentDescription()
        let declarations = try before.typeScriptDeclarations()
        #expect(declarations.contains("declare function lookup"))
        #expect(declarations.contains("declare const counter"))
        #expect(await probe.creationCount == 0)

        let runtime = try await template.makeRuntime()
        #expect(await probe.creationCount == 1)
        let after = try await runtime.environmentDescription()
        #expect(
            try before.typeScriptDeclarations()
                == after.typeScriptDeclarations()
        )
        #expect(
            try before.typeScriptWorkspace()
                == after.typeScriptWorkspace()
        )
    }

    @Test("per-runtime factories provide independent Swift and JavaScript state")
    func factoriesProvideIndependentState() async throws {
        let template = try counterTemplate()
        async let firstRuntime = template.makeRuntime()
        async let secondRuntime = template.makeRuntime()
        let (first, second) = try await (firstRuntime, secondRuntime)

        let firstValue: Int = try await first.evaluate("nextCounter()")
        let secondValue: Int = try await second.evaluate("nextCounter()")
        let nextFirstValue: Int = try await first.evaluate("counter.next()")
        let moduleValue: Int = try await second.evaluateModule(
            "import { next } from 'host:counter'; export const value = await next();"
        ).value(forExport: "value")

        try await first.global.set("first", forProperty: "runtimeName")
        let secondHasName = try await second.global.hasProperty("runtimeName")

        #expect(firstValue == 1)
        #expect(secondValue == 1)
        #expect(nextFirstValue == 2)
        #expect(moduleValue == 2)
        #expect(!secondHasName)
    }

    @Test("a per-runtime root can produce snapshot values")
    func factoryProducesSnapshotValues() async throws {
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { Counter(initialValue: 41) }) {
                RuntimeObject(as: "counter") {
                    InstanceValue(as: "initial") { root in
                        await root.currentValue()
                    }
                    InstanceFunction("next") { (root: Counter) async -> Int in
                        await root.next()
                    }
                }
            }
        }

        let runtime = try await template.makeRuntime()
        let initial: Int = try await runtime.evaluate("counter.initial")
        let next: Int = try await runtime.evaluate("counter.next()")

        #expect(initial == 41)
        #expect(next == 42)
    }

    @Test("root-aware functions preserve Swift effects and Void results")
    func rootAwareFunctionsPreserveEffects() async throws {
        enum ExpectedFailure: Error { case failed }
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { Counter() }) {
                RuntimeGlobals {
                    InstanceFunction("syncValue") { (_: Counter) -> Int in 1 }
                    InstanceFunction("throwingValue") {
                        (_: Counter) throws -> Int in
                        throw ExpectedFailure.failed
                    }
                    InstanceFunction("asyncValue") { (_: Counter) async -> Int in 3 }
                    InstanceFunction("asyncThrowingValue") {
                        (_: Counter) async throws -> Int in 4
                    }
                    InstanceFunction("syncVoid") { (_: Counter) -> Void in }
                    InstanceFunction("throwingVoid") { (_: Counter) throws -> Void in }
                    InstanceFunction("asyncVoid") { (_: Counter) async -> Void in }
                    InstanceFunction("asyncThrowingVoid") {
                        (_: Counter) async throws -> Void in
                    }
                }
            }
        }
        let runtime = try await template.makeRuntime()

        let values: [Int] = try await runtime.evaluate(
            "Promise.all([syncValue(), asyncValue(), asyncThrowingValue()])"
        )
        let thrownName: String = try await runtime.evaluate(
            "try { throwingValue() } catch (error) { error.name }"
        )
        let voids: Bool = try await runtime.evaluate(
            "syncVoid() === undefined && throwingVoid() === undefined"
        )
        let asyncVoids: Bool = try await runtime.evaluate(
            "Promise.all([asyncVoid(), asyncThrowingVoid()]).then(values => values.every(value => value === undefined))"
        )

        #expect(values == [1, 3, 4])
        #expect(thrownName == "SwiftError")
        #expect(voids)
        #expect(asyncVoids)
    }

    @Test("created runtimes retain their configuration and remain independently mutable")
    func runtimeConfigurationAndTemplateRemainIndependent() async throws {
        let configuration = JavaScriptRuntime.Configuration(
            memoryLimit: 8 * 1_024 * 1_024,
            maximumStackSize: 256 * 1_024,
            defaultExecutionTimeout: .seconds(1)
        )
        let template = try JavaScriptRuntimeTemplate(configuration: configuration) {
            Globals {
                Value("original", as: "name")
            }
        }
        let originalDescription = try template.environmentDescription()
        let runtime = try await template.makeRuntime()

        try await runtime.global.set("changed", forProperty: "name")
        try await runtime.global.set(42, forProperty: "additional")

        #expect(runtime.configuration == configuration)
        #expect(try template.environmentDescription() == originalDescription)
        #expect(try await runtime.environmentDescription() != originalDescription)
    }

    @Test("template module loaders remain asynchronous and runtime-local")
    func templateInstallsModuleLoader() async throws {
        let template = try JavaScriptRuntimeTemplate {
            ModuleLoader(
                .init { request in
                    JavaScriptModuleSource(
                        source: "export const name = '\(request.specifier)'",
                        sourceURL: "memory:///\(request.specifier)",
                        typeScriptDeclarations: .init("export const name: string;")
                    )
                }
            )
        }

        let runtime = try await template.makeRuntime()
        let name: String = try await runtime.importModule("loaded:module")
            .value(forExport: "name")
        #expect(name == "loaded:module")
    }

    @Test("the template DSL composes conditional and repeated declarations")
    func templateDSLComposesControlFlow() async throws {
        struct Values: Decodable, Sendable, Equatable {
            let answer: Int
            let optionalValue: String
            let firstValue: Int
            let secondValue: Int
            let selection: String
            let available: Bool
        }

        let includeAnswer = true
        let optionalName: String? = "optionalValue"
        let repeatedNames = ["firstValue", "secondValue"]
        let selectedValue = 2

        let template = try JavaScriptRuntimeTemplate {
            Globals {
                if includeAnswer {
                    Value(42, as: "answer")
                }
                if let optionalName {
                    Value("present", as: optionalName)
                }
                for (index, name) in repeatedNames.enumerated() {
                    Value(index + 1, as: name)
                }
                switch selectedValue {
                case 1:
                    Value("one", as: "selection")
                default:
                    Value("two", as: "selection")
                }
                if #available(macOS 14, *) {
                    Value(true, as: "available")
                }
            }
        }

        let runtime = try await template.makeRuntime()
        let values: Values = try await runtime.evaluate(
            "({ answer, optionalValue, firstValue, secondValue, selection, available })"
        )

        #expect(
            values == Values(
                answer: 42,
                optionalValue: "present",
                firstValue: 1,
                secondValue: 2,
                selection: "two",
                available: true
            )
        )
    }

    @Test("ordinary DSL functions preserve every Swift closure effect")
    func ordinaryDSLFunctionsPreserveEffects() async throws {
        let template = try JavaScriptRuntimeTemplate {
            Globals {
                Function("syncValue") { 1 }
                Function("throwingValue") { () throws -> Int in 2 }
                Function("asyncValue") { () async -> Int in 3 }
                Function("asyncThrowingValue") { () async throws -> Int in 4 }
                Function("syncVoid") { () -> Void in }
                Function("throwingVoid") { () throws -> Void in }
                Function("asyncVoid") { () async -> Void in }
                Function("asyncThrowingVoid") { () async throws -> Void in }
            }
        }
        let runtime = try await template.makeRuntime()

        let values: [Int] = try await runtime.evaluate(
            "Promise.all([syncValue(), throwingValue(), asyncValue(), asyncThrowingValue()])"
        )
        let voidValuesAreUndefined: Bool = try await runtime.evaluate(
            "Promise.all([syncVoid(), throwingVoid(), asyncVoid(), asyncThrowingVoid()]).then(values => values.every(value => value === undefined))"
        )

        #expect(values == [1, 2, 3, 4])
        #expect(voidValuesAreUndefined)
    }

    @Test("multiple startup groups preserve lexical action order")
    func multipleStartupGroupsPreserveOrder() async throws {
        let first = JavaScriptProgram("globalThis.startupOrder = ['first']")
        let second = JavaScriptProgram("globalThis.startupOrder.push('second')")
        let template = try JavaScriptRuntimeTemplate {
            Startup {
                Run(first)
            }
            Startup {
                Run(second)
            }
        }

        let runtime = try await template.makeRuntime()
        let order: [String] = try await runtime.evaluate("startupOrder")

        #expect(order == ["first", "second"])
    }

    private func counterTemplate() throws -> JavaScriptRuntimeTemplate {
        try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { Counter() }) {
                RuntimeGlobals {
                    InstanceFunction("nextCounter") { (root: Counter) async -> Int in
                        await root.next()
                    }
                }
                RuntimeObject(as: "counter") {
                    InstanceFunction("next") { (root: Counter) async -> Int in
                        await root.next()
                    }
                }
                RuntimeModule("host:counter") {
                    InstanceFunction("next") { (root: Counter) async -> Int in
                        await root.next()
                    }
                }
            }
        }
    }

    private actor Counter {
        private var value: Int

        init(initialValue: Int = 0) {
            value = initialValue
        }

        func next() -> Int {
            value += 1
            return value
        }

        func currentValue() -> Int { value }
    }

    private actor SharedGreeting {
        func message() -> String { "hello" }
    }

    private actor FactoryProbe {
        private(set) var creationCount = 0

        func recordCreation() {
            creationCount += 1
        }
    }
}
