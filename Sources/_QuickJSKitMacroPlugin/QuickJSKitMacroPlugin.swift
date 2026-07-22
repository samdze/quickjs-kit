import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct QuickJSKitMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        JavaScriptExportMacro.self,
        MarkerMacro.self,
    ]
}
