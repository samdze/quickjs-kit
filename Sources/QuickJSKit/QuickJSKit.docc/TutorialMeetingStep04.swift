import QuickJSKit

struct ProjectLead: Codable, Sendable {
    let id: String
    let name: String
}

actor ProjectDirectory {
    func projectLead(for project: String) -> ProjectLead? {
        project == "Mobile" ? ProjectLead(id: "ava", name: "Ava") : nil
    }
}

let runtime = try JavaScriptRuntime()
let directory = ProjectDirectory()
// An async Swift binding settles as a native JavaScript Promise.
try await runtime.function(
    "projectLead",
    options: .init(parameterNames: ["project"])
) { (project: String) async -> ProjectLead? in
    await directory.projectLead(for: project)
}
