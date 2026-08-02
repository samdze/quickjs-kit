import Testing
import QuickJSKit

@Suite("Platform compatibility examples")
struct PlatformCompatibilityExamplesTests {
    @Test("the JavaScript concurrency intrinsics match the platform contract")
    func javaScriptConcurrencyIntrinsicsMatchThePlatformContract() async throws {
        let runtime = try JavaScriptRuntime()

        let atomicsType: String = try await runtime.evaluate("typeof Atomics")
        let sharedArrayBufferType: String = try await runtime.evaluate(
            "typeof SharedArrayBuffer"
        )

        #if os(Windows)
        #expect(atomicsType == "undefined")
        #else
        #expect(atomicsType == "object")
        #endif
        #expect(sharedArrayBufferType == "function")
    }

    @Test("the JavaScript clock and random source are available")
    func javaScriptClockAndRandomSourceAreAvailable() async throws {
        let runtime = try JavaScriptRuntime()

        let now: Double = try await runtime.evaluate("Date.now()")
        let random: Double = try await runtime.evaluate("Math.random()")

        #expect(now.isFinite)
        #expect(now > 0)
        #expect(random >= 0)
        #expect(random < 1)
    }
}
