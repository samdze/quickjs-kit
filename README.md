# QuickJSKit

QuickJSKit is a modern Swift interface to the QuickJS JavaScript engine. It
makes embedding JavaScript feel like using a native Swift framework: ownership
is automatic, execution is actor-isolated, conversions are type-safe, errors
retain JavaScript diagnostics, and no C concepts appear in the public API.

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

The contextual result type selects direct decoding. The same operation can make
the type explicit and attach a diagnostic source name:

```swift
let user = try await runtime.evaluate(
    "({ id: 42, name: 'Ada' })",
    as: User.self,
    sourceURL: "user.js"
)
```

## Live JavaScript values

Untyped evaluation preserves JavaScript object identity through pointer-free,
`Sendable` handles. All operations return to the actor that owns the value.

```swift
let value = try await runtime.evaluate("({ count: 1, tags: ['swift'] })")
let object = value.objectValue!

try await object.set(2, forProperty: "count")
let count: Int = try await object.value(forProperty: "count")
```

Objects support typed and untyped property access, existence checks, deletion,
and own enumerable property names. Arrays add indexed access and append.
Functions accept heterogeneous Swift arguments and directly decode results:

```swift
let value = try await runtime.evaluate("(a, b) => a + b")
let function = value.functionValue!
let answer: Int = try await function.call(20, 22)
```

The force unwraps above keep the README compact. Application code can use
`guard let` or its preferred validation mechanism when a script is not trusted.

## Globals and direct codecs

```swift
try await runtime.global.set(user, forProperty: "user")
let stored: User = try await runtime.global.value(forProperty: "user")

var encoder = runtime.encoder
var decoder = runtime.decoder
encoder.maximumNestingDepth = 64
decoder.maximumNestingDepth = 64

let encoded = try await encoder.encode(user)
let decoded = try await decoder.decode(User.self, from: encoded)
```

The codecs traverse QuickJS values directly. They do not serialize through
JSON or an intermediate value tree. QuickJSKit supports:

- strict `Bool`, `String`, `Float`, and `Double` conversion;
- lossless signed and unsigned integers, using JavaScript `bigint` outside the
  safe `number` range;
- optionals, arrays, string-keyed dictionaries, and `Codable` models;
- `Data` as `Uint8Array`, `Date` as JavaScript `Date`, and `URL` as a string;
- permissive documented decode forms for binary data, dates, and URLs;
- arbitrary-size detached integers through `JavaScriptBigInt`.

## Typed Swift bindings and native promises

Swift parameter packs preserve heterogeneous argument types without exposing a
variadic C-shaped callback API. Synchronous, throwing, asynchronous, and
asynchronous-throwing closures use their natural JavaScript behavior:

```swift
let sum = try await runtime.function(
    "sum",
    options: .init(
        parameterNames: ["left", "right"],
        documentation: .init(
            summary: "Adds two integers.",
            parameters: [
                "left": "The first integer.",
                "right": "The second integer.",
            ],
            returns: "The exact sum.",
        ),
    )
) { (left: Int, right: Int) in
    left + right
}

let answer: Int = try await runtime.evaluate("sum(20, 22)")
try await sum.remove()
```

Async Swift functions return native QuickJS promises. Typed evaluation,
function calls, property and array reads, and `JavaScriptDecoder` automatically
await native promises. Raw APIs return live promise objects immediately.

```swift
try await runtime.function("loadUser") { (id: Int) async throws -> User in
    try await database.user(id: id)
}

let user: User = try await runtime.evaluate("loadUser(42)")
```

Explicit exports make the JavaScript surface reviewable and retain metadata for
TypeScript generation:

```swift
let binding = try await runtime.export(storage, as: "storage") { storage, export in
    export.function("read", options: .init(parameterNames: ["key"])) { key in
        try await storage.read(key)
    }
    export.value("1.0", as: "version", documentation: "API version.")
}
```

Methods are read-only and non-enumerable; snapshot values are read-only and
enumerable. Export publication is transactional. Binding removal is explicit,
idempotent, and can either preserve or cancel active asynchronous calls.

