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

## Reusable runtime templates

`JavaScriptRuntimeTemplate` describes an environment once and creates any
number of independently isolated runtimes. Each runtime owns a distinct
QuickJS heap, context, module registry, Promise queue, limits, and global
object. The template never shares JavaScript objects between them.

```swift
let template = try JavaScriptRuntimeTemplate(
    configuration: .init(memoryLimit: 32 * 1_024 * 1_024)
) {
    Globals {
        Function("sum") { (left: Int, right: Int) in
            left + right
        }
        Value("1.0", as: "hostVersion")
    }

    SwiftModule("host:math") {
        Function("double") { (value: Int) in value * 2 }
    }

    SourceModule(
        "export const answer = 42;",
        as: "app:answer",
        declarations: .init("export const answer: number;")
    )
}

async let first = template.makeRuntime()
async let second = template.makeRuntime()
let (firstRuntime, secondRuntime) = try await (first, second)
```

The template closure is a concrete Result Builder. Components are flattened
immediately into the canonical provisioning definitions, so ordinary `if`,
`switch`, `for`, optional, and availability branches can compose an environment
without creating a retained generic syntax tree.

Shared `Sendable` actors and closures can be captured directly. When every
runtime needs distinct Swift state, declare one asynchronous factory and use
its root across globals, objects, and Swift modules:

```swift
let template = try JavaScriptRuntimeTemplate {
    RuntimeInstance(factory: { Storage() }) {
        RuntimeObject(as: "storage") {
            InstanceFunction("read") { storage, key in
                try await storage.read(key)
            }
            InstanceValue(as: "version") { _ in "1.0" }
        }

        RuntimeModule("host:storage") {
            InstanceFunction("remove") { storage, key in
                try await storage.remove(key)
            }
        }
    }
}
```

The factory root is a Swift-only parameter and does not appear in JavaScript
arity, generated TypeScript, or TSDoc. Factories run sequentially in
declaration order for one creation; separate `makeRuntime()` calls can run
concurrently through ordinary Swift structured concurrency.

Registered source modules are parsed once when the template is created. An
internal compile-only bytecode artifact accelerates installation into each new
heap. Source remains canonical: artifacts are process-local, are never exposed
or persisted, and an unreadable artifact causes a fresh runtime to retry from
source before a Swift factory runs. Module bodies still execute only on import.

Known global scripts can use the same source-canonical optimization through a
reusable program. Startup remains explicit, so moving work into provisioning is
always visible at the template declaration:

```swift
let bootstrap = JavaScriptProgram(
    "initializeHost().then(value => { globalThis.ready = value })",
    sourceURL: "Scripts/bootstrap.js"
)

let template = try JavaScriptRuntimeTemplate {
    Globals {
        Function("initializeHost") { () async -> Bool in true }
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

`prepare` compiles without executing. Startup programs await native Promise
results, preloaded modules link without running their bodies, and startup
imports complete top-level `await` before `makeRuntime()` returns.

Templates also produce the exact TypeScript environment without constructing
QuickJS:

```swift
let environment = try template.environmentDescription()
let workspace = try environment.typeScriptWorkspace()
try workspace.write(to: workspaceURL)
```

For latency-sensitive services, `JavaScriptRuntimeProvisioner` maintains a
bounded supply of fully prepared runtimes:

```swift
let provisioner = try JavaScriptRuntimeProvisioner(
    template: template,
    warmCapacity: 8,
    maximumConcurrentCreations: 4
)

try await provisioner.warmUp()
let runtime = try await provisioner.makeRuntime()
```

Each runtime is transferred permanently and replenished in the background.
QuickJSKit does not reset, return, or reuse an arbitrarily mutated heap; a
general-purpose leasing pool remains application-owned.

## Compile-time exports and runtime-local Swift state

Macros are an optional product. Applications opt in without adding the macro
plugin to QuickJSKit's core runtime:

```swift
import QuickJSKit
import QuickJSKitMacros

/// State owned by exactly one JavaScript runtime.
@JavaScriptExport
final class Counter {
    /// The current count.
    var count: Int = 0

    /// Adds an amount to the count.
    ///
    /// - Parameter amount: The amount to add.
    /// - Returns: The updated count.
    func increment(_ amount: Int) -> Int {
        count += amount
        return count
    }
}

