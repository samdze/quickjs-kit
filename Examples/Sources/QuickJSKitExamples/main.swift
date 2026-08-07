import Foundation
import QuickJSKit
import QuickJSKitMacros

private struct ExampleUser: Codable, Sendable {
    let id: Int
    let name: String
}

private actor ExampleUserStore {
    func name(for identifier: Int) -> String {
        identifier == 42 ? "Ada" : "Unknown"
    }
}

/// A user visible to application scripts.
@JavaScriptExport
private struct WorkspaceUser: Codable, Sendable {
    /// The stable user identifier.
    let id: Int

    /// The user-facing name.
    let name: String
}

@main
private struct QuickJSKitExamples {
    static func main() async throws {
        switch CommandLine.arguments.dropFirst().first {
        case nil, "all":
            try await typedEvaluation()
            try await asyncHostAPI()
            try await moduleEmbedding()
            try await runtimeTemplates()
            try await typeScriptWorkspace()
        case "evaluation":
            try await typedEvaluation()
        case "binding":
            try await asyncHostAPI()
        case "module":
            try await moduleEmbedding()
        case "template":
            try await runtimeTemplates()
        case "tooling":
            try await typeScriptWorkspace()
        default:
            print("Usage: QuickJSKitExamples [all|evaluation|binding|module|template|tooling]")
        }
    }

    private static func typedEvaluation() async throws {
        let runtime = try JavaScriptRuntime(configuration: .restricted)
        let user: ExampleUser = try await runtime.evaluate("""
            ({ id: 42, name: "Ada" })
            """)
        print("evaluation: \(user.id): \(user.name)")
    }

    private static func asyncHostAPI() async throws {
        let runtime = try JavaScriptRuntime(configuration: .restricted)
        let store = ExampleUserStore()
        try await runtime.function(
            "loadUserName",
            options: .init(parameterNames: ["id"])
        ) { identifier in
            await store.name(for: identifier)
        }
        let name: String = try await runtime.evaluate("loadUserName(42)")
        print("binding: \(name)")
    }

    private static func moduleEmbedding() async throws {
        let runtime = try JavaScriptRuntime(configuration: .restricted)
        try await runtime.defineModule("host:math") { module in
            module.function("sum") { (left: Int, right: Int) in
                left + right
            }
        }
        try await runtime.registerModule(
            """
            import { sum } from "host:math";
            export const answer = sum(20, 22);
            """,
            as: "app:main"
        )
        let module = try await runtime.importModule("app:main")
        let answer: Int = try await module.value(forExport: "answer")
        print("module: \(answer)")
    }

    private static func runtimeTemplates() async throws {
        let template = try JavaScriptRuntimeTemplate(configuration: .restricted) {
            Globals {
                Function("sum") { (left: Int, right: Int) in
                    left + right
                }
            }
            Prepare(JavaScriptProgram("sum(20, 22)"))
        }
        let provisioner = try JavaScriptRuntimeProvisioner(
            template: template,
            warmCapacity: 2
        )
        try await provisioner.warmUp()
        let runtime = try await provisioner.makeRuntime()
        let answer: Int = try await runtime.evaluate("sum(20, 22)")
        print("template: \(answer)")
        await provisioner.shutdown()
    }

    private static func typeScriptWorkspace() async throws {
        let template = try JavaScriptRuntimeTemplate(configuration: .restricted) {
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
                ) { (_: Int) async -> WorkspaceUser in
                    WorkspaceUser(id: 42, name: "Ada")
                }
            }
        }
        let workspace = try template.environmentDescription()
            .typeScriptWorkspace()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuickJSKitExampleWorkspace")
        try? FileManager.default.removeItem(at: directory)
        try workspace.write(to: directory)
        print("tooling: \(directory.path)")
    }
}
