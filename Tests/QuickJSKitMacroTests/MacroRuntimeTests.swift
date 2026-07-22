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
@TypeScriptModel(scope: .namespace("Example.Models"))
struct MacroUser: Codable, Sendable {
    /// The stable identifier.
    let id: Int

    /// The display name.
    let name: String
}

/// Runtime configuration exposed to scripts.
@TypeScriptModel(scope: .namespace("Example.Models"))
final class MacroConfiguration: Codable, Sendable {
    /// Whether the feature is enabled.
    let isEnabled: Bool

    init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }
}

/// The lifecycle state of a script job.
@TypeScriptModel(scope: .namespace("Example.Models"))
enum MacroState: String, Codable, Sendable {
    /// The job has not started.
    case pending

    /// The legacy completed state.
    @available(*, deprecated, message: "Use the ready state instead.")
    case legacy
}

@Suite("Macro-generated runtime APIs")
struct MacroRuntimeTests {
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

    @Test("a model macro supplies deterministic TypeScript metadata")
    func modelMacroSuppliesSchema() {
        let schema = MacroUser.typeScriptSchema
        #expect(schema.scope == .namespace("Example.Models"))
        #expect(schema.definitions.count == 1)
    }

    @Test("model macros preserve struct class enum and case documentation")
    func modelMacrosPreserveDocumentation() throws {
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
