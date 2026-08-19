import Foundation
import QuickJSKit

// Replace the initial source with this policy-aware version.
let workflowSource = """
    export async function decide(event) {
        const { destinationFor } = await import("rules:acme");
        const decision = {
            destination: destinationFor(event),
            label: `${event.tenant}:${event.kind}`
        };
        await audit.record(decision);
        return decision;
    }
    """

// Replace makeWebhookEnvironment() with this complete factory.
func makeWebhookEnvironment(
    rulesURL: URL,
    configuration: JavaScriptRuntime.Configuration = .init()
) throws -> JavaScriptRuntimeTemplate {
    let loader = makeTenantRuleLoader(rulesURL: rulesURL)
    return try JavaScriptRuntimeTemplate(configuration: configuration) {
        RuntimeInstance(factory: { DeliveryAudit() }) {
            RuntimeObject(as: "audit")
        }
        ModuleLoader(loader)
        SourceModule(
            workflowSource,
            as: "app:webhook-workflow",
            sourceURL: "WebhookEnvironment.workflowSource",
            declarations: .init(
                "export function decide(event: { tenant: string; kind: string }): Promise<{ destination: string; label: string }>;"
            )
        )
    }
}

// Load the host-selected rule before JavaScript evaluates dynamic import().
func loadSelectedRule(in runtime: JavaScriptRuntime) async throws {
    _ = try await runtime.importModule("rules:acme")
}
