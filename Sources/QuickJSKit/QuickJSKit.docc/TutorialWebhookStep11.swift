import Foundation
import QuickJSKit

func startServer(environment: JavaScriptRuntimeTemplate) async throws {
    let provisioner = try JavaScriptRuntimeProvisioner(
        template: environment,
        warmCapacity: 2
    )
    try await provisioner.warmUp()
    defer { Task { await provisioner.shutdown() } }

    // Each runtime is transferred to one request handler.
    _ = try await provisioner.makeRuntime()
}
