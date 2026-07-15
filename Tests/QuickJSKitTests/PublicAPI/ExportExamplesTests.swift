import Testing
import QuickJSKit

@Suite("Explicit Swift export examples")
struct ExportExamplesTests {
    actor Storage {
        private var values: [String: String] = ["language": "Swift"]

        func read(_ key: String) -> String? { values[key] }
        func write(_ key: String, value: String) { values[key] = value }
    }

    @Test("an actor exposes explicitly selected methods and snapshot values")
    func exportsActor() async throws {
        let runtime = try JavaScriptRuntime()
        let storage = Storage()

        let binding = try await runtime.export(storage, as: "storage") { storage, export in
            export.function(
                "read",
                options: .init(
                    parameterNames: ["key"],
                    documentation: "Reads a stored value."
                )
            ) { key async in
                await storage.read(key)
            }
            export.function(
                "write",
                options: .init(parameterNames: ["key", "value"])
            ) { key, value async in
                await storage.write(key, value: value)
            }
            export.value("1.0", as: "version", documentation: "API version.")
        }

        let value: String? = try await runtime.evaluate("storage.read('language')")
        #expect(value == "Swift")
        let version: String = try await runtime.evaluate("storage.version")
        #expect(version == "1.0")
        #expect(binding.value.isObject)
    }

    @Test("exported members have intentional property attributes")
    func exportedPropertyAttributes() async throws {
        let runtime = try JavaScriptRuntime()
        let storage = Storage()
        try await runtime.export(storage, as: "storage") { storage, export in
            export.function("read") { key async in await storage.read(key) }
            export.value("1.0", as: "version")
        }

        let attributes: [Bool] = try await runtime.evaluate("""
            [
              Object.getOwnPropertyDescriptor(storage, 'read').writable,
              Object.getOwnPropertyDescriptor(storage, 'read').enumerable,
              Object.getOwnPropertyDescriptor(storage, 'version').writable,
              Object.getOwnPropertyDescriptor(storage, 'version').enumerable
            ]
            """)
        #expect(attributes == [false, false, false, true])
    }

    @Test("a failed export leaves the global object unchanged")
    func exportIsTransactional() async throws {
        let runtime = try JavaScriptRuntime()
        let storage = Storage()

        await #expect(throws: JavaScriptError.self) {
            try await runtime.export(storage, as: "storage") { _, export in
                export.value(1, as: "duplicate")
                export.value(2, as: "duplicate")
            }
        }

        let absent: Bool = try await runtime.evaluate("typeof storage === 'undefined'")
        #expect(absent)
    }

    @Test("an export rejects live values from another runtime")
    func exportRejectsCrossRuntimeValues() async throws {
        let runtime = try JavaScriptRuntime()
        let otherRuntime = try JavaScriptRuntime()
        let foreignValue = try await otherRuntime.evaluate("({ id: 42 })")
        let storage = Storage()

        await #expect(throws: JavaScriptError.self) {
            try await runtime.export(storage, as: "storage") { _, export in
                export.value(foreignValue, as: "foreign")
            }
        }

        let absent: Bool = try await runtime.evaluate("typeof storage === 'undefined'")
        #expect(absent)
    }

    @Test("an encoding failure rolls back prepared export methods")
    func encodingFailureRollsBackMethods() async throws {
        struct ExpectedFailure: Error {}
        struct InvalidSnapshot: Encodable, Sendable {
            func encode(to encoder: any Encoder) throws { throw ExpectedFailure() }
        }

        let runtime = try JavaScriptRuntime()
        let storage = Storage()

        await #expect(throws: ExpectedFailure.self) {
            try await runtime.export(storage, as: "storage") { storage, export in
                export.function("read") { key async in await storage.read(key) }
                export.value(InvalidSnapshot(), as: "invalid")
            }
        }

        let absent: Bool = try await runtime.evaluate("typeof storage === 'undefined'")
        #expect(absent)
    }
}
