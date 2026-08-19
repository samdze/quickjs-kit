import Foundation
import QuickJSKit

func makeServiceEnvironment(rulesURL: URL) throws -> JavaScriptRuntimeTemplate {
    try makeWebhookEnvironment(
        rulesURL: rulesURL,
        configuration: .restricted
    )
}

func handle(
    _ event: WebhookEvent,
    environment: JavaScriptRuntimeTemplate
) async throws -> DeliveryDecision {
    let runtime = try await environment.makeRuntime()
    try await loadSelectedRule(in: runtime)
    let workflow = try await runtime.importModule("app:webhook-workflow")
    let decide = try await workflow.function(forExport: "decide")

    do {
        // The deadline applies to this one JavaScript invocation.
        return try await decide.call(
            event,
            options: .init(timeout: .after(.milliseconds(100)))
        )
    } catch let error as JavaScriptError {
        print("Tenant workflow \(error.kind): \(error.message)")
        throw error
    }
}
