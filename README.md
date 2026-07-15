# QuickJSKit

QuickJSKit is a modern Swift interface to the QuickJS JavaScript engine. Its
goal is to make embedding JavaScript feel like using a native Swift framework:
safe ownership, actor-isolated execution, typed conversions, structured errors,
and no C concepts in the public API.

The project is currently in its architecture-validation phase. The available
surface intentionally covers only runtime creation, resource configuration,
script evaluation, primitive values, and JavaScript exceptions.

```swift
import QuickJSKit

let runtime = try JavaScriptRuntime()
let answer = try await runtime.evaluate("6 * 7")

print(answer.numberValue as Any) // Optional(42.0)
```

Every call into QuickJS is serialized by `JavaScriptRuntime`, an actor. The C
engine and its manual ownership model remain internal implementation details.
See [Architecture](Documentation/Architecture.md) and [AGENTS.md](AGENTS.md)
before contributing.

## Requirements

- Swift 6.3 or newer
- macOS 13+, iOS 16+, tvOS 16+, watchOS 9+, or visionOS 1+
- Linux, Windows, and Android toolchains capable of building Swift Package
  Manager C targets

## Phase 1 scope

Implemented:

- vendored, pinned upstream QuickJS
- actor-isolated runtime and context ownership
- deterministic RAII cleanup at the Swift/C boundary
- primitive evaluation results
- structured JavaScript errors with stack traces
- memory and stack limits

Deferred by design:

- live object, array, and function handles
- typed and `Codable` conversions
- Swift closure registration and exported objects
- promise/async bridging, modules, interrupts, and cancellation
- TypeScript declaration and IDE workspace generation
- macros

QuickJS is copyright Fabrice Bellard and Charlie Gordon and is distributed
under the MIT license in `Sources/CQuickJS/LICENSE`.

## Development

Build and run the focused architecture suite with:

```console
swift build
swift test
```

Treat warnings as defects. See `AGENTS.md` for ownership, concurrency, testing,
documentation, and contribution requirements.
