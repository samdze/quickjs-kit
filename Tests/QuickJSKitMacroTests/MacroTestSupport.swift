import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing
import _QuickJSKitMacroPlugin

let quickJSKitMacroSpecs: [String: MacroSpec] = [
    "JavaScriptExport": MacroSpec(
        type: JavaScriptExportMacro.self,
        conformances: [
            "TypeScriptSchemaProviding",
            "JavaScriptValueTypeProviding",
            "JavaScriptExportProviding",
            "JavaScriptHostTypeProviding",
        ]
    ),
    "JavaScriptIgnore": MacroSpec(type: MarkerMacro.self),
    "JavaScriptName": MacroSpec(type: MarkerMacro.self),
    "JavaScriptReadOnly": MacroSpec(type: MarkerMacro.self),
]

func assertQuickJSKitMacroExpansion(
    _ source: String,
    expandedSource: String,
    diagnostics: [DiagnosticSpec] = [],
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
) {
    assertMacroExpansion(
        source,
        expandedSource: expandedSource,
        diagnostics: diagnostics,
        macroSpecs: quickJSKitMacroSpecs,
        testModuleName: "MacroContractTests",
        testFileName: "MacroContractTests.swift",
        failureHandler: {
            Issue.record(
                Comment(rawValue: $0.message),
                sourceLocation: .init(
                    fileID: $0.location.fileID,
                    filePath: $0.location.filePath,
                    line: $0.location.line,
                    column: $0.location.column
                )
            )
        },
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
    )
}

func quickJSKitDiagnosticID(_ identifier: String) -> MessageID {
    MessageID(domain: "QuickJSKitMacros", id: identifier)
}
