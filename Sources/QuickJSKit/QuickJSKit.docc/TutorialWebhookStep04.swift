import QuickJSKit

func handleOnce(
    _ event: WebhookEvent,
    environment: JavaScriptRuntimeTemplate
) async throws -> DeliveryDecision {
    let runtime = try await environment.makeRuntime()
    let workflow = try await runtime.importModule("app:webhook-workflow")
    let decide = try await workflow.function(forExport: "decide")
    return try await decide.call(event)
}
