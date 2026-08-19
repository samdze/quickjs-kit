# Modules and Loaders

Use standard ES modules, Swift-defined modules, and explicit loader policy.

## Register source modules

```swift
try await runtime.registerModule(
    "export const answer = 42;",
    as: "app:answer",
    sourceURL: "Scripts/answer.js"
)

let module = try await runtime.importModule("app:answer")
let answer: Int = try await module.value(forExport: "answer")
```

Registered modules support static imports, relative imports, cycles,
re-exports, available dynamic imports, and top-level `await`. A module
evaluates at most once in one runtime, and repeated imports preserve module and
namespace identity.

## Define Swift modules

```swift
try await runtime.defineModule("host:math") { module in
    module.function("sum") { (left: Int, right: Int) in
        left + right
    }
}

let module = try await runtime.evaluateModule("""
    import { sum } from "host:math";
    export const answer = sum(20, 22);
    """, sourceURL: "memory:///main.js")
let answer: Int = try await module.value(forExport: "answer")
```

Swift modules use the same typed binding and Promise behavior as global
bindings, but publish members in an ES module namespace.

## Add an asynchronous loader

```swift
try await runtime.setModuleLoader(
    JavaScriptModuleLoader { request in
        JavaScriptModuleSource(
            source: loadSource(for: request.specifier),
            sourceURL: request.specifier
        )
    }
)
```

The resolver and loader are `Sendable`. Loading happens as Swift data outside a
suspending QuickJS callback. Concurrent requests for one canonical specifier
share the same load work; cancelling one consumer does not cancel work needed
by another.

## Define module policy

QuickJSKit does not include an implicit filesystem, network, package-manager,
or npm loader. Applications decide which specifiers are resolvable and which
source may be loaded. For untrusted scripts, allowlist specifiers and validate
loader results. Loader configuration becomes fixed once compilation begins.

## Prepare module graphs

Use ``JavaScriptRuntimeTemplate`` to register source modules and loaders before
creating a runtime. Use `PreloadModule` when a graph should be compiled without
evaluating it, or `ImportModule` when startup should evaluate selected modules.

## Related guides

- <doc:BindingsAndPromises>
- <doc:RuntimeTemplates>
- <doc:SecurityAndUntrustedCode>
