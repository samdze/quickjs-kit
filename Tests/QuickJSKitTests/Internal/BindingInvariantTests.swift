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

    private struct Model: Codable, Sendable {
        let id: Int
    }

    private actor ExportRoot {
        func value() -> Int { 42 }
    }

    private final class WeakBox<Value: AnyObject> {
        weak var value: Value?

        init(_ value: Value?) {
            self.value = value
        }
    }
}
