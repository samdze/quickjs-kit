import Foundation
import QuickJSKit
import QuickJSKitMacros

@JavaScriptExport
struct ProjectLead: Codable, Sendable {
    let id: String
    let name: String
}

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

actor ProjectDirectory {
    func projectLead(for project: String) -> ProjectLead? {
        project == "Mobile" ? ProjectLead(id: "ava", name: "Ava") : nil
    }
}

func makeRuntime(scriptsURL: URL) async throws -> JavaScriptRuntime {
    let runtime = try JavaScriptRuntime()
    let directory = ProjectDirectory()
    try await runtime.defineModule("host:workspace") { module in
        module.type(ProjectLead.self)
        module.function("projectLead", options: .init(parameterNames: ["project"])) {
            (project: String) async -> ProjectLead? in
            await directory.projectLead(for: project)
        }
    }

    let recipeURL = scriptsURL.appendingPathComponent("follow-up.js")
    let recipeSource = try String(contentsOf: recipeURL, encoding: .utf8)
    // Use the actual file URL in diagnostics and generated editor metadata.
    try await runtime.registerModule(
        recipeSource,
        as: "app:follow-up",
        sourceURL: recipeURL.absoluteString,
        typeScriptDeclarations: .init(
            "export function plan(note: unknown): Promise<unknown>;"
        )
    )
    // Import now so a recipe syntax or dependency error fails during setup.
    _ = try await runtime.importModule("app:follow-up")
    return runtime
}

func runRecipeAndConfigureAuthoring(
    note: MeetingNote,
    scriptsURL: URL
) async throws {
    let runtime = try await makeRuntime(scriptsURL: scriptsURL)
    let recipe = try await runtime.importModule("app:follow-up")
    let makePlan = try await recipe.function(forExport: "plan")
    let plan: FollowUpPlan = try await makePlan.call(note)
    let declarations = try await runtime.environmentDescription()
        .typeScriptDeclarations()
    let workspace = try await runtime.environmentDescription().typeScriptWorkspace(
        options: .init(sourceGlobs: ["Scripts/**/*.js"])
    )
    try workspace.write(
        // Generated files are separate from the recipe source that authors edit.
        to: FileManager.default.temporaryDirectory
            .appendingPathComponent("FollowUpRecipeWorkspace")
    )
    print(plan)
    print(declarations)
}