JavaScript execution failures are `JavaScriptError` values with copied names,
messages, stacks, and source identities. Swift result-shape failures use the
standard `EncodingError` and `DecodingError` families with coding paths.

## Scoped execution and controls

`run` groups operations under one actor isolation context. Its synchronous
form cannot suspend; its asynchronous form supports ordinary `try await` and is
reentrant whenever the operation suspends:

```swift
let total = try await runtime.run { runtime in
    let first: Int = try runtime.evaluate("20")
    let second: Int = try runtime.evaluate("22")
    return first + second
}

let refreshed = try await runtime.run { runtime in
    let user: User = try await runtime.evaluate("loadUser()")
    return user
}
```

Synchronous typed evaluation drains immediately runnable jobs. It throws
`JavaScriptError` with kind `.wouldSuspend` if external asynchronous progress
is still required. Active JavaScript can be bounded per operation or by a
runtime default:

```swift
let runtime = try JavaScriptRuntime(configuration: .init(
    defaultExecutionTimeout: .milliseconds(250)
))

let result: Int = try await runtime.evaluate(
    "expensiveCalculation()",
    options: .init(timeout: .after(.seconds(1)))
)
```

Task cancellation, deadlines, and a custom interrupt predicate stop active
QuickJS execution without making the runtime unusable. `memoryUsage()` exposes
a stable heap summary and `collectGarbage()` requests an explicit collection.

## ES and Swift modules

Runtime-local source supports native static imports, cycles, re-exports,
dynamic imports of registered source, `import.meta.url`, and top-level await:

```swift
try await runtime.registerModule(
    "export const answer = 42",
    as: "app/math.js"
)

let module = try await runtime.importModule("app/math.js")
let answer: Int = try await module.value(forExport: "answer")
```

An asynchronous loader can resolve a complete static dependency graph without
blocking a Swift executor. Load work suspends outside QuickJS and concurrent
requests for the same canonical specifier are coalesced:

```swift
try await runtime.setModuleLoader(.init { request in
    let source = try await sourceStore.load(request.specifier)
    return JavaScriptModuleSource(
        source: source,
        sourceURL: "memory:///\(request.specifier)"
    )
})
```

Swift-defined modules reuse the same typed binding and native Promise machinery
as globals and explicit object exports:

```swift
try await runtime.defineModule("app/native") { module in
    module.value("1.0", as: "version", documentation: "API version.")
    module.function("sum") { (left: Int, right: Int) in
        left + right
    }
}
```

Module registration and Swift module definition are transactional. Loader
configuration becomes immutable once module compilation starts.

## TypeScript declarations and IDE workspaces

Swift models opt into structural declarations explicitly. The schema is an
immutable value, can describe related or recursive definitions, and is ready
for future macro synthesis:

```swift
extension User: TypeScriptSchemaProviding {
    static let typeScriptSchema = TypeScriptSchema.interface(
        "User",
        scope: "Acme.Models",
        documentation: "A user visible to embedded scripts.",
        properties: [
            .init(
                "id",
                type: .number,
                isReadonly: true,
                documentation: "The stable user identifier.",
            ),
            .init(
                "name",
                type: .string,
                isReadonly: true,
                documentation: "The display name.",
            ),
        ],
    )
}
```

Every schema has one explicit declaration scope. Global and namespaced types
are available to scripts without imports; namespaces organize types only and do
not create JavaScript objects:

```swift
let global = TypeScriptSchema.interface(
    "Configuration",
    scope: .global,
    properties: [.init("debug", type: .boolean)]
)

let model = TypeScriptSchema.interface(
    "User",
    scope: "Acme.Models",
    properties: [.init("id", type: .number)]
)
```

A schema owned by a known JavaScript module becomes an importable type export:

```swift
static let typeScriptSchema = TypeScriptSchema.interface(
    "User",
    scope: .module("host:users"),
    properties: [.init("id", type: .number)]
)
```

```typescript
import { loadUser, type User } from "host:users";

const user: User = await loadUser(42);
```

Functions and values outside that module refer to the same canonical type as
`import("host:users").User`; this type expression does not perform a runtime
import. A schema used by several modules remains declared once in its chosen
scope.

