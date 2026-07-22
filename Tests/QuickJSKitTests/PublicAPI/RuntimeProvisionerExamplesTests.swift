import QuickJSKit
import Testing

@Suite("Prewarmed runtime provisioning examples")
struct RuntimeProvisionerExamplesTests {
    @Test("a provisioner transfers ready independent runtimes and replenishes capacity")
    func provisionerTransfersIndependentRuntimes() async throws {
        let template = try JavaScriptRuntimeTemplate {
            Globals {
                Value("ready", as: "state")
            }
        }
        let provisioner = try JavaScriptRuntimeProvisioner(
            template: template,
            warmCapacity: 2
        )

        try await provisioner.warmUp()
        let initial = await provisioner.status
        #expect(initial.readyCount == 2)
        #expect(initial.provisioningCount == 0)

        let first = try await provisioner.makeRuntime()
        let second = try await provisioner.makeRuntime()
        try await first.global.set("first", forProperty: "identity")
        let secondHasIdentity = try await second.global.hasProperty("identity")

        try await provisioner.warmUp()
        let replenished = await provisioner.status
        #expect(replenished.readyCount == 2)
        #expect(!secondHasIdentity)

        await provisioner.shutdown()
        let final = await provisioner.status
        let state: String = try await first.evaluate("state")
        #expect(final.isShutdown)
        #expect(final.readyCount == 0)
        #expect(state == "ready")
    }

    @Test("provisioner capacity and creation concurrency must be positive")
    func provisionerValidatesCapacity() throws {
        let template = try JavaScriptRuntimeTemplate {}

        #expect(throws: JavaScriptError.self) {
            _ = try JavaScriptRuntimeProvisioner(
                template: template,
                warmCapacity: 0
            )
        }
        #expect(throws: JavaScriptError.self) {
            _ = try JavaScriptRuntimeProvisioner(
                template: template,
                warmCapacity: 1,
                maximumConcurrentCreations: 0
            )
        }
    }
}
