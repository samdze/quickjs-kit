import QuickJSKit

struct MeetingNote: Codable, Sendable {
    let project: String
    let title: String
    let actionItems: [String]
}

struct ProjectLead: Codable, Sendable {
    let id: String
    let name: String
}

struct FollowUpTask: Codable, Sendable {
    let title: String
}

struct FollowUpPlan: Codable, Sendable {
    let title: String
    let ownerID: String?
    let tasks: [FollowUpTask]
}

actor ProjectDirectory {
    func projectLead(for project: String) -> ProjectLead? {
        project == "Mobile" ? ProjectLead(id: "ava", name: "Ava") : nil
    }
}

let recipeSource = """
    export async function plan(note) {
        const lead = await projectLead(note.project);
        return {
            title: `Follow up: ${note.title}`,
            ownerID: lead?.id ?? null,
            tasks: note.actionItems.map(title => ({ title }))
        };
    }
    """

let runtime = try JavaScriptRuntime()
let directory = ProjectDirectory()
// This async binding fulfills the Promise awaited by the recipe.
try await runtime.function("projectLead") { (project: String) async -> ProjectLead? in
    await directory.projectLead(for: project)
}
try await runtime.registerModule(recipeSource, as: "app:follow-up")
let recipe = try await runtime.importModule("app:follow-up")
let makePlan = try await recipe.function(forExport: "plan")
let plan: FollowUpPlan = try await makePlan.call(
    MeetingNote(project: "Mobile", title: "Ship the new editor", actionItems: [])
)
