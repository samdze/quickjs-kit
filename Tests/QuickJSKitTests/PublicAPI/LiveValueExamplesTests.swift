import Testing
import QuickJSKit

@Suite("Live JavaScript value examples")
struct LiveValueExamplesTests {
    struct Settings: Codable, Sendable, Equatable {
        let theme: String
        let retries: Int
    }

    @Test("the global object stores and decodes Swift values")
    func globalObjectRoundTripsModel() async throws {
        let runtime = try JavaScriptRuntime()
        let settings = Settings(theme: "dark", retries: 3)

        try await runtime.global.set(settings, forProperty: "settings")
        let decoded: Settings = try await runtime.global.value(
            forProperty: "settings"
        )

        #expect(decoded == settings)
        #expect(try await runtime.global.hasProperty("settings"))
        #expect(try await runtime.global.deleteProperty("settings"))
    }

    @Test("arrays support indexed reads writes and append")
    func arraysAreMutableThroughTheirHandle() async throws {
        let runtime = try JavaScriptRuntime()
        let value = try await runtime.evaluate("[1, , 3]")
        let array = try #require(value.arrayValue)

        #expect(try await array.count == 3)
        #expect(try await array.value(at: 1).isUndefined)

        try await array.set(2, at: 1)
        try await array.append(4)

        #expect(try await array.value(at: 1, as: Int.self) == 2)
        #expect(try await array.count == 4)
    }

    @Test("functions accept heterogeneous typed arguments")
    func functionsDecodeTheirResult() async throws {
        let runtime = try JavaScriptRuntime()
        let value = try await runtime.evaluate("(count, label) => `${label}:${count + 1}`")
        let function = try #require(value.functionValue)

        let result: String = try await function.call(41, "answer")

        #expect(result == "answer:42")
    }

    @Test("functions support an explicit this receiver")
    func functionsUseExplicitReceiver() async throws {
        let runtime = try JavaScriptRuntime()
        let objectValue = try await runtime.evaluate("({ base: 40 })")
        let functionValue = try await runtime.evaluate("(function (value) { return this.base + value; })")
        let object = try #require(objectValue.objectValue)
        let function = try #require(functionValue.functionValue)

        let result = try await function.call(on: object, 2, as: Int.self)

        #expect(result == 42)
    }

    @Test("functions accept existing live JavaScript values")
    func functionsAcceptLiveArguments() async throws {
        let runtime = try JavaScriptRuntime()
        let object = try await runtime.evaluate("({ identity: 'shared' })")
        let function = try await runtime.evaluate("value => value")
        let callable = try #require(function.functionValue)

        let result = try await callable.call(arguments: [object])

        #expect(result == object)
    }

    @Test("property names include only own enumerable string properties")
    func propertyNamesAreDataOriented() async throws {
        let runtime = try JavaScriptRuntime()
        let value = try await runtime.evaluate("""
            (() => {
              const prototype = { inherited: true };
              const object = Object.create(prototype);
              object.visible = 1;
              Object.defineProperty(object, "hidden", { value: 2 });
              object[Symbol("ignored")] = 3;
              return object;
            })()
            """)
        let object = try #require(value.objectValue)

        #expect(try await object.propertyNames() == ["visible"])
    }
}
