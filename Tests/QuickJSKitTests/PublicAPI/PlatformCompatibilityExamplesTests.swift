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
}
