import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct JavaScriptExportMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let export = try ExportSyntaxAnalyzer.analyze(
            attribute: node,
            declaration: declaration,
            context: context
        )
        switch export.kind {
        case .structure:
            return valueTypeMembers(export, kindExpression: ".structure")
        case let .enumeration(cases):
            let values = cases.map(enumCaseExpression).joined(separator: ", ")
            return valueTypeMembers(
                export,
                kindExpression: ".enumeration(cases: [\(values)])"
            )
        case let .host(host):
            return hostTypeMembers(export, host: host)
        }
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let export: ParsedExport
        do {
            export = try ExportSyntaxAnalyzer.analyze(
                attribute: node,
                declaration: declaration,
                context: context
            )
        } catch is DiagnosticsError {
            // The member role owns user-facing validation diagnostics. Returning
            // no conformance here prevents the attached roles from reporting the
            // same syntax error twice.
            return []
        }
        switch export.kind {
        case .structure, .enumeration:
            return [
                try JavaScriptValueSchemaMacro.expansion(
                    export: export,
                    type: type
                ),
                try ExtensionDeclSyntax(
                    "extension \(type.trimmed): JavaScriptValueTypeProviding {}"
                ),
            ]
        case .host:
            return [
                try ExtensionDeclSyntax(
                    "extension \(type.trimmed): JavaScriptExportProviding, JavaScriptHostTypeProviding {}"
                ),
            ]
        }
    }

    private static func valueTypeMembers(
        _ export: ParsedExport,
        kindExpression: String
    ) -> [DeclSyntax] {
        [
            DeclSyntax(stringLiteral: """
            public static let javaScriptValueTypeDefinition = JavaScriptValueTypeDefinition<Self>(
                name: \(swiftLiteral(export.javaScriptName)),
                documentation: \(export.documentationExpression),
                sourceLocation: \(export.sourceLocationExpression),
                kind: \(kindExpression)
            )
            """),
        ]
    }

    private static func hostTypeMembers(
        _ export: ParsedExport,
        host: ParsedExport.Host
    ) -> [DeclSyntax] {
        let body = host.instanceMembers
            .map { "            \($0)" }
            .joined(separator: "\n")
        let constructors = host.constructors.joined(separator: ",\n                ")
        let staticBody = host.staticMembers
            .map { "            \($0)" }
            .joined(separator: "\n")
        return [
            DeclSyntax(stringLiteral: "public static let javaScriptHostTypeName = \(swiftLiteral(export.javaScriptName))"),
            DeclSyntax(stringLiteral: "public static let javaScriptExportDocumentation: TypeScriptDocumentation? = \(export.documentationExpression)"),
            DeclSyntax(stringLiteral: "public static let javaScriptExportSourceLocation: TypeScriptSourceLocation? = \(export.sourceLocationExpression)"),
            DeclSyntax(stringLiteral: """
            public static let javaScriptExportDefinition = JavaScriptRuntimeTemplate.InstanceExport<\(export.swiftName)> {
            \(body)
            }
            """),
            DeclSyntax(stringLiteral: """
            public static let javaScriptHostTypeDefinition = JavaScriptHostTypeDefinition<\(export.swiftName)>(
                name: javaScriptHostTypeName,
                documentation: javaScriptExportDocumentation,
                sourceLocation: javaScriptExportSourceLocation,
                instanceMembers: javaScriptExportDefinition,
                constructors: [
                    \(constructors)
                ]
            ) {
            \(staticBody)
            }
            """),
        ]
    }

    static func enumCaseExpression(_ value: ParsedExport.EnumCase) -> String {
        ".init(\(swiftLiteral(value.name)), value: \(value.literalExpression), documentation: \(value.documentationExpression), sourceLocation: \(value.sourceLocationExpression))"
    }
}

public struct MarkerMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}
