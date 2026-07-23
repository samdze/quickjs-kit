import SwiftDiagnostics
import SwiftSyntax

enum QuickJSKitMacroDiagnostic: DiagnosticMessage {
    case unsupportedDeclaration
    case classMustBeFinal
    case valueMemberRequiresIgnore
    case customCodable(String)
    case propertyRequiresExplicitType(String)
    case propertyWrapper(String)
    case lazyProperty(String)
    case unsupportedValueType(String)
    case malformedCodingKeys(String)
    case unsupportedEnumRepresentation
    case associatedValueEnum(String)
    case invalidIntegerEnumValue(String)
    case genericInitializer
    case failableInitializer
    case unsupportedInitializerParameter(String)
    case genericMethod(String)
    case operatorMethod(String)
    case unsupportedMethodParameter(String, String)
    case unsupportedProperty(String)
    case throwingProperty(String)
    case invalidName(String)
    case duplicateName(String, String)
    case createConflict
    case duplicateDocumentationParameter(String, String)
    case unknownDocumentationParameter(String, String)

    var message: String {
        switch self {
        case .unsupportedDeclaration:
            return "@JavaScriptExport supports structs, raw String or Int enums, final classes, and actors."
        case .classMustBeFinal:
            return "@JavaScriptExport requires a class to be final."
        case .valueMemberRequiresIgnore:
            return "Struct and enum methods are not live JavaScript members; add @JavaScriptIgnore or export a final class or actor."
        case let .customCodable(member):
            return "Cannot infer an honest JavaScript representation because '\(member)' customizes Codable; provide handwritten TypeScriptSchemaProviding and JavaScriptValueTypeProviding conformances without @JavaScriptExport."
        case let .propertyRequiresExplicitType(name):
            return "Property '\(name)' requires an explicit type for JavaScript export."
        case let .propertyWrapper(name):
            return "Property wrapper on '\(name)' prevents reliable Codable schema inference; provide handwritten conformances."
        case let .lazyProperty(name):
            return "Lazy property '\(name)' prevents reliable Codable schema inference; provide handwritten conformances."
        case let .unsupportedValueType(type):
            return "Type '\(type)' cannot be represented by inferred JavaScript value schemas; provide a supported Codable type or handwritten conformances."
        case let .malformedCodingKeys(reason):
            return "CodingKeys cannot be inferred: \(reason)"
        case .unsupportedEnumRepresentation:
            return "@JavaScriptExport enums require exactly one raw String or Int representation."
        case let .associatedValueEnum(name):
            return "Enum case '\(name)' has associated values and is not runtime-publishable."
        case let .invalidIntegerEnumValue(name):
            return "Raw value for enum case '\(name)' must be an integer literal within Int64, and an implicit value cannot follow Int64.max."
        case .genericInitializer:
            return "Exported initializers cannot be generic."
        case .failableInitializer:
            return "Exported initializers cannot be failable."
        case let .unsupportedInitializerParameter(name):
            return "Initializer parameter '\(name)' uses an unsupported default, variadic, inout, autoclosure, ownership, or isolation feature."
        case let .genericMethod(name):
            return "Exported method '\(name)' cannot be generic."
        case let .operatorMethod(name):
            return "Operator '\(name)' cannot be exported as a JavaScript method; add @JavaScriptIgnore."
        case let .unsupportedMethodParameter(method, parameter):
            return "Parameter '\(parameter)' of exported method '\(method)' uses an unsupported default, variadic, inout, autoclosure, ownership, or isolation feature."
        case let .unsupportedProperty(name):
            return "Property '\(name)' uses an accessor form that cannot be exported safely."
        case let .throwingProperty(name):
            return "Throwing getter '\(name)' cannot be a JavaScript property; expose it as a method."
        case let .invalidName(name):
            return "'\(name)' is not a valid JavaScript and TypeScript identifier."
        case let .duplicateName(name, surface):
            return "Duplicate JavaScript export name '\(name)' on the \(surface) surface."
        case .createConflict:
            return "Static export name 'create' conflicts with the factory generated for an async initializer."
        case let .duplicateDocumentationParameter(member, parameter):
            return "Documentation for exported member '\(member)' describes parameter '\(parameter)' more than once."
        case let .unknownDocumentationParameter(member, parameter):
            return "Documentation for exported member '\(member)' refers to unknown parameter '\(parameter)'."
        }
    }

    var diagnosticID: MessageID {
        MessageID(domain: "QuickJSKitMacros", id: identifier)
    }

    var severity: DiagnosticSeverity { .error }

    private var identifier: String {
        switch self {
        case .unsupportedDeclaration: "QJSM001"
        case .classMustBeFinal: "QJSM002"
        case .valueMemberRequiresIgnore: "QJSM003"
        case .customCodable: "QJSM004"
        case .propertyRequiresExplicitType: "QJSM005"
        case .propertyWrapper: "QJSM006"
        case .lazyProperty: "QJSM007"
        case .unsupportedValueType: "QJSM008"
        case .malformedCodingKeys: "QJSM009"
        case .unsupportedEnumRepresentation: "QJSM010"
        case .associatedValueEnum: "QJSM011"
        case .invalidIntegerEnumValue: "QJSM012"
        case .genericInitializer: "QJSM013"
        case .failableInitializer: "QJSM014"
        case .unsupportedInitializerParameter: "QJSM015"
        case .genericMethod: "QJSM016"
        case .operatorMethod: "QJSM017"
        case .unsupportedMethodParameter: "QJSM018"
        case .unsupportedProperty: "QJSM019"
        case .throwingProperty: "QJSM020"
        case .invalidName: "QJSM021"
        case .duplicateName: "QJSM022"
        case .createConflict: "QJSM023"
        case .duplicateDocumentationParameter: "QJSM024"
        case .unknownDocumentationParameter: "QJSM025"
        }
    }
}

func macroFailure(
    _ message: QuickJSKitMacroDiagnostic,
    at node: some SyntaxProtocol,
    highlights: [Syntax] = []
) -> DiagnosticsError {
    let diagnosticHighlights = highlights.isEmpty
        ? [Syntax(node)]
        : highlights
    return DiagnosticsError(
        diagnostics: [
            Diagnostic(
                node: Syntax(node),
                message: message,
                highlights: diagnosticHighlights
            ),
        ]
    )
}
