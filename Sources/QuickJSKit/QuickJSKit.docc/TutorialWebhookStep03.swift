import QuickJSKit

func makeWebhookEnvironment() throws -> JavaScriptRuntimeTemplate {
    try JavaScriptRuntimeTemplate {
        RuntimeInstance(factory: { DeliveryAudit() }) {
            // The macro supplies every JavaScript-visible audit member.
            RuntimeObject(as: "audit")
        }
        SourceModule(
            workflowSource,
            as: "app:webhook-workflow",
            sourceURL: "WebhookEnvironment.workflowSource"
        )
    }
}
