import Testing
@testable import QuickJSKit

@Suite("Live-value registry invariants")
struct RegistryLifetimeTests {
    @Test("the same object receives canonical identity")
    func canonicalIdentity() async throws {
        let runtime = try JavaScriptRuntime()
        _ = try await runtime.evaluate("globalThis.shared = {}")

        let first = try await runtime.evaluate("shared")
        let second = try await runtime.evaluate("shared")

        #expect(first == second)
        #expect(Set([first, second]).count == 1)
    }

    @Test("dropping handles releases registry entries on the actor")
    func droppingHandlesReleasesReferences() async throws {
        let runtime = try JavaScriptRuntime()
        var value: JavaScriptValue? = try await runtime.evaluate("({ answer: 42 })")
        #expect(await runtime.retainedReferenceCountForTesting == 1)

        value = nil
        _ = value
        for _ in 0..<100 where await runtime.retainedReferenceCountForTesting != 0 {
            await Task.yield()
        }

        #expect(await runtime.retainedReferenceCountForTesting == 0)
    }
}
