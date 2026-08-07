# Compile-Time Exports

Generate JavaScript capabilities and TypeScript metadata from one checked Swift
declaration.

## Overview

Import the optional macro product alongside QuickJSKit:

```swift
import QuickJSKit
import QuickJSKitMacros
```

Apply `@JavaScriptExport` to a Codable struct, a raw `String` or `Int` enum, a
final class, or an actor. Structs and enums become value capabilities. Final
classes and actors become live host capabilities. Publication remains explicit
through `JavaScriptType`, so annotation alone never changes a runtime.

```swift
@JavaScriptExport
struct User: Codable, Sendable {
    /// The stable user identifier.
    let id: Int

    /// The display name.
    let name: String
}

let template = try JavaScriptRuntimeTemplate {
    SwiftModule("host:users") {
        JavaScriptType(User.self)
    }
}
```

## Inference boundaries

Value schemas include stored instance properties, including private properties,
and honor `CodingKeys`. Computed and static properties are excluded. Optional,
array, and string-keyed dictionary sugar is equivalent to `Optional<T>`,
`Array<T>`, and `Dictionary<String, T>`.

QuickJSKit rejects syntax when it cannot infer the encoded representation
honestly. Custom Codable implementations, property wrappers, lazy properties,
non-string dictionary keys, tuples, function types, metatypes, and unsupported
generic containers require handwritten ``TypeScriptSchemaProviding`` and
``JavaScriptValueTypeProviding`` conformances.

Host exports reject unsupported initializer and method features during macro
expansion. Use `@JavaScriptIgnore` to exclude a member,
`@JavaScriptName("name")` to rename it, and `@JavaScriptReadOnly` to omit a
setter. Diagnostics have stable QuickJSKit macro identifiers and point to the
offending declaration, member, parameter, type, or accessor.

Documentation comments flow through the same parsed model into structured
TSDoc and declaration source maps. Runtime behavior and generated editor
metadata therefore cannot select different members or enum values.
