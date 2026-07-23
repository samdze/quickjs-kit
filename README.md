# QuickJSKit

QuickJSKit is a modern Swift interface to the QuickJS JavaScript engine. It
provides actor-isolated execution, direct Codable conversion, typed Swift
bindings, native Promises, ES modules, reusable runtime templates,
JavaScript-visible Swift types, and deterministic TypeScript tooling without
exposing C APIs or manual ownership.

```swift
import QuickJSKit

struct User: Codable, Sendable {
    let id: Int
    let name: String
}

let runtime = try JavaScriptRuntime()
let user: User = try await runtime.evaluate("""
    ({ id: 42, name: "Ada" })
    """)
```

The contextual result type selects direct decoding. No JSON document or
intermediate Swift value tree is required.

## Highlights

- Swift 6.3 strict concurrency with one actor per independent QuickJS heap.
- Pointer-free live objects, arrays, functions, modules, and host objects.
- Lossless integers, `BigInt`, optionals, collections, `Data`, `Date`, `URL`,
  and custom `Codable` models.
- Typed sync, throwing, async, and async-throwing Swift functions bridged to
  JavaScript exceptions and native Promises.
- ES modules, Swift modules, lexical resolution, custom async loaders, cycles,
  top-level `await`, and prepared programs.
- Execution cancellation, timeouts, interruption, memory and stack limits,
  host-object limits, pending-call backpressure, and resource observability.
- Immutable runtime templates and prewarmed one-shot provisioning for many
  independently isolated runtimes.
- `@JavaScriptExport` for Codable value types and live Swift class or actor
  types, with explicit runtime publication.
- Deterministic `.d.ts`, rich TSDoc, source maps, and managed IDE workspaces.
- The same public API on Apple platforms, Linux, Windows, and Android.

## Typed bindings and native Promises

```swift
try await runtime.function("sum") { (left: Int, right: Int) in
    left + right
}

try await runtime.function("loadUser") {
    (id: Int) async throws -> User in
    try await database.user(id: id)
}

let answer: Int = try await runtime.evaluate("sum(20, 22)")
let loaded: User = try await runtime.evaluate("loadUser(42)")
```

Typed evaluation, calls, property reads, array reads, and decoding automatically
await native QuickJS Promises. Raw APIs preserve the live Promise object.

## Modules

```swift
try await runtime.defineModule("host:math") { module in
    module.function("sum") { (left: Int, right: Int) in
        left + right
    }
}

try await runtime.registerModule(
    """
    import { sum } from "host:math";
    export const answer = sum(20, 22);
    """,
    as: "app:main"
)

let module = try await runtime.importModule("app:main")
let answer: Int = try await module.value(forExport: "answer")
```

## Reusable runtime templates

```swift
let template = try JavaScriptRuntimeTemplate(
    configuration: .restricted
) {
    Globals {
        Function("sum") { (left: Int, right: Int) in
            left + right
        }
    }
    SourceModule("export const version = '1.0';", as: "app:info")
}

let runtime = try await template.makeRuntime()
```

Each created runtime has its own heap, context, jobs, modules, limits, and
failure domain. Templates reuse detached Swift definitions and private
source-canonical compile artifacts, never mutable heap state.

Use `JavaScriptRuntimeProvisioner` when runtimes should be prepared before
demand and transferred permanently to callers.

## JavaScript-visible Swift types

Import the optional macro product:

```swift
import QuickJSKit
import QuickJSKitMacros

@JavaScriptExport(scope: .module("host:users"))
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

Annotation creates a checked capability and metadata; `JavaScriptType` controls
where it is published. Structs and raw enums are JavaScript value types. Final
classes and actors are live host types with runtime-local identity.

## TypeScript tooling

```swift
let environment = try template.environmentDescription()
let declarations = try environment.typeScriptDeclarations()
let workspace = try environment.typeScriptWorkspace(
    options: .init(
        sourceGlobs: ["Scripts/**/*.js", "Scripts/**/*.ts"],
        checkJavaScript: true,
        includePackageJSON: true
    )
)
try workspace.write(to: workspaceURL)
```

Generated declarations include structured TSDoc, scopes, globals, module
exports, schemas, constructors, and source maps. Snapshots contain no runtime,
closure, actor, live value, or C state.

## Security

`JavaScriptRuntime.Configuration.restricted` is a customizable starting point:
64 MiB memory, 512 KiB JavaScript stack, one second of active JavaScript
execution, 1,024 live host objects, and 256 pending async host calls.

It is not an operating-system sandbox. QuickJS and exported Swift code execute
inside the application process. Run hostile code in a separately sandboxed
process and expose only minimal allowlisted capabilities. Read
[SECURITY.md](SECURITY.md) and the DocC guide *Running Untrusted Code* before
accepting untrusted scripts.

## Documentation and examples

The DocC catalog contains task-oriented guides for evaluation, conversions,
bindings, Promises, modules, templates, TypeScript tooling, security, platform
support, ownership, cancellation, and performance.

Standalone packages under [Examples](Examples) demonstrate:

- typed evaluation and Codable;
- async Swift host APIs;
- ES and Swift modules;
- templates and prewarmed provisioning;
- macros and TypeScript workspace generation.

Public tests are also executable consumer examples and import only QuickJSKit.

## Platform support

| Platform | Minimum or target |
| --- | --- |
| macOS | 13 |
| iOS / tvOS | 16 |
| watchOS | 9 |
| visionOS | 1 |
| Linux | Swift 6.3 supported distributions |
| Windows | x86-64 Swift 6.3 |
| Android | official Swift 6.3 SDK |

Every declared platform is a release-blocking CI target. The public API does not
vary by platform.

## Development

```console
swift test
swift test -c release -Xswiftc -warnings-as-errors
Scripts/verify-vendored-quickjs.sh
swift run -c release QuickJSKitBenchmarks --iterations 100
```

See [AGENTS.md](AGENTS.md), [Architecture](Documentation/Architecture.md),
[Contributing](CONTRIBUTING.md), [Migration notes](MIGRATION.md), and the
[architectural decisions](Documentation/Decisions).

QuickJS is copyright Fabrice Bellard and Charlie Gordon and is distributed
under the MIT license in `Sources/CQuickJS/LICENSE`.
