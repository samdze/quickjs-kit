import Foundation
import QuickJSKit
import QuickJSKitMacros
import Testing

/// A counter confined to one JavaScript runtime.
@JavaScriptExport
final class LocalCounter {
    /// The current count.
    var count: Int = 0

    /// Increments the counter.
    ///
    /// - Parameter amount: The amount to add.
    /// - Returns: The updated count.
    func increment(_ amount: Int) -> Int {
        count += amount
        return count
    }

    /// Reads the count asynchronously without leaving the caller's executor.
    ///
    /// - Returns: The current count.
    nonisolated(nonsending) func current() async -> Int {
        count
    }
}

/// An actor exported with Promise-valued members.
@JavaScriptExport
actor MacroActor {
    /// The actor-isolated value.
    var value: Int = 7

    /// Adds an amount.
    ///
    /// - Parameter amount: The amount to add.
    /// - Returns: The updated value.
    @JavaScriptName("add")
    func addValue(_ amount: Int) -> Int {
        value += amount
        return value
    }

    @JavaScriptIgnore
    func hidden() -> Int { -1 }
}

/// Stateless arithmetic helpers.
@JavaScriptExport
final class MacroMultiplier: Sendable {
    /// Doubles a value.
    ///
    /// - Parameter value: The value to double.
    /// - Returns: Twice the supplied value.
    func double(_ value: Int) -> Int {
        value * 2
    }
}

/// A user transferred between Swift and JavaScript.
@JavaScriptExport(scope: .namespace("Example.Models"))
struct MacroUser: Codable, Sendable {
    /// The stable identifier.
    let id: Int

    /// The display name.
    let name: String
}

/// Runtime configuration exposed to scripts.
@JavaScriptExport(scope: .namespace("Example.Models"))
struct MacroConfiguration: Codable, Sendable {
    /// Whether the feature is enabled.
    let isEnabled: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }
}

/// The lifecycle state of a script job.
@JavaScriptExport(scope: .namespace("Example.Models"))
enum MacroState: String, Codable, Sendable {
    /// The job has not started.
    case pending

    /// The legacy completed state.
    @available(*, deprecated, message: "Use the ready state instead.")
    case legacy
}

/// A runtime-visible user value.
@JavaScriptExport
struct RuntimeUser: Codable, Sendable, Equatable {
    /// The stable identifier.
    let id: Int

    /// The display name.
    let name: String
}

/// A runtime-visible user state.
@JavaScriptExport
enum RuntimeUserState: String, Codable, Sendable {
    /// The user may access the application.
    case active

    /// The user may not access the application.
    case suspended
}

/// Integer enum values preserve Number and BigInt boundaries.
@JavaScriptExport
enum RuntimeIntegerState: Int, Codable, Sendable {
    case negative = -1
    case large = 9_007_199_254_740_992
}

/// A constructible Swift service retained by its JavaScript wrapper.
@JavaScriptExport
final class RuntimeChild: Sendable {
    let identifier: Int

    init(identifier: Int) {
        self.identifier = identifier
    }
}

/// A constructible Swift service retained by its JavaScript wrapper.
@JavaScriptExport
final class RuntimeUserService: Sendable {
    let offset: Int

    /// Creates a service.
    ///
    /// - Parameter offset: The amount added to every value.
    init(offset: Int) {
        self.offset = offset
    }

    /// Adds the configured offset.
    ///
    /// - Parameter value: The input value.
    /// - Returns: The adjusted value.
    func adjust(_ value: Int) -> Int {
        value + offset
    }

    /// Returns this service while preserving JavaScript identity.
    func same() -> RuntimeUserService { self }

    /// Reads an optional child host reference.
    func identify(_ child: RuntimeChild?) -> Int {
        child?.identifier ?? -1
    }

    /// Creates an optional host result on the actor executor.
    func child() -> RuntimeChild? {
        RuntimeChild(identifier: offset)
    }

    /// Creates a host result from a Codable argument.
    func makeChild(identifier: Int) -> RuntimeChild {
        RuntimeChild(identifier: identifier)
    }

    /// Triples a value without creating a service.
    static func triple(_ value: Int) -> Int {
        value * 3
    }
}

/// A host class with strict same-arity initializer overloads.
@JavaScriptExport
final class RuntimeOverloadedService: Sendable {
    let kind: String

    init(value: String) {
        kind = "string:\(value)"
    }

    init(value: Bool) {
        kind = "boolean:\(value)"
    }
}

/// A non-Sendable class confined to the runtime that constructs it.
@JavaScriptExport
final class RuntimeLocalConstructible {
    var value: Int

