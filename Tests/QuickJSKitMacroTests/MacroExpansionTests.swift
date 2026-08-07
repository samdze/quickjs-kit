import Testing

@Suite("JavaScript export macro expansions")
struct MacroExpansionTests {
    @Test("a struct uses syntax-aware Codable schema analysis")
    func structureExpansion() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            struct User: Codable, Sendable {
                /// The identifier.
                let id: Int
                let aliases: Optional<Array<String>>
                let nickname: String?
                let tags: [String]
                let flags: Dictionary<String, Bool>
                private let metadata: [String: URL]
                let profile: Models.Profile

                enum CodingKeys: String, CodingKey {
                    case id
                    case aliases = "names"
                    case nickname
                    case tags
                    case flags
                    case metadata
                    case profile
                }
            }
            """,
            expandedSource: """
            struct User: Codable, Sendable {
                /// The identifier.
                let id: Int
                let aliases: Optional<Array<String>>
                let nickname: String?
                let tags: [String]
                let flags: Dictionary<String, Bool>
                private let metadata: [String: URL]
                let profile: Models.Profile

                enum CodingKeys: String, CodingKey {
                    case id
                    case aliases = "names"
                    case nickname
                    case tags
                    case flags
                    case metadata
                    case profile
                }

                public static let javaScriptValueTypeDefinition = JavaScriptValueTypeDefinition<Self>(
                    name: "User",
                    documentation: nil,
                    sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 1, column: 1),
                    kind: .structure
                )
            }

            extension User: TypeScriptSchemaProviding {
                public static var typeScriptSchema: TypeScriptSchema {
                    .interface(
                        "User",
                        documentation: nil,
                        sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 1, column: 1),
                        properties: [
                            .init("id", type: .union([.number, .bigint]), isOptional: false, documentation: .init(summary: "The identifier."), defaultValue: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 4, column: 9)),
                        .init("names", type: .union([.array(.string), .null]), isOptional: true, documentation: nil, defaultValue: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 5, column: 9)),
                        .init("nickname", type: .union([.string, .null]), isOptional: true, documentation: nil, defaultValue: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 6, column: 9)),
                        .init("tags", type: .array(.string), isOptional: false, documentation: nil, defaultValue: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 7, column: 9)),
                        .init("flags", type: .record(.boolean), isOptional: false, documentation: nil, defaultValue: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 8, column: 9)),
                        .init("metadata", type: .record(.string), isOptional: false, documentation: nil, defaultValue: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 9, column: 17)),
                        .init("profile", type: .named("Profile"), isOptional: false, documentation: nil, defaultValue: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 10, column: 9))
                        ]
                    )
                }

                public static var typeScriptSchemaDependencies: [any TypeScriptSchemaProviding.Type] {
                    [Models.Profile.self]
                }
            }

            extension User: JavaScriptValueTypeProviding {
            }
            """
        )
    }

    @Test("signed integer enum values share one expansion model")
    func enumerationExpansion() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            enum State: Int, Codable, Sendable {
                case negative = -1
                case zero
            }
            """,
            expandedSource: """
            enum State: Int, Codable, Sendable {
                case negative = -1
                case zero

                public static let javaScriptValueTypeDefinition = JavaScriptValueTypeDefinition<Self>(
                    name: "State",
                    documentation: nil,
                    sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 1, column: 1),
                    kind: .enumeration(cases: [.init("negative", value: .integer(-1), documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 3, column: 10)), .init("zero", value: .integer(0), documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 4, column: 10))])
                )
            }

            extension State: TypeScriptSchemaProviding {
                public static var typeScriptSchema: TypeScriptSchema {
                    .enumeration(
                        "State",
                        documentation: nil,
                        sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 1, column: 1),
                        cases: [
                            .init("negative", value: .integer(-1), documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 3, column: 10)),
                        .init("zero", value: .integer(0), documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 4, column: 10))
                        ]
                    )
                }
            }

            extension State: JavaScriptValueTypeProviding {
            }
            """
        )
    }

    @Test("a final class expands every supported function effect")
    func classExpansion() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service: Sendable {
                let version: String
                init(version: String) { self.version = version }
                static func count() -> Int { 1 }
                func sync(_ value: Int) -> Int { value }
                func throwing(_ value: Int) throws -> Int { value }
                func asynchronous(_ value: Int) async -> Int { value }
                func both(_ value: Int) async throws -> Int { value }
            }
            """,
            expandedSource: """
            final class Service: Sendable {
                let version: String
                init(version: String) { self.version = version }
                static func count() -> Int { 1 }
                func sync(_ value: Int) -> Int { value }
                func throwing(_ value: Int) throws -> Int { value }
                func asynchronous(_ value: Int) async -> Int { value }
                func both(_ value: Int) async throws -> Int { value }

                public static let javaScriptHostTypeName = "Service"

                public static let javaScriptExportDocumentation: TypeScriptDocumentation? = nil

                public static let javaScriptExportSourceLocation: TypeScriptSourceLocation? = .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 1, column: 1)

                public static let javaScriptExportDefinition = JavaScriptRuntimeTemplate.InstanceExport<Service> {
                            InstanceProperty<Service>("version", documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 3, column: 9), get: { (root: Service) -> String in
                                    root.version
                                })
                            InstanceFunction<Service>("sync", options: .init(parameterNames: ["value"], documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 6, column: 5), parameterSourceLocations: ["value": .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 6, column: 15)]), { (root: Service, value: Int) -> Int in
                                    root.sync(value)
                                })
                            InstanceFunction<Service>("throwing", options: .init(parameterNames: ["value"], documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 7, column: 5), parameterSourceLocations: ["value": .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 7, column: 19)]), { (root: Service, value: Int) throws -> Int in
                                    try root.throwing(value)
                                })
                            InstanceFunction<Service>("asynchronous", options: .init(parameterNames: ["value"], documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 8, column: 5), parameterSourceLocations: ["value": .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 8, column: 23)]), runtimeIsolated: { (_: isolated JavaScriptRuntime, root: Service, value: Int) async -> Int in
                                    await root.asynchronous(value)
                                })
                            InstanceFunction<Service>("both", options: .init(parameterNames: ["value"], documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 9, column: 5), parameterSourceLocations: ["value": .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 9, column: 15)]), runtimeIsolated: { (_: isolated JavaScriptRuntime, root: Service, value: Int) async throws -> Int in
                                    try await root.both(value)
                                })
                }

                public static let javaScriptHostTypeDefinition = JavaScriptHostTypeDefinition<Service>(
                    name: javaScriptHostTypeName,
                    documentation: javaScriptExportDocumentation,
                    sourceLocation: javaScriptExportSourceLocation,
                    instanceMembers: javaScriptExportDefinition,
                    constructors: [
                        JavaScriptHostConstructor<Service>(options: .init(parameterNames: ["version"], documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 4, column: 5), parameterSourceLocations: ["version": .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 4, column: 10)]), { (version: String) -> Service in
                                Service(version: version)
                            })
                    ]
                ) {
                            Function("count", options: .init(parameterNames: [], documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 5, column: 5), parameterSourceLocations: [:]), { () -> Int in
                                    Service.count()
                                })
                }
            }

            extension Service: JavaScriptExportProviding, JavaScriptHostTypeProviding {
            }
            """
        )
    }

    @Test("an actor expands isolated members as asynchronous bindings")
    func actorExpansion() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            actor Counter {
                let identifier: Int
                var count: Int
                init(identifier: Int, count: Int) {
                    self.identifier = identifier
                    self.count = count
                }
                func increment() -> Int {
                    count += 1
                    return count
                }
            }
            """,
            expandedSource: """
            actor Counter {
                let identifier: Int
                var count: Int
                init(identifier: Int, count: Int) {
                    self.identifier = identifier
                    self.count = count
                }
                func increment() -> Int {
                    count += 1
                    return count
                }

                public static let javaScriptHostTypeName = "Counter"

                public static let javaScriptExportDocumentation: TypeScriptDocumentation? = nil

                public static let javaScriptExportSourceLocation: TypeScriptSourceLocation? = .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 1, column: 1)

                public static let javaScriptExportDefinition = JavaScriptRuntimeTemplate.InstanceExport<Counter> {
                            InstanceProperty<Counter>("identifier", documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 3, column: 9), runtimeIsolatedGet: { (_: isolated JavaScriptRuntime, root: Counter) async -> Int in
                                    root.identifier
                                })
                            InstanceProperty<Counter>("count", documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 4, column: 9), runtimeIsolatedGet: { (_: isolated JavaScriptRuntime, root: Counter) async -> Int in
                                    await root.count
                                })
                            InstanceFunction<Counter>("increment", options: .init(parameterNames: [], documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 9, column: 5), parameterSourceLocations: [:]), runtimeIsolated: { (_: isolated JavaScriptRuntime, root: Counter) async -> Int in
                                    await root.increment()
                                })
                }

                public static let javaScriptHostTypeDefinition = JavaScriptHostTypeDefinition<Counter>(
                    name: javaScriptHostTypeName,
                    documentation: javaScriptExportDocumentation,
                    sourceLocation: javaScriptExportSourceLocation,
                    instanceMembers: javaScriptExportDefinition,
                    constructors: [
                        JavaScriptHostConstructor<Counter>(options: .init(parameterNames: ["identifier", "count"], documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 5, column: 5), parameterSourceLocations: ["identifier": .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 5, column: 10), "count": .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 5, column: 27)]), { (identifier: Int, count: Int) -> Counter in
                                Counter(identifier: identifier, count: count)
                            })
                    ]
                ) {

                }
            }

            extension Counter: JavaScriptExportProviding, JavaScriptHostTypeProviding {
            }
            """
        )
    }

    @Test("refinement attributes change only the canonical export model")
    func refinementAttributes() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Settings {
                @JavaScriptReadOnly
                var version: Int = 1
                @JavaScriptName("reload")
                func refresh() {}
                @JavaScriptIgnore
                func internalOnly() {}
            }
            """,
            expandedSource: """
            final class Settings {
                var version: Int = 1
                func refresh() {}
                func internalOnly() {}

                public static let javaScriptHostTypeName = "Settings"

                public static let javaScriptExportDocumentation: TypeScriptDocumentation? = nil

                public static let javaScriptExportSourceLocation: TypeScriptSourceLocation? = .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 1, column: 1)

                public static let javaScriptExportDefinition = JavaScriptRuntimeTemplate.InstanceExport<Settings> {
                            InstanceProperty<Settings>("version", documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 4, column: 9), get: { (root: Settings) -> Int in
                                    root.version
                                })
                            InstanceFunction<Settings>("reload", options: .init(parameterNames: [], documentation: nil, sourceLocation: .init(fileID: "MacroContractTests/MacroContractTests.swift", line: 5, column: 5), parameterSourceLocations: [:]), { (root: Settings) -> Void in
                                    root.refresh()
                                })
                }

                public static let javaScriptHostTypeDefinition = JavaScriptHostTypeDefinition<Settings>(
                    name: javaScriptHostTypeName,
                    documentation: javaScriptExportDocumentation,
                    sourceLocation: javaScriptExportSourceLocation,
                    instanceMembers: javaScriptExportDefinition,
                    constructors: [

                    ]
                ) {

                }
            }

            extension Settings: JavaScriptExportProviding, JavaScriptHostTypeProviding {
            }
            """
        )
    }
}
