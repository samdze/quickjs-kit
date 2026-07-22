@_exported import QuickJSKit

/// Generates a reusable JavaScript export definition for an actor or final class.
@attached(member, names: named(javaScriptExportDocumentation), named(javaScriptExportSourceLocation), named(javaScriptExportDefinition))
@attached(extension, conformances: JavaScriptExportProviding)
public macro JavaScriptExport() =
    #externalMacro(module: "_QuickJSKitMacroPlugin", type: "JavaScriptExportMacro")

/// Excludes one otherwise eligible member from `@JavaScriptExport`.
@attached(peer)
public macro JavaScriptIgnore() =
    #externalMacro(module: "_QuickJSKitMacroPlugin", type: "MarkerMacro")

/// Overrides the JavaScript name generated for a member.
@attached(peer)
public macro JavaScriptName(_ name: String) =
    #externalMacro(module: "_QuickJSKitMacroPlugin", type: "MarkerMacro")

/// Forces a mutable Swift property to be exported without a JavaScript setter.
@attached(peer)
public macro JavaScriptReadOnly() =
    #externalMacro(module: "_QuickJSKitMacroPlugin", type: "MarkerMacro")

/// Synthesizes an explicit TypeScript schema for a Codable model.
@attached(extension, conformances: TypeScriptSchemaProviding, names: named(typeScriptSchema), named(typeScriptSchemaDependencies))
public macro TypeScriptModel(scope: TypeScriptDeclarationScope? = nil) =
    #externalMacro(module: "_QuickJSKitMacroPlugin", type: "TypeScriptModelMacro")
