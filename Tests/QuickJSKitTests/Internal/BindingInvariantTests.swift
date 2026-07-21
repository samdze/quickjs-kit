import Testing
@testable import QuickJSKit

@Suite("Binding and promise invariants")
struct BindingInvariantTests {
    @Test("borrowed callback arguments do not enter the live-value registry")
    func borrowedArgumentsRemainTemporary() async throws {
        let runtime = try JavaScriptRuntime()
        let binding = try await runtime.function("readID") { (model: Model) in model.id }
        let initialReferences = await runtime.retainedReferenceCountForTesting

        for _ in 0..<100 {
            let result: Int = try await runtime.evaluate("readID({ id: 42 })")
            #expect(result == 42)
        }

        #expect(await runtime.retainedReferenceCountForTesting == initialReferences)
        #expect(await runtime.callbackDepthForTesting == 0)
        #expect(await binding.isActive)
    }

    @Test("settlement releases promise capabilities and active-call accounting")
    func settlementReleasesCapabilities() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.function("answer") { () async -> Int in 42 }

        let answer: Int = try await runtime.evaluate("answer()")

        #expect(answer == 42)
        #expect(await runtime.pendingPromiseCountForTesting == 0)
        #expect(await runtime.hostWaiterCountForTesting == 0)
    }

    @Test("canonical descriptions retain recursive type shapes without executable state")
    func descriptionsRetainTypeShapes() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.function("models") { (values: [Model?]) -> [String: Model] in
            Dictionary(uniqueKeysWithValues: values.compactMap { model in
                model.map { (String($0.id), $0) }
            })
        }

        let description = try #require(await runtime.bindingDescriptionsForTesting.first)
        guard case let .array(.optional(.codable(parameterName))) =
                description.parameters.first?.type,
              case let .dictionary(.codable(resultName)) = description.result else {
            Issue.record("The description did not retain recursive collection shapes.")
            return
        }
        #expect(parameterName.hasSuffix(".Model"))
        #expect(resultName.hasSuffix(".Model"))
    }

    @Test("explicit removal releases an exported actor root")
    func removalReleasesExportRoot() async throws {
        let runtime = try JavaScriptRuntime()
        var root: ExportRoot? = ExportRoot()
        let weakRoot = WeakBox(root)
        var optionalBinding: JavaScriptBinding?
        do {
            let retainedRoot = try #require(root)
            optionalBinding = try await runtime.export(retainedRoot, as: "root") { root, export in
                export.function("value") { () async in await root.value() }
            }
        }
        let binding = try #require(optionalBinding)
        root = nil

        #expect(weakRoot.value != nil)
        try await binding.remove()
        await Task.yield()
        #expect(weakRoot.value == nil)
    }

    @Test("explicit removal releases a captured actor")
    func removalReleasesCapturedActor() async throws {
        let runtime = try JavaScriptRuntime()
        var capture: ExportRoot? = ExportRoot()
        let weakCapture = WeakBox(capture)
        var optionalBinding: JavaScriptBinding?
        do {
            let retainedCapture = try #require(capture)
            optionalBinding = try await runtime.function("capturedValue") {
                await retainedCapture.value()
            }
        }
        let binding = try #require(optionalBinding)
        capture = nil

        #expect(weakCapture.value != nil)
        try await binding.remove()
        await Task.yield()
        #expect(weakCapture.value == nil)
    }

    @Test("binding descriptions use canonical global object and module locations")
    func descriptionsUseCanonicalLocations() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.function("globalFunction") { () -> Int in 1 }
        let root = ExportRoot()
        _ = try await runtime.export(root, as: "root") { _, export in
            export.function("objectFunction") { () -> Int in 2 }
        }
        try await runtime.defineModule("swift:metadata") { module in
            module.function("moduleFunction") { () -> Int in 3 }
        }

        let descriptions = await runtime.bindingDescriptionsForTesting
        let locations = Dictionary(uniqueKeysWithValues: descriptions.map {
            ($0.name, $0.location)
        })

        #expect(locations["globalFunction"] == .global)
        #expect(locations["objectFunction"] == .objectExport(name: "root"))
        #expect(locations["moduleFunction"] == .module(specifier: "swift:metadata"))
    }

    @Test("an outer engine entry refreshes the stack and checkpoints once")
    func outerEntryHasOnePreparationAndCheckpoint() async throws {
        let runtime = try JavaScriptRuntime()
        let initialRefreshes = await runtime.stackTopRefreshCountForTesting
        let initialCheckpoints = await runtime.checkpointCountForTesting

        _ = try await runtime.evaluate("42")

        #expect(await runtime.stackTopRefreshCountForTesting == initialRefreshes + 1)
        #expect(await runtime.checkpointCountForTesting == initialCheckpoints + 1)
    }

    @Test("a typed root read owns one engine entry and checkpoint")
    func typedRootReadHasOneEntryAndCheckpoint() async throws {
        let runtime = try JavaScriptRuntime()
        let initialRefreshes = await runtime.stackTopRefreshCountForTesting
        let initialCheckpoints = await runtime.checkpointCountForTesting

        let answer: Int = try await runtime.evaluate("Promise.resolve(42)")

        #expect(answer == 42)
        #expect(await runtime.stackTopRefreshCountForTesting == initialRefreshes + 1)
        #expect(await runtime.checkpointCountForTesting == initialCheckpoints + 1)
    }

    @Test("one reusable async definition installs into independent runtimes")
    func reusableDefinitionInstallsIntoIndependentRuntimes() async throws {
        var builder = JavaScriptExportBuilder()
        builder.function("increment") { (value: Int) async -> Int in
            await Task.yield()
            return value + 1
        }
        let definition = try #require(builder.members.first)
        let first = try JavaScriptRuntime()
        let second = try JavaScriptRuntime()

        _ = try await first.registerGlobalFunction(definition)
        _ = try await second.registerGlobalFunction(definition)

        async let firstResult: Int = first.evaluate("increment(20)")
        async let secondResult: Int = second.evaluate("increment(41)")
        #expect(try await [firstResult, secondResult] == [21, 42])

        let firstDescription = try #require(await first.bindingDescriptionsForTesting.first)
        let secondDescription = try #require(await second.bindingDescriptionsForTesting.first)
        #expect(firstDescription == secondDescription)
    }

    @Test("removing one reusable binding instance leaves another runtime independent")
    func reusableDefinitionInstancesHaveIndependentLifecycles() async throws {
        let gate = MultiRuntimeGate(expectedEntrants: 2)
        var builder = JavaScriptExportBuilder()
        builder.function("increment") { (value: Int) async -> Int in
            await gate.wait()
            return value + 1
        }
        let definition = try #require(builder.members.first)
        let first = try JavaScriptRuntime()
        let second = try JavaScriptRuntime()
        let firstBinding = try await first.registerGlobalFunction(definition)
        _ = try await second.registerGlobalFunction(definition)
        let firstResult = Task { try await first.evaluate("increment(20)", as: Int.self) }
        let secondResult = Task { try await second.evaluate("increment(41)", as: Int.self) }
        await gate.waitUntilReady()

        try await firstBinding.remove(cancellingInFlight: true)

        await #expect(throws: JavaScriptError.self) { _ = try await firstResult.value }
        await gate.open()
        #expect(try await secondResult.value == 42)
    }

    @Test("binding descriptions preserve exact Swift closure effects")
    func descriptionsPreserveClosureEffects() async throws {
        let runtime = try JavaScriptRuntime()
        try await runtime.function("sync") { () -> Int in 1 }
        try await runtime.function("throwing") { () throws -> Int in 2 }
        try await runtime.function("async") { () async -> Int in 3 }
        try await runtime.function("asyncThrowing") { () async throws -> Int in 4 }

        let descriptions = await runtime.bindingDescriptionsForTesting
        let effects = Dictionary(uniqueKeysWithValues: descriptions.map {
            ($0.name, $0.effects)
        })
        #expect(effects["sync"] == .init(isAsync: false, isThrowing: false))
        #expect(effects["throwing"] == .init(isAsync: false, isThrowing: true))
        #expect(effects["async"] == .init(isAsync: true, isThrowing: false))
        #expect(effects["asyncThrowing"] == .init(isAsync: true, isThrowing: true))
    }

    private struct Model: Codable, Sendable {
        let id: Int
    }

    private actor ExportRoot {
        func value() -> Int { 42 }
    }

    private actor MultiRuntimeGate {
        private let expectedEntrants: Int
        private var entrantCount = 0
        private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
        private var readinessContinuations: [CheckedContinuation<Void, Never>] = []

        init(expectedEntrants: Int) {
            self.expectedEntrants = expectedEntrants
        }

        func wait() async {
            entrantCount += 1
            if entrantCount == expectedEntrants {
                for continuation in readinessContinuations { continuation.resume() }
                readinessContinuations.removeAll()
            }
            await withCheckedContinuation { releaseContinuations.append($0) }
        }

        func waitUntilReady() async {
            guard entrantCount < expectedEntrants else { return }
            await withCheckedContinuation { readinessContinuations.append($0) }
        }

        func open() {
            for continuation in releaseContinuations { continuation.resume() }
            releaseContinuations.removeAll()
        }
    }

    private final class WeakBox<Value: AnyObject> {
        weak var value: Value?

        init(_ value: Value?) {
            self.value = value
        }
    }
}
