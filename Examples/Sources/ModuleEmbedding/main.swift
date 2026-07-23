import QuickJSKit

@main
private struct ModuleEmbeddingExample {
    static func main() async throws {
        let runtime = try JavaScriptRuntime(
            configuration: .restricted
        )
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
        print(answer)
    }
}