    init(value: Int) {
        self.value = value
    }

    func increment() -> Int {
        value += 1
        return value
    }
}

/// A host actor created through an asynchronous factory.
@JavaScriptExport
actor RuntimeAsyncService {
    let value: Int

    /// Creates an actor asynchronously.
    ///
    /// - Parameter value: The stored value.
    init(value: Int) async {
        self.value = value
    }

    /// Returns the stored value.
    func read() -> Int { value }

    /// Reads a direct optional host reference on the actor executor.
    func identify(_ child: RuntimeChild?) -> Int {
        child?.identifier ?? -1
    }

    /// Creates an optional host result on the actor executor.
    func child(identifier: Int) -> RuntimeChild? {
        RuntimeChild(identifier: identifier)
    }
}

private actor HostCallGate {
    private var resultContinuation: CheckedContinuation<Int, Never>?
    private var startContinuations: [CheckedContinuation<Void, Never>] = []

    func wait() async -> Int {
        for continuation in startContinuations {
            continuation.resume()
        }
        startContinuations.removeAll()
        return await withCheckedContinuation { continuation in
            resultContinuation = continuation
        }
    }

    func waitUntilStarted() async {
        if resultContinuation != nil { return }
        await withCheckedContinuation { continuation in
            startContinuations.append(continuation)
        }
    }

    func resume(returning value: Int) {
        resultContinuation?.resume(returning: value)
        resultContinuation = nil
    }
}

private let hostCallGate = HostCallGate()

/// A host actor whose method remains suspended during a garbage collection.
@JavaScriptExport
actor RuntimeSuspendingService {
    init() {}

    /// Waits until the test releases the call.
    ///
    /// - Returns: The released value.
    func wait() async -> Int {
        await hostCallGate.wait()
    }
}

