import QuickJSKit
import QuickJSKitMacros

@JavaScriptExport
private struct SmokeUser: Codable, Sendable {
    let id: Int
}

@main
private struct PlatformSmoke {
    static func main() async throws {
        let template = try JavaScriptRuntimeTemplate(
            configuration: .restricted
        ) {
            Globals {
                JavaScriptType(SmokeUser.self)
                Function("asyncAnswer") { () async -> Int in 42 }
            }
            SourceModule(
                "export const answer = 42;",
                as: "smoke:module"
            )
        }
        let runtime = try await template.makeRuntime()

        let raw = try await runtime.evaluate("20 + 22")
        guard raw.numberValue == 42 else { throw SmokeFailure.rawEvaluation }

        let user: SmokeUser = try await runtime.evaluate(
            "new SmokeUser({ id: 42 })"
        )
        guard user.id == 42 else { throw SmokeFailure.typedEvaluation }

        let promised: Int = try await runtime.evaluate("asyncAnswer()")
        guard promised == 42 else { throw SmokeFailure.promise }

        let module = try await runtime.importModule("smoke:module")
        let exported: Int = try await module.value(forExport: "answer")
        guard exported == 42 else { throw SmokeFailure.module }

        print("QuickJSKit platform smoke passed")
    }
}

private enum SmokeFailure: Error {
    case rawEvaluation
    case typedEvaluation
    case promise
    case module
}
