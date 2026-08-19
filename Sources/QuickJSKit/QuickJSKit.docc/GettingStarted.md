# Getting Started

Use ``JavaScriptRuntime`` when an application needs one isolated JavaScript
environment.

## Add the package

Add the `QuickJSKit` product to your Swift package and import it in the target
that hosts JavaScript:

```swift
import QuickJSKit
```

QuickJSKit requires Swift 6.3 or later. The public API uses Swift concurrency;
runtime operations are asynchronous because they cross the runtime actor.

## Create a runtime

```swift
let runtime = try JavaScriptRuntime()
```

The default configuration is unrestricted. For externally supplied scripts,
begin with ``JavaScriptRuntime/Configuration/restricted`` and adjust limits
after measuring the workload. See <doc:SecurityAndUntrustedCode>.

## Evaluate typed results

The result type controls direct decoding:

```swift
struct User: Codable, Sendable {
    let id: Int
    let name: String
}

let user: User = try await runtime.evaluate("""
    ({ id: 42, name: "Ada" })
    """)
```

Use an explicit type argument when contextual inference is unavailable:

```swift
let user = try await runtime.evaluate(source, as: User.self)
```

Untyped evaluation returns ``JavaScriptValue``. Objects, arrays, and functions
remain live handles, so use that form when JavaScript identity or mutation is
important. See <doc:WorkingWithJavaScriptValues>.

## Choose between typed and live APIs

Prefer typed results for snapshots that can be represented by `Codable`.
Prefer live values when the JavaScript object must be inspected, mutated, or
called repeatedly. Both choices preserve runtime isolation; a live handle
cannot be used with another runtime.

## Continue learning

- Understand isolation and value lifetime in <doc:RuntimeModel>.
- Learn conversion rules in <doc:EvaluationAndConversion>.
- Build an app command with <doc:BuildAHostForJavaScript>.
- Explore runtime reuse in a server workflow with
  <doc:BuildAProductionPluginRunner>.
