# Runtime Templates

Declare one host environment and create independently isolated runtimes from it.

## Overview

``JavaScriptRuntimeTemplate`` stores reusable Swift definitions, source
modules, loaders, documentation, schemas, and optional per-runtime Swift
factories. It never stores a QuickJS heap or live JavaScript value.

```swift
let template = try JavaScriptRuntimeTemplate {
    Globals {
        Function("sum") { (left: Int, right: Int) in
            left + right
        }
    }

    SourceModule(
        "export const answer = 42;",
        as: "app:answer",
        declarations: .init("export const answer: number;")
    )
}

let runtime = try await template.makeRuntime()
let answer: Int = try await runtime.evaluate("sum(20, 22)")
```

The template uses concrete Result Builder components. Standard Swift `if`,
`switch`, `for`, optional, and availability branches are flattened in lexical
order into the canonical detached provisioning definitions.

Every created ``JavaScriptRuntime`` has a separate QuickJS runtime, context,
module graph, Promise queue, globals, and resource limits. Create several in
parallel with Swift structured concurrency rather than sharing one heap.

## Prepared programs and startup

Use ``JavaScriptProgram`` when the same global script runs in several runtimes
or repeatedly in one runtime:

```swift
let bootstrap = JavaScriptProgram(
    "loadConfiguration().then(value => { globalThis.configuration = value })",
    sourceURL: "Scripts/bootstrap.js"
)

let template = try JavaScriptRuntimeTemplate {
    Globals {
        Function("loadConfiguration") { () async -> Bool in true }
    }
    SourceModule("export const shared = true", as: "app:shared")
    SourceModule(
        "import { shared } from 'app:shared'; export { shared }",
        as: "app:main"
    )
    Prepare(bootstrap)
    Startup {
        Run(bootstrap)
        PreloadModule("app:shared")
        ImportModule("app:main")
    }
}
```

Prepared programs and registered modules keep source as their canonical form
and use private compile-only artifacts as a disposable optimization. Startup
actions run after all Swift definitions and per-runtime roots are installed.
Program Promise results and module top-level `await` complete before the
runtime is returned.

## Prewarmed runtime supply

``JavaScriptRuntimeProvisioner`` maintains ready runtimes without weakening
heap isolation:

```swift
let provisioner = try JavaScriptRuntimeProvisioner(
    template: template,
    warmCapacity: 4
)
try await provisioner.warmUp()

let runtime = try await provisioner.makeRuntime()
```

The returned runtime leaves the provisioner permanently. Replenishment creates
a new independent heap; no runtime is reset, returned, or reused. Shutting down
the provisioner affects only pending work and runtimes it has not transferred.

## Per-runtime Swift state

Use a root factory when host state must also be isolated:

```swift
actor Storage {
    func read(_ key: String) -> String { key }
}

let template = try JavaScriptRuntimeTemplate {
    RuntimeInstance(factory: { Storage() }) {
        RuntimeObject(as: "storage") {
            InstanceFunction("read") { storage, key in
                try await storage.read(key)
            }
        }
    }
}
```

The root is passed only to Swift. It does not contribute a JavaScript argument
or appear in generated TypeScript. One factory root can back globals, exported
objects, and Swift modules, and the created runtime retains it until teardown.

## Tooling without a runtime

The template exposes the same detached metadata model as a configured runtime:

```swift
let environment = try template.environmentDescription()
let declarations = try environment.typeScriptDeclarations()
let workspace = try environment.typeScriptWorkspace()
```

Calling this method does not create QuickJS or invoke a Swift factory.

## Publication locations

``Globals`` publishes functions, values, and types on `globalThis`.
``SwiftModule`` publishes the same members in one ES module. A macro-generated
`@JavaScriptExport` type has no intrinsic TypeScript location, so its schema
inherits the container that publishes it. References to a separately
registered type keep that type's own location; generated module declarations
use one local `import type` block per module and deduplicate its imports.

## Compilation and ownership

Registered source and prepared programs are parsed during template construction
and may receive private compile-only artifacts. Each runtime reads those
artifacts into its own heap. Module bodies remain unevaluated unless explicitly
started or imported. Source stays canonical and is used automatically if an
artifact cannot be read.

Live ``JavaScriptValue`` instances cannot be placed in a template because they
belong to an existing runtime. Use `Codable` snapshot values or create the live
value separately in each resulting runtime.
