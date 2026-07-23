# Bindings, Actors, and Promises

Expose typed Swift capabilities while preserving structured concurrency.

## Register a function

```swift
let runtime = try JavaScriptRuntime()

try await runtime.function("sum") { (left: Int, right: Int) in
    left + right
}

let answer: Int = try await runtime.evaluate("sum(20, 22)")
```

Synchronous errors become JavaScript exceptions. An async Swift closure returns
a native QuickJS Promise immediately:

```swift
try await runtime.function("loadName") { (id: Int) async throws -> String in
    try await database.name(for: id)
}

let name: String = try await runtime.evaluate("loadName(42)")
```

Typed root reads automatically await native Promises. Cancelling one Swift
waiter removes only that waiter; explicit binding removal with
`cancellingInFlight: true` cancels producers owned by that binding.

## Export an actor

```swift
try await runtime.export(storage, as: "storage") { storage, export in
    export.function("read") { key in
        try await storage.read(key)
    }
}
```

QuickJS callbacks execute through the owning runtime actor. Async work may
suspend, but Promise settlement always re-enters that actor. Avoid blocking a
synchronous callback and use async functions for external work.

Use ``JavaScriptRuntime/Configuration/maximumPendingHostCallCount`` to bound
outstanding async JavaScript-to-Swift operations.
