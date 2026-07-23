import QuickJSKit

private actor UserStore {
    func name(for identifier: Int) -> String {
        identifier == 42 ? "Ada" : "Unknown"
    }
}

@main
private struct AsyncHostAPIExample {
    static func main() async throws {
        let runtime = try JavaScriptRuntime(
            configuration: .restricted
        )
        let store = UserStore()
        try await runtime.function(
            "loadUserName",
            options: .init(parameterNames: ["id"])
        ) { identifier in
            await store.name(for: identifier)
        }

        let name: String = try await runtime.evaluate(
            "loadUserName(42)"
        )
        print(name)
    }
}
