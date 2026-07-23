# Getting Started

Create an isolated runtime and decode JavaScript directly into Swift.

## Evaluate typed results

``JavaScriptRuntime`` is an actor. Every operation on its QuickJS heap is
serialized without requiring locks or a dedicated thread.

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

Use the explicit type argument when contextual inference is unavailable:

```swift
let user = try await runtime.evaluate(source, as: User.self)
```

Raw evaluation returns ``JavaScriptValue`` and preserves live identity for
objects, arrays, and functions. Typed evaluation decodes directly while the
temporary result is owned by the runtime.

## Choose a configuration

`JavaScriptRuntime.Configuration()` is unrestricted. Start applications that
accept externally supplied scripts with
``JavaScriptRuntime/Configuration/restricted`` and customize its limits for
their workload. See <doc:RunningUntrustedCode>.

For repeatedly configured runtimes, use <doc:RuntimeTemplates>.
