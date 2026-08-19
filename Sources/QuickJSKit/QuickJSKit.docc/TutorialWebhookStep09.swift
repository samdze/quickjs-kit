import QuickJSKit

func handleRequest(
    _ event: WebhookEvent,
    environment: JavaScriptRuntimeTemplate
) async throws -> DeliveryDecision {
    let request = Task { try await handle(event, environment: environment) }
    return try await withTaskCancellationHandler {
        try await request.value
    } onCancel: {
        // Cancellation reaches the task that owns the runtime call.
        request.cancel()
    }
}