Capture the exact Swift-provided environment after configuring a runtime, then
render declarations or a complete editor workspace without retaining the
runtime:

```swift
let environment = try await runtime.environmentDescription()
let declarations = try environment.typeScriptDeclarations()

let projectDeclarations = try environment.typeScriptDeclarations(
    options: .init(defaultTypeScope: "MyProject.Models")
)

let workspace = try environment.typeScriptWorkspace(
    options: .init(
        sourceGlobs: ["Scripts/**/*.js", "Scripts/**/*.ts"],
        checkJavaScript: true,
        includePackageJSON: true
    )
)
try workspace.write(to: workspaceURL)
```

The workspace contains `quickjskit.generated.d.ts`, `tsconfig.json`, and an
optional private ESM `package.json`. A private ownership manifest makes
regeneration idempotent and prevents QuickJSKit from replacing unrelated or
user-modified files by default.

Source modules supply companion declaration bodies explicitly:

```swift
try await runtime.registerModule(
    "export const answer = 42;",
    as: "app:answer",
    typeScriptDeclarations: .init("export const answer: number;")
)
```

Additional schemas may target the same source-module scope. QuickJSKit emits
those generated type exports before the opaque companion body in one ambient
module declaration. A source module that owns generated types must provide a
companion body even in permissive mode, because TypeScript cannot combine a
typed module body with an open-ended shorthand ambient module safely.

Strict generation reports custom `Codable` types without a schema and source
modules without companion declarations. `.allowUntyped` is an explicit escape
hatch that renders these surfaces as `unknown` or untyped ambient modules.

Functions and declarations accept structured TSDoc containing summaries,
remarks, parameter and return documentation, thrown-error conditions, examples,
see-also links, defaults, and deprecation guidance. This metadata is emitted in
the generated `.d.ts` file, so TypeScript-aware editors can display it in hover
cards, signature help, completion details, and deprecation diagnostics.

Documentation completeness is independent from type completeness. Applications
can make complete IDE documentation a generation gate:

```swift
let declarations = try environment.typeScriptDeclarations(
    options: .init(
        documentationCompleteness: .requireComplete
    )
)
```

In this mode, every generated symbol needs a summary, every parameter needs a
description, non-`Void` functions need return documentation, and throwing
functions need at least one documented error. Source-module companion bodies
remain opaque and are responsible for documenting their own exports.

This pre-release API uses `defaultTypeScope` in place of the former
`typeNamespace` option. `TypeScriptDefinition` is now a value with a nested
`Kind`, and cross-scope named references identify their destination explicitly.

## Concurrency and ownership

`JavaScriptRuntime` is an actor. Calls into one QuickJS heap are serialized,
while independent runtimes may make concurrent progress. Live handles retain
their runtime, contain no C pointer, and schedule registry release through the
runtime actor. The registry releases all retained values before context and
runtime destruction.

## Requirements

- Swift 6.3 or newer with strict concurrency checking
- macOS 13+, iOS 16+, tvOS 16+, watchOS 9+, or visionOS 1+
- Linux, Windows, and Android toolchains capable of building Swift Package
  Manager C targets

## Current scope

Phase 5 provides evaluation, live values, direct `Codable` conversion, typed
Swift bindings and exports, native Promise interoperability, scoped runtime
access, execution controls, ES and Swift modules, custom asynchronous loading,
memory observability, explicit TypeScript schemas, detached environment
snapshots, deterministic declarations, and managed IDE workspaces.

Runtime templates, macros, reflection-based exports, declaration source maps,
computed properties, workers, and `AbortSignal` integration remain deliberate
future phases. See [Architecture](Documentation/Architecture.md), the
[decision records](Documentation/Decisions), and [AGENTS.md](AGENTS.md) before
contributing.

QuickJS is copyright Fabrice Bellard and Charlie Gordon and is distributed
under the MIT license in `Sources/CQuickJS/LICENSE`.

## Development

The public test suites are executable usage examples and import only
`QuickJSKit`. Internal tests use `@testable` solely for otherwise unobservable
ownership and registry invariants.

```console
swift build
swift test
swift test -Xswiftc -warnings-as-errors -Xcc -Werror
```

Treat warnings and sanitizer findings as defects.
