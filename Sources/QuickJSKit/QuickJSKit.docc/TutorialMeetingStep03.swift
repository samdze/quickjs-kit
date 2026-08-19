import QuickJSKit

struct MeetingNote: Codable, Sendable {
    let project: String
    let title: String
    let actionItems: [String]
}

struct FollowUpTask: Codable, Sendable {
    let title: String
}

struct FollowUpPlan: Codable, Sendable {
    let title: String
    let ownerID: String?
    let tasks: [FollowUpTask]
}

let recipeSource = """
    export function plan(note) {
        return {
            title: `Follow up: ${note.title}`,
            ownerID: null,
            tasks: note.actionItems.map(title => ({ title }))
        };
    }
    """

let runtime = try JavaScriptRuntime()
try await runtime.registerModule(recipeSource, as: "app:follow-up")
let recipe = try await runtime.importModule("app:follow-up")
let makePlan = try await recipe.function(forExport: "plan")

// Calling a module export encodes the note and decodes a detached Swift plan.
let plan: FollowUpPlan = try await makePlan.call(
    MeetingNote(
        project: "Mobile",
        title: "Ship the new editor",
        actionItems: ["Confirm the rollout", "Write release notes"]
    )
)
