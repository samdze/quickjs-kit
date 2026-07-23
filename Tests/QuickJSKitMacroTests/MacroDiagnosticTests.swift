import SwiftSyntaxMacrosGenericTestSupport
import Testing

@Suite("JavaScript export macro diagnostics")
struct MacroDiagnosticTests {
    @Test("unsupported declaration kinds fail at the declaration name")
    func unsupportedDeclaration() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            protocol Service {}
            """,
            expandedSource: "protocol Service {}",
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM001"),
                    message: "@JavaScriptExport supports structs, raw String or Int enums, final classes, and actors.",
                    line: 2,
                    column: 10,
                    highlights: ["Service"]
                ),
            ]
        )
    }

    @Test("a non-final class is rejected at its name")
    func nonFinalClass() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            class Service {}
            """,
            expandedSource: "class Service {}",
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM002"),
                    message: "@JavaScriptExport requires a class to be final.",
                    line: 2,
                    column: 7,
                    highlights: ["Service"]
                ),
            ]
        )
    }

    @Test("value models fail closed when Codable is customized")
    func customCodable() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            struct Model: Codable {
                func encode(to encoder: Encoder) throws {}
            }
            """,
            expandedSource: """
            struct Model: Codable {
                func encode(to encoder: Encoder) throws {}
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM004"),
                    message: "Cannot infer an honest JavaScript representation because 'encode(to:)' customizes Codable; provide handwritten TypeScriptSchemaProviding and JavaScriptValueTypeProviding conformances without @JavaScriptExport.",
                    line: 3,
                    column: 10,
                    highlights: ["encode"]
                ),
            ]
        )
    }

    @Test("value methods must be explicitly ignored")
    func valueMethod() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            struct Model: Codable {
                func reset() {}
            }
            """,
            expandedSource: """
            struct Model: Codable {
                func reset() {}
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM003"),
                    message: "Struct and enum methods are not live JavaScript members; add @JavaScriptIgnore or export a final class or actor.",
                    line: 3,
                    column: 10,
                    highlights: ["reset"]
                ),
            ]
        )
    }

    @Test("value model properties require explicit unambiguous storage")
    func valueProperties() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            struct Model: Codable {
                lazy var deferred: Int = 0
            }
            """,
            expandedSource: """
            struct Model: Codable {
                lazy var deferred: Int = 0
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM007"),
                    message: "Lazy property 'deferred' prevents reliable Codable schema inference; provide handwritten conformances.",
                    line: 3,
                    column: 5,
                    highlights: ["lazy var deferred: Int = 0"]
                ),
            ]
        )
    }

    @Test("property wrappers are not inferred as Codable storage")
    func propertyWrapper() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            struct Model: Codable {
                @Wrapped var value: Int
            }
            """,
            expandedSource: """
            struct Model: Codable {
                @Wrapped var value: Int
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM006"),
                    message: "Property wrapper on 'value' prevents reliable Codable schema inference; provide handwritten conformances.",
                    line: 3,
                    column: 5,
                    highlights: ["@Wrapped"]
                ),
            ]
        )
    }

    @Test("unsupported value types identify their type syntax")
    func unsupportedValueType() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            struct Model: Codable {
                let pair: (Int, Int)
            }
            """,
            expandedSource: """
            struct Model: Codable {
                let pair: (Int, Int)
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM008"),
                    message: "Type '(Int, Int)' cannot be represented by inferred JavaScript value schemas; provide a supported Codable type or handwritten conformances.",
                    line: 3,
                    column: 15,
                    highlights: ["(Int, Int)"]
                ),
            ]
        )
    }

    @Test("malformed CodingKeys are rejected")
    func malformedCodingKeys() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            struct Model: Codable {
                let value: Int
                enum CodingKeys: String, CodingKey {
                    case value = makeName()
                }
            }
            """,
            expandedSource: """
            struct Model: Codable {
                let value: Int
                enum CodingKeys: String, CodingKey {
                    case value = makeName()
                }
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM009"),
                    message: "CodingKeys cannot be inferred: raw values must be static string literals.",
                    line: 5,
                    column: 22,
                    highlights: ["makeName()"]
                ),
            ]
        )
    }

    @Test("CodingKeys requires the canonical synthesized Codable shape")
    func codingKeysInheritance() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            struct Model: Codable {
                let value: Int
                enum CodingKeys: CodingKey {
                    case value
                }
            }
            """,
            expandedSource: """
            struct Model: Codable {
                let value: Int
                enum CodingKeys: CodingKey {
                    case value
                }
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM009"),
                    message: "CodingKeys cannot be inferred: declare it as 'enum CodingKeys: String, CodingKey'.",
                    line: 4,
                    column: 20,
                    highlights: [": CodingKey"]
                ),
            ]
        )
    }

    @Test("enum representations and cases are validated once")
    func enumRepresentation() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            enum State: String, Codable {
                case value(Int)
            }
            """,
            expandedSource: """
            enum State: String, Codable {
                case value(Int)
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM011"),
                    message: "Enum case 'value' has associated values and is not runtime-publishable.",
                    line: 3,
                    column: 10,
                    highlights: ["value(Int)"]
                ),
            ]
        )
    }

    @Test("enums require one supported raw type")
    func unsupportedEnumRawType() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            enum State: Double, Codable {
                case value = 1
            }
            """,
            expandedSource: """
            enum State: Double, Codable {
                case value = 1
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM010"),
                    message: "@JavaScriptExport enums require exactly one raw String or Int representation.",
                    line: 2,
                    column: 11,
                    highlights: [": Double, Codable"]
                ),
            ]
        )
    }

    @Test("integer enum raw values must fit Int64")
    func invalidIntegerEnumRawValue() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            enum State: Int, Codable {
                case value = 18446744073709551615
            }
            """,
            expandedSource: """
            enum State: Int, Codable {
                case value = 18446744073709551615
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM012"),
                    message: "Raw value for enum case 'value' must be an integer literal within Int64, and an implicit value cannot follow Int64.max.",
                    line: 3,
                    column: 18,
                    highlights: ["18446744073709551615"]
                ),
            ]
        )
    }

    @Test("generic initializers are rejected at init")
    func genericInitializer() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                init<T>(value: T) {}
            }
            """,
            expandedSource: """
            final class Service {
                init<T>(value: T) {}
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM013"),
                    message: "Exported initializers cannot be generic.",
                    line: 3,
                    column: 5,
                    highlights: ["init"]
                ),
            ]
        )
    }

    @Test("failable initializers are rejected at the question mark")
    func failableInitializer() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                init?() { return nil }
            }
            """,
            expandedSource: """
            final class Service {
                init?() { return nil }
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM014"),
                    message: "Exported initializers cannot be failable.",
                    line: 3,
                    column: 9,
                    highlights: ["?"]
                ),
            ]
        )
    }

    @Test("initializers reject unsupported signatures at the parameter")
    func initializerParameter() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                init(value: Int = 0) {}
            }
            """,
            expandedSource: """
            final class Service {
                init(value: Int = 0) {}
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM015"),
                    message: "Initializer parameter 'value' uses an unsupported default, variadic, inout, autoclosure, ownership, or isolation feature.",
                    line: 3,
                    column: 10,
                    highlights: ["value: Int = 0"]
                ),
            ]
        )
    }

    @Test("generic methods fail at their exported name")
    func genericMethod() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                func load<T>(_ value: T) -> T { value }
            }
            """,
            expandedSource: """
            final class Service {
                func load<T>(_ value: T) -> T { value }
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM016"),
                    message: "Exported method 'load' cannot be generic.",
                    line: 3,
                    column: 10,
                    highlights: ["load"]
                ),
            ]
        )
    }

    @Test("method parameters reject unsupported features")
    func methodParameter() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                func load(value: Int = 0) {}
            }
            """,
            expandedSource: """
            final class Service {
                func load(value: Int = 0) {}
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM018"),
                    message: "Parameter 'value' of exported method 'load' uses an unsupported default, variadic, inout, autoclosure, ownership, or isolation feature.",
                    line: 3,
                    column: 15,
                    highlights: ["value: Int = 0"]
                ),
            ]
        )
    }

    @Test("operators require explicit exclusion")
    func operatorMethod() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class NumberBox {
                static func + (left: NumberBox, right: NumberBox) -> NumberBox { left }
            }
            """,
            expandedSource: """
            final class NumberBox {
                static func + (left: NumberBox, right: NumberBox) -> NumberBox { left }
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM017"),
                    message: "Operator '+' cannot be exported as a JavaScript method; add @JavaScriptIgnore.",
                    line: 3,
                    column: 17,
                    highlights: ["+"]
                ),
            ]
        )
    }

    @Test("host properties require explicit types")
    func hostPropertyType() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                var count = 0
            }
            """,
            expandedSource: """
            final class Service {
                var count = 0
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM005"),
                    message: "Property 'count' requires an explicit type for JavaScript export.",
                    line: 3,
                    column: 9,
                    highlights: ["count"]
                ),
            ]
        )
    }

    @Test("throwing getters must be methods")
    func throwingGetter() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                var value: Int {
                    get throws { 1 }
                }
            }
            """,
            expandedSource: """
            final class Service {
                var value: Int {
                    get throws { 1 }
                }
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM020"),
                    message: "Throwing getter 'value' cannot be a JavaScript property; expose it as a method.",
                    line: 4,
                    column: 9,
                    highlights: ["get throws { 1 }"]
                ),
            ]
        )
    }

    @Test("subscripts require explicit exclusion")
    func subscriptMember() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                subscript(index: Int) -> Int { index }
            }
            """,
            expandedSource: """
            final class Service {
                subscript(index: Int) -> Int { index }
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM019"),
                    message: "Property 'subscript' uses an accessor form that cannot be exported safely.",
                    line: 3,
                    column: 5,
                    highlights: ["subscript"]
                ),
            ]
        )
    }

    @Test("JavaScript names are validated at expansion time")
    func invalidName() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                @JavaScriptName("not-valid")
                func load() {}
            }
            """,
            expandedSource: """
            final class Service {
                func load() {}
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM021"),
                    message: "'not-valid' is not a valid JavaScript and TypeScript identifier.",
                    line: 4,
                    column: 10,
                    highlights: ["load"]
                ),
            ]
        )
    }

    @Test("duplicate names are scoped to one surface")
    func duplicateName() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                func load() {}
                @JavaScriptName("load")
                func fetch() {}
            }
            """,
            expandedSource: """
            final class Service {
                func load() {}
                func fetch() {}
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM022"),
                    message: "Duplicate JavaScript export name 'load' on the instance surface.",
                    line: 5,
                    column: 10,
                    highlights: ["fetch"]
                ),
            ]
        )
    }

    @Test("async constructor factories reserve the static create name")
    func createConflict() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            actor Service {
                init() async {}
                static func create() {}
            }
            """,
            expandedSource: """
            actor Service {
                init() async {}
                static func create() {}
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM023"),
                    message: "Static export name 'create' conflicts with the factory generated for an async initializer.",
                    line: 4,
                    column: 17,
                    highlights: ["create"]
                ),
            ]
        )
    }

    @Test("documentation parameter names must match the signature")
    func documentationParameter() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                /// Loads a value.
                /// - Parameter other: An unknown parameter.
                func load(value: Int) {}
            }
            """,
            expandedSource: """
            final class Service {
                /// Loads a value.
                /// - Parameter other: An unknown parameter.
                func load(value: Int) {}
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM025"),
                    message: "Documentation for exported member 'load' refers to unknown parameter 'other'.",
                    line: 5,
                    column: 5,
                    highlights: ["func load(value: Int) {}"]
                ),
            ]
        )
    }

    @Test("duplicate documentation parameters are deterministic")
    func duplicateDocumentationParameter() {
        assertQuickJSKitMacroExpansion(
            """
            @JavaScriptExport
            final class Service {
                /// Loads a value.
                /// - Parameter value: The value.
                /// - Parameter value: The same value again.
                func load(value: Int) {}
            }
            """,
            expandedSource: """
            final class Service {
                /// Loads a value.
                /// - Parameter value: The value.
                /// - Parameter value: The same value again.
                func load(value: Int) {}
            }
            """,
            diagnostics: [
                .init(
                    id: quickJSKitDiagnosticID("QJSM024"),
                    message: "Documentation for exported member 'load' describes parameter 'value' more than once.",
                    line: 6,
                    column: 5,
                    highlights: ["func load(value: Int) {}"]
                ),
            ]
        )
    }
}