@Suite("Macro-generated runtime APIs")
struct MacroRuntimeTests {
    @Test("final Swift classes are constructible JavaScript host types")
    func hostTypesAreConstructible() async throws {
        let template = try JavaScriptRuntimeTemplate {
            SwiftModule("host:users") {
                JavaScriptType(RuntimeUserService.self)
            }
            SwiftModule("host:children") {
                JavaScriptType(RuntimeChild.self)
            }
        }
        let declarations = try template.environmentDescription()
            .typeScriptDeclarations()
        #expect(declarations.contains("export class RuntimeUserService"))
        #expect(
            declarations.contains(
                "child?: import(\"host:children\").RuntimeChild | null"
            )
        )
        let runtime = try await template.makeRuntime()
        let result: Int = try await runtime.evaluate("""
            Promise.all([
                import("host:users"),
                import("host:children"),
            ]).then(([{ RuntimeUserService }, { RuntimeChild }]) => {
                const service = new RuntimeUserService(2);
                const child = new RuntimeChild(42);
                return service.adjust(40)
                    + (service === service.same() ? 0 : 1000)
                    + (service.identify(child) === 42 ? 0 : 1000)
                    + (service.identify(null) === -1 ? 0 : 1000)
                    + (service.child().identifier === 2 ? 0 : 1000)
                    + (service.makeChild(9).identifier === 9 ? 0 : 1000);
            })
            """)
        #expect(result == 42)
        let staticResult: Int = try await runtime.evaluate("""
            import("host:users").then(({ RuntimeUserService }) =>
                RuntimeUserService.triple(14)
            )
            """)
        #expect(staticResult == 42)
    }

    @Test("host initializer overloads are selected by strict argument decoding")
    func hostInitializerOverloadsUseStrictDecoding() async throws {
        let template = try JavaScriptRuntimeTemplate {
            Globals {
                JavaScriptType(RuntimeOverloadedService.self)
            }
        }
        let runtime = try await template.makeRuntime()
        let first: String = try await runtime.evaluate(
            "new RuntimeOverloadedService(\"value\").kind"
        )
        let second: String = try await runtime.evaluate(
            "new RuntimeOverloadedService(true).kind"
        )
        let values = [first, second]
        #expect(values == ["string:value", "boolean:true"])

        let rejectsNumber: Bool = try await runtime.evaluate("""
            try {
                new RuntimeOverloadedService(42);
                false;
            } catch (error) {
                error instanceof TypeError
                    && error.message.includes("Candidates:");
            }
        """)
        #expect(rejectsNumber)
    }

    @Test("non-Sendable constructed classes remain runtime confined")
    func nonSendableConstructedHostIsConfined() async throws {
        let template = try JavaScriptRuntimeTemplate {
            Globals {
                JavaScriptType(RuntimeLocalConstructible.self)
            }
        }
        let first = try await template.makeRuntime()
        let second = try await template.makeRuntime()
        let firstValue: Int = try await first.evaluate("""
            globalThis.local = new RuntimeLocalConstructible(40);
            local.increment();
            """)
        let secondValue: Int = try await second.evaluate("""
            globalThis.local = new RuntimeLocalConstructible(10);
            local.increment();
            """)
        #expect(firstValue == 41)
        #expect(secondValue == 11)
    }

    @Test("actors with async initializers use native Promise factories")
    func asyncHostFactories() async throws {
        let template = try JavaScriptRuntimeTemplate {
            SwiftModule("host:actors") {
                JavaScriptType(RuntimeAsyncService.self)
                JavaScriptType(RuntimeChild.self)
            }
        }
        let runtime = try await template.makeRuntime()
        let value: Int = try await runtime.evaluate("""
            import("host:actors").then(async ({ RuntimeAsyncService, RuntimeChild }) => {
                const service = await RuntimeAsyncService.create(42);
                const child = new RuntimeChild(7);
                return await service.read()
                    + (await service.identify(child) === 7 ? 0 : 1000)
                    + (await service.identify(null) === -1 ? 0 : 1000)
                    + ((await service.child(42)).identifier === 42 ? 0 : 1000);
            })
            """)
        #expect(value == 42)
    }

    @Test("host object limits and garbage collection are observable")
    func hostObjectLimits() async throws {
        let template = try JavaScriptRuntimeTemplate(
            configuration: .init(maximumHostObjectCount: 1)
        ) {
            Globals {
                JavaScriptType(RuntimeUserService.self)
            }
        }
        let runtime = try await template.makeRuntime()
        let installed: Bool = try await runtime.evaluate(
            "globalThis.service = new RuntimeUserService(1); true"
        )
        #expect(installed)
        #expect(await runtime.resourceUsage().hostObjectCount == 1)
        let reusedWithinLimit: Bool = try await runtime.evaluate(
            "service.same() === service"
        )
        #expect(reusedWithinLimit)
        #expect(await runtime.resourceUsage().hostObjectCount == 1)

        let limited: Bool = try await runtime.evaluate("""
            try {
                new RuntimeUserService(2);
                false;
            } catch (error) {
                error instanceof RangeError;
            }
            """)
        #expect(limited)

        _ = try await runtime.evaluate("delete globalThis.service")
        await runtime.collectGarbage()
        #expect(await runtime.resourceUsage().hostObjectCount == 0)
    }

    @Test("active async host calls retain their Swift receiver")
    func activeHostCallsRetainTheirReceiver() async throws {
        let template = try JavaScriptRuntimeTemplate {
            Globals {
                JavaScriptType(RuntimeSuspendingService.self)
            }
        }
        let runtime = try await template.makeRuntime()
        let started: Bool = try await runtime.evaluate("""
            globalThis.service = new RuntimeSuspendingService();
            globalThis.pendingHostCall = service.wait();
            delete globalThis.service;
            true;
            """)
        #expect(started)
        await hostCallGate.waitUntilStarted()

        await runtime.collectGarbage()
        #expect(await runtime.resourceUsage().hostObjectCount == 1)

        await hostCallGate.resume(returning: 42)
        let result: Int = try await runtime.evaluate("pendingHostCall")
        #expect(result == 42)
        let deleted: Bool = try await runtime.evaluate(
            "delete globalThis.pendingHostCall"
        )
        #expect(deleted)
        await runtime.collectGarbage()
        #expect(await runtime.resourceUsage().hostObjectCount == 0)
    }

    @Test("structs and enums become explicit JavaScript value types")
    func valueTypesArePublishedExplicitly() async throws {
        let template = try JavaScriptRuntimeTemplate {
            Globals {
                JavaScriptType(RuntimeUser.self)
                JavaScriptType(RuntimeUserState.self)
                JavaScriptType(RuntimeIntegerState.self)
            }
        }
        let declarations = try template.environmentDescription()
            .typeScriptDeclarations()
        #expect(declarations.contains("interface RuntimeUser"))
        #expect(declarations.contains("new(value: RuntimeUser): RuntimeUser"))
        #expect(declarations.contains("readonly active: \"active\""))
        #expect(declarations.contains("readonly large: 9007199254740992n"))

        let runtime = try await template.makeRuntime()
        let user: RuntimeUser = try await runtime.evaluate("""
            new RuntimeUser({ id: 42, name: "Ada", ignored: true })
            """)
        let isInstance: Bool = try await runtime.evaluate("""
            new RuntimeUser({ id: 1, name: "Grace" }) instanceof RuntimeUser
            """)
        let status: String = try await runtime.evaluate(
            "RuntimeUserState(RuntimeUserState.active)"
        )
        let isFrozen: Bool = try await runtime.evaluate(
            "Object.isFrozen(RuntimeUserState)"
        )
        let integerCases: Bool = try await runtime.evaluate("""
            RuntimeIntegerState.negative === -1
                && typeof RuntimeIntegerState.large === "bigint"
                && RuntimeIntegerState(9007199254740992n)
                    === RuntimeIntegerState.large
            """)

        #expect(user == RuntimeUser(id: 42, name: "Ada"))
        #expect(isInstance)
        #expect(status == "active")
        #expect(isFrozen)
        #expect(integerCases)
    }

    @Test("types can be registered immediately as globals and module exports")
    func immediateTypeRegistration() async throws {
        let globalRuntime = try JavaScriptRuntime()
        try await globalRuntime.registerType(RuntimeUser.self)
        try await globalRuntime.registerType(RuntimeUserService.self)
        let globalResult: Int = try await globalRuntime.evaluate("""
            const user = new RuntimeUser({ id: 40, name: "Ada" });
            new RuntimeUserService(2).adjust(user.id);
            """)
        #expect(globalResult == 42)

        let moduleRuntime = try JavaScriptRuntime()
        try await moduleRuntime.defineModule("host:immediate") { module in
            module.type(RuntimeUserState.self)
            module.type(RuntimeChild.self)
        }
        let moduleResult: String = try await moduleRuntime.evaluate("""
            import("host:immediate").then(({ RuntimeUserState }) =>
                RuntimeUserState(RuntimeUserState.active)
            )
            """)
        #expect(moduleResult == "active")
    }

    @Test("type publication is permanent unique and scope checked")
    func typeRegistrationValidation() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.registerType(RuntimeUser.self)
        await #expect(throws: JavaScriptError.self) {
            try await runtime.registerType(RuntimeUser.self)
        }
        await #expect(throws: JavaScriptError.self) {
            try await runtime.registerType(MacroUser.self)
        }
    }

    @Test("failed type publication rolls back runtime registration")
    func failedTypePublicationRollsBack() async throws {
        let runtime = try JavaScriptRuntime()
        let prepared: Bool = try await runtime.evaluate("""
            Object.defineProperty(globalThis, "RuntimeUser", {
                configurable: false,
                value: 1,
            });
            true;
            """)
        #expect(prepared)

        let first = await #expect(throws: JavaScriptError.self) {
            try await runtime.registerType(RuntimeUser.self)
        }
        let second = await #expect(throws: JavaScriptError.self) {
            try await runtime.registerType(RuntimeUser.self)
        }
        #expect(first?.message == second?.message)
        #expect(first?.message.contains("already registered") == false)
    }

    @Test("failed module materialization releases every type reservation")
    func failedModuleMaterializationReleasesReservations() async throws {
        let runtime = try JavaScriptRuntime()
        await #expect(throws: JavaScriptError.self) {
            try await runtime.defineModule("host:invalid-types") { module in
                module.type(RuntimeChild.self)
                module.type(RuntimeChild.self)
            }
        }

        try await runtime.registerType(RuntimeChild.self)
        let value: Int = try await runtime.evaluate(
            "new RuntimeChild(42).identifier"
        )
        #expect(value == 42)
    }

    @Test("a non-Sendable root remains local to each generated runtime export")
    func nonSendableRootIsRuntimeLocal() async throws {
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { LocalCounter() }) {
                RuntimeObject(as: "counter")
            }
        }
        let declarations = try template.environmentDescription()
            .typeScriptDeclarationBundle()
        #expect(declarations.declarations.contains("count: number | bigint;"))
        #expect(!declarations.declarations.contains("readonly count:"))
        #expect(declarations.declarations.contains("A counter confined to one JavaScript runtime."))
        #expect(declarations.declarations.contains("Increments the counter."))
        #expect(declarations.declarations.contains("The current count."))
        #expect(declarations.sourceMap.contains("counter.count"))
        #expect(declarations.sourceMap.contains("increment.amount"))

        async let first = template.makeRuntime()
        async let second = template.makeRuntime()
        let (firstRuntime, secondRuntime) = try await (first, second)

        let firstValue: Int = try await firstRuntime.evaluate(
            "counter.increment(2)"
        )
        let secondValue: Int = try await secondRuntime.evaluate(
            "counter.increment(5)"
        )
        let asynchronous: Int = try await firstRuntime.evaluate(
            "counter.current()"
        )
        let assigned: Int = try await firstRuntime.evaluate(
            "counter.count = 11; counter.count"
        )
        let descriptor: Bool = try await firstRuntime.evaluate(
            "Object.getOwnPropertyDescriptor(counter, 'count').enumerable && !Object.getOwnPropertyDescriptor(counter, 'count').configurable"
        )

        #expect(firstValue == 2)
        #expect(secondValue == 5)
        #expect(asynchronous == 2)
        #expect(assigned == 11)
        #expect(descriptor)
    }

    @Test("an actor macro generates async methods and Promise-valued properties")
    func actorMacroGeneratesPromises() async throws {
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { MacroActor() }) {
                RuntimeObject(as: "service")
            }
        }
        let runtime = try await template.makeRuntime()

        let value: Int = try await runtime.evaluate("service.value")
        let updated: Int = try await runtime.evaluate("service.add(5)")
        let hidden: Bool = try await runtime.evaluate(
            "'hidden' in service"
        )

        #expect(value == 7)
        #expect(updated == 12)
        #expect(!hidden)
    }

    @Test("inferred generated definitions populate globals objects modules and tooling")
    func inferredDefinitionsPopulateEveryDestination() async throws {
        let template = try JavaScriptRuntimeTemplate {
            RuntimeInstance(factory: { MacroMultiplier() }) {
                RuntimeGlobals()
                RuntimeObject(as: "multiplier")
                RuntimeModule("host:multiplier")
            }
        }
        let declarations = try template.environmentDescription()
            .typeScriptDeclarations()
        #expect(declarations.contains("Stateless arithmetic helpers."))
        #expect(declarations.contains("Doubles a value."))
        #expect(declarations.contains("@param value - The value to double."))
        #expect(declarations.contains("@returns Twice the supplied value."))

        let runtime = try await template.makeRuntime()
        let global: Int = try await runtime.evaluate("double(3)")
        let object: Int = try await runtime.evaluate("multiplier.double(4)")
        let module = try await runtime.importModule("host:multiplier")
        let function = try await module.function(forExport: "double")
        let imported: Int = try await function.call(5)

        #expect(global == 6)
        #expect(object == 8)
        #expect(imported == 10)
    }

    @Test("removing an immediate generated export releases its root")
    func removingGeneratedExportReleasesRoot() async throws {
        let runtime = try JavaScriptRuntime()
        weak var retainedRoot: MacroActor?
        let binding: JavaScriptBinding
        do {
            let root = MacroActor()
            retainedRoot = root
            binding = try await runtime.export(root, as: "service")
        }

        #expect(retainedRoot != nil)
        #expect(try await binding.remove())
        #expect(retainedRoot == nil)
    }

    @Test("a value export supplies deterministic TypeScript metadata")
    func valueExportSuppliesSchema() {
        let schema = MacroUser.typeScriptSchema
        #expect(schema.scope == .namespace("Example.Models"))
        #expect(schema.definitions.count == 1)
    }

    @Test("value exports preserve struct enum and case documentation")
    func valueExportsPreserveDocumentation() throws {
        let environment = try JavaScriptRuntimeTemplate {}
            .environmentDescription(
                including: [
                    MacroUser.typeScriptSchema,
                    MacroConfiguration.typeScriptSchema,
                    MacroState.typeScriptSchema,
                ]
            )
        let declarations = try environment.typeScriptDeclarations()

        #expect(declarations.contains("A user transferred between Swift and JavaScript."))
        #expect(declarations.contains("Runtime configuration exposed to scripts."))
        #expect(declarations.contains("Whether the feature is enabled."))
        #expect(declarations.contains("The lifecycle state of a script job."))
        #expect(declarations.contains("The job has not started."))
        #expect(declarations.contains("Use the ready state instead."))
    }

    @Test("macro source locations produce declaration maps")
    func macroSourceLocationsProduceMaps() throws {
        let environment = try JavaScriptRuntimeTemplate {}
            .environmentDescription(including: [MacroUser.typeScriptSchema])
        let bundle = try environment.typeScriptDeclarationBundle()

        #expect(bundle.declarations.contains("sourceMappingURL"))
        #expect(bundle.sourceMap.contains("MacroRuntimeTests.swift"))
        #expect(bundle.sourceMap.contains("MacroUser.id"))
        #expect(bundle.sourceMap.contains("\"version\": 3"))
        #expect(
            (try JSONSerialization.jsonObject(
                with: Data(bundle.sourceMap.utf8)
            )) is [String: Any]
        )
    }
}
