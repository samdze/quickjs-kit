# Bindings and Promises

Expose typed Swift functions to JavaScript while preserving Swift concurrency
and native Promise semantics.

## Register a synchronous function

```swift
let binding = try await runtime.function("sum") {
    (left: Int, right: Int) in
    left + right
}

let answer: Int = try await runtime.evaluate("sum(20, 22)")
```

Parameters are decoded from JavaScript arguments. Missing arguments are
`undefined`; extra arguments are ignored. A `Void` result becomes JavaScript
`undefined`.

## Preserve Swift effects

All four Swift effect combinations have JavaScript behavior:

```swift
try await runtime.function("sync") { (value: Int) in value + 1 }
try await runtime.function("throwing") { (value: Int) throws -> Int in
    guard value >= 0 else { throw MyError.invalidValue }
    return value
}
try await runtime.function("async") { (value: Int) async in value + 2 }
try await runtime.function("asyncThrowing") {
    (value: Int) async throws -> Int in
    try await loadValue(value)
}
```

Synchronous Swift failures become rejected JavaScript calls. Asynchronous
bindings return a native QuickJS Promise immediately; fulfillment and
rejection re-enter the owning runtime actor.

## Wait for native Promises

Typed evaluation, function calls, property reads, array reads, and decoding
automatically await native QuickJS Promises:

```swift
try await runtime.function("loadName") {
    (id: Int) async throws -> String in
    try await loadName(id)
}

let name: String = try await runtime.evaluate("loadName(42)")
```

Raw ``JavaScriptValue`` APIs preserve the Promise as a live value when the
caller needs to observe or pass it explicitly. Arbitrary thenables remain
ordinary JavaScript objects.

## Control binding lifetime

Registration returns a ``JavaScriptBinding``. Removing a binding prevents new
calls while an active call may either finish or be cancelled:

```swift
try await binding.remove()
try await binding.remove(cancellingInFlight: true)
```

Removal is explicit and idempotent. A cancelled Swift waiter is local to that
waiter; it does not cancel a producer needed by another consumer. Use
`cancellingInFlight: true` when the binding owns work that must stop.

## Bound pending work

Set ``JavaScriptRuntime/Configuration/maximumPendingHostCallCount`` to bound
admitted asynchronous JavaScript-to-Swift calls. Calls beyond the limit are
rejected with a JavaScript `RangeError`. The limit applies to admission, not
to cancellation of work already admitted.

## Export actors and objects

Use <doc:ExportingSwiftTypes> when a JavaScript API should be organized as an
object, actor, or module instead of a global function.

## Related guides

- <doc:ErrorsAndDiagnostics>
- <doc:CancellationAndExecutionControl>
- <doc:ExportingSwiftTypes>
- <doc:TypeScriptTooling>
