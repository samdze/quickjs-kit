# Modules and Custom Loaders

Use standard ES modules and explicit Swift-defined modules.

## Register and import source

```swift
let runtime = try JavaScriptRuntime()
try await runtime.registerModule(
    "export const answer = 42;",
    as: "app:answer",
    sourceURL: "Scripts/answer.js"
)

let module = try await runtime.importModule("app:answer")
let answer: Int = try await module.value(forExport: "answer")
```

Registered modules support static imports, cycles, re-exports, dynamic imports
of available sources, and top-level `await`. A module evaluates at most once in
one runtime.

## Define a Swift module

```swift
try await runtime.defineModule("host:math") { module in
    module.function("sum") { (left: Int, right: Int) in
        left + right
    }
}
```

Custom ``JavaScriptModuleLoader`` resolution and loading closures are
`Sendable`. Loaded source crosses suspension only as Swift data; no C value or
borrowed string leaves the runtime entry. Resolve only allowlisted specifiers
when scripts are not trusted.

Templates can preload module graphs without evaluating them or import selected
modules during startup. See <doc:RuntimeTemplates>.
