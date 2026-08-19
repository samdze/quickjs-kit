# Compile-Time Exports

Use the optional `QuickJSKitMacros` product to derive checked JavaScript and
TypeScript metadata from Swift declarations.

## Add the macro product

```swift
import QuickJSKit
import QuickJSKitMacros
```

Apply `@JavaScriptExport` to a supported value or host declaration:

```swift
@JavaScriptExport
struct User: Codable, Sendable {
    /// The stable user identifier.
    let id: Int

    /// The display name.
    let name: String
}
```

Annotation generates metadata and checked export definitions. It does not
publish anything to a runtime by itself.

## Publish explicitly

Choose the destination in the template or runtime:

```swift
let template = try JavaScriptRuntimeTemplate {
    SwiftModule("host:users") {
        JavaScriptType(User.self)
    }
}
```

The containing ``Globals`` or ``SwiftModule`` declaration owns the JavaScript
and TypeScript location. The same rule applies to immediate type registration.

## Supported declarations

Codable structs and raw `String` or `Int` enums become JavaScript value types.
Final classes and actors become live host types with runtime-local identity.
Use explicit annotations to rename members, omit members, or make accessors
read-only.

Stored properties and `CodingKeys` participate in value-schema inference.
Computed and static properties are excluded.

## Inference boundaries

The macro rejects declarations when it cannot describe the encoded shape
honestly. Custom `Codable` implementations, property wrappers, non-string
dictionary keys, tuples, function types, metatypes, and unsupported generic
containers require handwritten ``TypeScriptSchemaProviding`` and
``JavaScriptValueTypeProviding`` conformances.

Diagnostics identify the unsupported declaration, member, parameter, type, or
accessor. This keeps runtime behavior and generated editor metadata aligned.

## Documentation and source locations

Swift documentation comments flow into structured TSDoc. Generated schemas,
documentation, and source locations are detached metadata and can be emitted
without creating a runtime.

## Related guides

- <doc:ExportingSwiftTypes>
- <doc:TypeScriptTooling>
- <doc:RuntimeTemplates>
