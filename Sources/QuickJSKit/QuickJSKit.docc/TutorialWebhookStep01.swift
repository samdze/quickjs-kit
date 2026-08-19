import QuickJSKit
import QuickJSKitMacros

struct WebhookEvent: Codable, Sendable {
    let tenant: String
    let kind: String
}

@JavaScriptExport
struct DeliveryDecision: Codable, Sendable {
    let destination: String
    let label: String
}

@JavaScriptExport
actor DeliveryAudit {
    /// Records the decision that Swift will deliver.
    func record(_ decision: DeliveryDecision) -> String {
        "Recorded \(decision.destination)"
    }
}
