import Foundation
import QuickJSKit
import QuickJSKitMacros

/// A user visible to application scripts.
@JavaScriptExport(scope: .namespace("Example.Models"))
private struct User: Codable, Sendable {
    /// The stable user identifier.
    let id: Int

    /// The user-facing name.
    let name: String
}

@main
private struct TypeScriptWorkspaceExample {
    static func main() async throws {
        let template = try JavaScriptRuntimeTemplate(
            configuration: .restricted
        ) {
            Globals {
                Function(
                    "loadUser",
                    options: .init(
                        parameterNames: ["id"],
                        documentation: .init(
                            summary: "Loads one user.",
                            parameters: ["id": "The stable user identifier."],
                            returns: "The matching user."
                        )
                    )
                ) { (_: Int) async -> User in
                    User(id: 42, name: "Ada")
                }
            }
        }

        let workspace = try template.environmentDescription()
            .typeScriptWorkspace()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickJSKitExampleWorkspace")
        try? FileManager.default.removeItem(at: directory)
        try workspace.write(to: directory)

        print(directory.path)
    }
}
