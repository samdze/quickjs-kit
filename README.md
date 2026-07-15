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
JSON or an intermediate value tree. Phase 2 supports:

- strict `Bool`, `String`, `Float`, and `Double` conversion;
- lossless signed and unsigned integers, using JavaScript `bigint` outside the
  safe `number` range;
- optionals, arrays, string-keyed dictionaries, and `Codable` models;
- `Data` as `Uint8Array`, `Date` as JavaScript `Date`, and `URL` as a string;
- permissive documented decode forms for binary data, dates, and URLs;
- arbitrary-size detached integers through `JavaScriptBigInt`.

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

Phase 2 provides evaluation, live objects/arrays/functions, globals, arbitrary
BigInt values, direct `Codable` conversion, Foundation value policies, resource
configuration, and structured errors.

Swift closure registration, promises and async bridging, modules, interrupts,
timeouts, TypeScript generation, IDE workspaces, and macros remain deliberate
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
