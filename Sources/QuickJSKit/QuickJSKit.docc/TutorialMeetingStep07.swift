import QuickJSKit
import QuickJSKitMacros

@JavaScriptExport
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
// Only declarations in this module become recipe capabilities.
try await runtime.defineModule("host:workspace") { module in
    module.type(ProjectLead.self)
    module.function("projectLead", options: .init(parameterNames: ["project"])) {
        (project: String) async -> ProjectLead? in
        await directory.projectLead(for: project)
    }
}
