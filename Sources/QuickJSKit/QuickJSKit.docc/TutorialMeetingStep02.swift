import QuickJSKit

struct FollowUpTask: Codable, Sendable {
    let title: String
}

struct FollowUpPlan: Codable, Sendable {
    let title: String
    let ownerID: String?
    let tasks: [FollowUpTask]
}

let runtime = try JavaScriptRuntime()
// The expression returns JavaScript data that matches FollowUpPlan exactly.
let preview: FollowUpPlan = try await runtime.evaluate(
    """
    ({
        title: "Follow up: Team sync",
        ownerID: null,
        tasks: [{ title: "Send the summary" }]
    })
    """
)
print(preview.title)
