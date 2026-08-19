# Runtime Model

QuickJSKit makes the JavaScript heap an explicit ownership and concurrency
boundary.

## One actor owns one heap

``JavaScriptRuntime`` is an actor. It owns one QuickJS heap, global object,
module graph, Promise queue, and live-value registry. Operations on one runtime
are serialized without requiring callers to coordinate locks.

Independent runtimes are independent isolation domains and can run
concurrently:

```swift
let first = try JavaScriptRuntime()
let second = try JavaScriptRuntime()

async let firstAnswer: Int = first.evaluate("20 + 22")
async let secondAnswer: Int = second.evaluate("6 * 7")

let answers = try await [firstAnswer, secondAnswer]
```

Operations on the same runtime can be submitted from many tasks, but they
still execute through that runtime actor.

## Detached values and live values

Detached values are Swift-owned data such as primitives, decoded models, and
``JavaScriptBigInt``. They can cross concurrency domains without engine access.

``JavaScriptObject``, ``JavaScriptArray``, and ``JavaScriptFunction`` are live
handles. They preserve JavaScript identity and mutation, and every operation
returns to the owning runtime actor. A live value retains its runtime until the
handle is released.

## Runtime affinity

Do not pass a live handle from one runtime into another:

```swift
let value: JavaScriptValue = try await first.evaluate("({ answer: 42 })")

// A cross-runtime live-value operation throws JavaScriptError.
try await second.global.set(value, forProperty: "value")
```

Use `Codable` to create a detached snapshot when data must move between
runtimes.

## Actor reentrancy

An operation passed to an asynchronous runtime access method may suspend and
is reentrant at suspension points. It is not a transaction across those
suspensions. Keep engine work short and perform external asynchronous work in
Swift tasks or async bindings.

## Lifetime and cleanup

Runtime-bound values are released through their owning actor. Do not rely on a
live handle's deinitializer to perform synchronous engine work, and do not
store live values in a ``JavaScriptRuntimeTemplate``. Templates contain
detached definitions; each created runtime receives its own heap and live
values.

## Related guides

- <doc:EvaluationAndConversion>
- <doc:WorkingWithJavaScriptValues>
- <doc:CancellationAndExecutionControl>
- <doc:RuntimeTemplates>
