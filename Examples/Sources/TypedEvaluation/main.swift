import QuickJSKit

private struct User: Codable, Sendable {
    let id: Int
    let name: String
}

@main
private struct TypedEvaluationExample {
    static func main() async throws {
        let runtime = try JavaScriptRuntime(
            configuration: .restricted
        )
        let user: User = try await runtime.evaluate("""
            ({ id: 42, name: "Ada" })
            """)

        print("\(user.id): \(user.name)")
    }
}
