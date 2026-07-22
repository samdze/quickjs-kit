@_exported import QuickJSKit

/// Generates the canonical JavaScript representation of a Swift declaration.
///
/// Structs and raw enums become Codable value types. Final classes and actors
/// become live Swift host types. Runtime publication remains explicit through
/// `JavaScriptType`.
@attached(
    member,
    names: named(javaScriptExportDocumentation),
    named(javaScriptExportSourceLocation),
    named(javaScriptHostTypeName),
    named(javaScriptHostTypeScope),
    named(javaScriptExportDefinition),
    named(javaScriptValueTypeDefinition),
    named(javaScriptHostTypeDefinition)
)
@attached(
    extension,
    conformances: TypeScriptSchemaProviding,
    JavaScriptValueTypeProviding,
    JavaScriptExportProviding,
    JavaScriptHostTypeProviding,
    names: named(typeScriptSchema), named(typeScriptSchemaDependencies)
)
public macro JavaScriptExport(scope: TypeScriptDeclarationScope? = nil) =
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
