# Exporting Swift Types

Publish Swift capabilities as JavaScript globals, objects, or ES module
members. Keep the exported surface intentionally small: every exported member
is authority granted to JavaScript.

## Export an object

```swift
actor Storage {
    func read(_ key: String) async throws -> String {
        try await databaseRead(key)
    }
}

let storage = Storage()
try await runtime.export(storage, as: "storage") { storage, export in
    export.function("read") { key in
        try await storage.read(key)
    }
}
```

Callbacks execute through the owning runtime actor. Async work may suspend;
Promise settlement always returns to that actor.

## Choose the publication location

``JavaScriptRuntime/export(_:as:documentation:_:)`` publishes an object on
`globalThis`. ``JavaScriptRuntime/defineModule(_:documentation:_:)`` publishes
members in one ES module. The same definitions can be reused in
``JavaScriptRuntimeTemplate`` with ``Globals`` and ``SwiftModule``.

The destination owns the JavaScript and TypeScript location. An exported Swift
type does not carry an intrinsic global or module scope.

## Export properties and values

Use ``JavaScriptExportBuilder`` to expose typed methods, snapshot values, and
live properties. Snapshot values are encoded into the destination runtime;
live properties keep runtime-local identity. Mark properties read-only when
JavaScript should not assign them.

Publication is transactional. If validation, encoding, or one member fails,
the destination is left unchanged.

## Runtime-local state

When each runtime needs its own non-`Sendable` host object, use a
``RuntimeInstance`` factory in a template. The root is supplied to Swift
callbacks and does not become a JavaScript argument or a TypeScript type.

## Design capabilities, not internals

Expose methods that represent application capabilities rather than general
filesystem, network, credential, or process access. Document the exported
surface with ``TypeScriptDocumentation`` so JavaScript and TypeScript users see
the same contract.

## Related guides

- <doc:BindingsAndPromises>
- <doc:CompileTimeExports>
- <doc:ModulesAndLoaders>
- <doc:SecurityAndUntrustedCode>
