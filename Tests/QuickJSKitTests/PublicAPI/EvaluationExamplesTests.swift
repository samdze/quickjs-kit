import Testing
import QuickJSKit

@Suite("Type-safe evaluation examples")
struct EvaluationExamplesTests {
    struct User: Codable, Sendable, Equatable {
        let id: Int
        let name: String
        let roles: [String]
    }

    @Test("evaluate infers and decodes a Swift model")
    func evaluateInfersModel() async throws {
        let runtime = try JavaScriptRuntime()

        let user: User = try await runtime.evaluate("""
            ({ id: 42, name: "Ada", roles: ["admin", "author"] })
            """)

        #expect(user == User(id: 42, name: "Ada", roles: ["admin", "author"]))
    }

    @Test("evaluate accepts an explicit result type")
    func evaluateUsesExplicitType() async throws {
        let runtime = try JavaScriptRuntime()

        let user = try await runtime.evaluate(
            "({ id: 7, name: 'Grace', roles: ['reviewer'] })",
            as: User.self,
            sourceURL: "user.js"
        )

        #expect(user.name == "Grace")
        #expect(user.roles == ["reviewer"])
    }

    @Test("untyped evaluate returns live values")
    func untypedEvaluateReturnsLiveValues() async throws {
        let runtime = try JavaScriptRuntime()

        let value = try await runtime.evaluate("({ answer: 42 })")
        let object = try #require(value.objectValue)

        #expect(value.isObject)
        #expect(try await object.value(forProperty: "answer", as: Int.self) == 42)
    }
}
