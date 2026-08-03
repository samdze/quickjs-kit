import Foundation
import QuickJSKit
import QuickJSKitMacros

@JavaScriptExport
private struct SmokeUser: Codable, Sendable {
    let id: Int
}

@main
private struct PlatformSmoke {
    static func main() async throws {
        do {
            try await run()
        } catch {
            write("QuickJSKit platform smoke failed.")
            if let error = error as? JavaScriptError {
                write("kind: \(error.kind.rawValue)")
                write("name: \(error.name ?? "<none>")")
                write("message: \(error.message)")
                write("sourceURL: \(error.sourceURL ?? "<none>")")
                write("stack:\n\(error.stack ?? "<none>")")
            } else {
                write(String(reflecting: error))
            }
            throw error
        }
    }

    private static func run() async throws {
        write("stage: create-runtime")
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

        write("stage: raw-evaluation")
        let raw = try await runtime.evaluate("20 + 22")
        guard raw.numberValue == 42 else { throw SmokeFailure.rawEvaluation }

        write("stage: typed-struct-type")
        let typeName: String = try await runtime.evaluate("typeof SmokeUser")
        guard typeName == "function" else { throw SmokeFailure.typedType }

        write("stage: typed-struct-construction")
        let user: SmokeUser = try await runtime.evaluate(
            "new SmokeUser({ id: 42 })"
        )
        guard user.id == 42 else { throw SmokeFailure.typedEvaluation }

        write("stage: promise-evaluation")
        let promised: Int = try await runtime.evaluate("asyncAnswer()")
        guard promised == 42 else { throw SmokeFailure.promise }

        write("stage: module-import")
        let module = try await runtime.importModule("smoke:module")

        write("stage: module-export-decoding")
        let exported: Int = try await module.value(forExport: "answer")
        guard exported == 42 else { throw SmokeFailure.module }

        write("QuickJSKit platform smoke passed")
    }

    private static func write(_ message: String) {
        let output = Data((message + "\n").utf8)
        FileHandle.standardError.write(output)
    }
}

private enum SmokeFailure: Error {
    case rawEvaluation
    case typedType
    case typedEvaluation
    case promise
    case module
}