let template = try JavaScriptRuntimeTemplate {
    RuntimeInstance(factory: { Counter() }) {
        RuntimeObject(as: "counter")
    }
}
```

The factory fixes the runtime-local root type, so macro-generated destinations
do not repeat `Counter.self`. The same definition can be installed wherever it
is useful while preserving its generated TSDoc and TypeScript metadata:

```swift
RuntimeInstance(factory: { Counter() }) {
    RuntimeGlobals()
    RuntimeObject(as: "counter")
    RuntimeModule("host:counter")
}
```

Generated modules accept method-only surfaces; expose live properties through
a global or object destination.

The `sending` factory result may be a non-`Sendable` final class. QuickJSKit
invokes the factory on the destination runtime actor, stores the root in an
actor-owned registry, and gives callbacks only its runtime-local identifier.
Synchronous members remain confined there. Async members of non-`Sendable`
classes must be `nonisolated(nonsending)` or use the explicit
`runtimeIsolated:` API so Swift can prove they do not cross executors. Shared
objects still require `Sendable`.

`@JavaScriptExport` is the single compile-time annotation for Swift declarations.
On a Codable struct or supported raw enum it generates a value schema. On a
final class or actor it discovers compatible initializers, methods, static
members, and live properties. `@JavaScriptIgnore`,
`@JavaScriptName("name")`, and `@JavaScriptReadOnly` make selection explicit.
Live properties are enumerable, non-configurable accessors; actor-isolated
getters produce native JavaScript promises.

Macro inference is deliberately fail-closed. Stored Codable properties need
explicit types; `Optional<T>`, `Array<T>`, `Dictionary<String, T>`, and their
Swift sugar forms are equivalent. `CodingKeys` controls omission and encoded
names, including for private stored properties. Computed and static properties
are not part of a value schema. Custom Codable implementations, property
wrappers, lazy storage, non-string dictionary keys, and unsupported generic
containers require handwritten `TypeScriptSchemaProviding` and
`JavaScriptValueTypeProviding` conformances instead of an inferred macro model.

Host signatures are checked during expansion. Generic, failable, defaulted,
variadic, `inout`, autoclosure, and unsupported ownership or isolation forms
produce diagnostics at the offending syntax. JavaScript names, duplicate
members, TSDoc parameter names, and the async-constructor `create` reservation
are validated before runtime configuration. Static and instance members use
separate name spaces, so the same name may intentionally exist on both.

Annotation makes a type export-capable but does not publish it. Value schemas
used by typed bindings enter TypeScript declarations automatically. Add
`JavaScriptType` to a global or Swift module when JavaScript should receive the
constructor or enum validator:

```swift
@JavaScriptExport(scope: .module("host:users"))
struct User: Codable, Sendable {
    /// The stable user identifier.
    let id: Int

    /// The display name.
    let name: String
}

@JavaScriptExport(scope: .module("host:users"))
enum UserStatus: String, Codable, Sendable {
    case active
    case suspended
}

@JavaScriptExport(scope: .module("host:users"))
final class UserService: Sendable {
    init() {}

    func save(_ user: User, status: UserStatus) async throws {
        // Persist the user.
    }
}

let template = try JavaScriptRuntimeTemplate {
    SwiftModule("host:users") {
        JavaScriptType(User.self)
        JavaScriptType(UserStatus.self)
        JavaScriptType(UserService.self)
    }
}
```

```javascript
import { User, UserStatus, UserService } from "host:users";

const user = new User({ id: 42, name: "Ada" });
const service = new UserService();
await service.save(user, UserStatus.active);
```

Struct constructors validate and canonicalize ordinary JavaScript objects;
they do not retain a Swift value. Enum exports are frozen callable validators.
Final classes and actors are live host objects with exact Swift identity and
runtime-local ownership. Direct host references are type-checked and cannot be
forged by plain JavaScript objects. Type registration is permanent for the
runtime lifetime and can also be performed immediately with
`runtime.registerType(_:)` or a Swift module builder's `type(_:)` operation.

Macro documentation for all four declaration kinds is parsed from Swift
documentation comments into
structured TSDoc. Generated workspaces include
`quickjskit.generated.d.ts.map` by default, using logical Swift file IDs rather
than build-machine paths. Use `typeScriptDeclarationBundle()` for the detached
declaration and Source Map v3 pair, or set workspace `sourceMapOptions` to
`nil` to omit maps.

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

Phase 7 provides evaluation, live values, direct `Codable` conversion, typed
Swift bindings and exports, native Promise interoperability, scoped runtime
access, execution controls, ES and Swift modules, custom asynchronous loading,
memory observability, explicit TypeScript schemas, detached environment
snapshots, deterministic declarations, and managed IDE workspaces.

It also provides declarative runtime templates, per-runtime Swift factories,
private source-canonical module compilation caching, optional compile-time
exports and model schemas, live accessor properties, and declaration source
maps. Runtime reflection, workers, and `AbortSignal` integration remain
deliberate future phases. See [Architecture](Documentation/Architecture.md), the
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
swift test -c release -Xswiftc -warnings-as-errors
CFLAGS=-Werror swift build -c release --target CQuickJS
swift run QuickJSKitBenchmarks --iterations 100
```

Treat warnings and sanitizer findings as defects.
