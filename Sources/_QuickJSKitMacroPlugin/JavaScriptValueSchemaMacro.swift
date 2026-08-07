import SwiftSyntax
import SwiftSyntaxBuilder

enum JavaScriptValueSchemaMacro {
    static func expansion(
        export: ParsedExport,
        type: some TypeSyntaxProtocol
    ) throws -> ExtensionDeclSyntax {
        switch export.kind {
        case let .structure(properties):
            return try structureExtension(
                export: export,
                properties: properties,
                type: type
            )
        case let .enumeration(cases):
            return try enumerationExtension(
                export: export,
                cases: cases,
                type: type
            )
        case .host:
            preconditionFailure("Host exports do not produce value schemas.")
        }
    }

    private static func structureExtension(
        export: ParsedExport,
        properties: [ParsedExport.ModelProperty],
        type: some TypeSyntaxProtocol
    ) throws -> ExtensionDeclSyntax {
        let propertySource = properties.map {
            ".init(\(swiftLiteral($0.name)), type: \($0.typeExpression), isOptional: \($0.isOptional), documentation: \($0.documentationExpression), defaultValue: \($0.defaultValueExpression), sourceLocation: \($0.sourceLocationExpression))"
        }.joined(separator: ",\n            ")
        let dependencies = Set(
            properties.flatMap(\.dependencies)
                .filter { $0 != export.swiftName }
        ).sorted().map { "\($0).self" }.joined(separator: ", ")
        return try ExtensionDeclSyntax("""
        extension \(type.trimmed): TypeScriptSchemaProviding {
            public static var typeScriptSchema: TypeScriptSchema {
                .interface(
                    \(literal: export.swiftName),
                    documentation: \(raw: export.documentationExpression),
                    sourceLocation: \(raw: export.sourceLocationExpression),
                    properties: [
                        \(raw: propertySource)
                    ]
                )
            }

            public static var typeScriptSchemaDependencies: [any TypeScriptSchemaProviding.Type] {
                [\(raw: dependencies)]
            }
        }
        """)
    }

    private static func enumerationExtension(
        export: ParsedExport,
        cases: [ParsedExport.EnumCase],
        type: some TypeSyntaxProtocol
    ) throws -> ExtensionDeclSyntax {
        let caseSource = cases.map(JavaScriptExportMacro.enumCaseExpression)
            .joined(separator: ",\n            ")
        return try ExtensionDeclSyntax("""
        extension \(type.trimmed): TypeScriptSchemaProviding {
            public static var typeScriptSchema: TypeScriptSchema {
                .enumeration(
                    \(literal: export.swiftName),
                    documentation: \(raw: export.documentationExpression),
                    sourceLocation: \(raw: export.sourceLocationExpression),
                    cases: [
                        \(raw: caseSource)
                    ]
                )
            }
        }
        """)
    }
}
