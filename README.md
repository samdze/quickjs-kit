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
        documentation: "Adds two integers."
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
future TypeScript generation:

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

Phase 3 provides evaluation, live values, direct `Codable` conversion, typed
Swift closure registration, native promise interoperability, explicit actor
exports, binding lifecycle control, and unhandled-rejection observation.

Modules, interrupts, timeouts, TypeScript rendering, IDE workspaces, macros,
reflection-based exports, computed properties, and `AbortSignal` integration
remain deliberate future phases. See [Architecture](Documentation/Architecture.md), the
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
