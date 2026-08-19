# Cancellation and Execution Control

Control active JavaScript work, Swift task cancellation, and asynchronous host
work as separate but cooperating mechanisms.

## Set an execution deadline

Configure a default deadline or override it for one operation:

```swift
let runtime = try JavaScriptRuntime(
    configuration: .init(
        defaultExecutionTimeout: .seconds(1)
    )
)

let answer: Int = try await runtime.evaluate(
    "20 + 22",
    options: .init(timeout: .milliseconds(100))
)
```

Execution deadlines cover active parsing, JavaScript execution, and immediately
runnable jobs. They do not include time suspended in Swift bindings, module
loaders, or host Promise waiting.

## Cancel active JavaScript

Swift task cancellation interrupts active JavaScript and is reported as
cancellation. The runtime remains reusable after the operation returns.

Use ``JavaScriptRuntime/setInterruptHandler(_:)`` for a synchronous host
predicate that must stop work. The predicate must return quickly, cannot
suspend, and must not call back into the runtime.

## Control asynchronous host work

Cancelling one Swift waiter removes only that waiter. The native Promise
producer continues when another consumer still needs it. Remove a binding with
`cancellingInFlight: true` when the binding owns work that should be cancelled
for every consumer.

Use ``JavaScriptRuntime/Configuration/maximumPendingHostCallCount`` to apply
backpressure before unbounded asynchronous host calls are admitted.

## Synchronous versus asynchronous access

The synchronous runtime access form can evaluate work that completes during the
current job checkpoint. It reports a pending Promise as `.wouldSuspend` instead
of blocking. Use the asynchronous form for external progress and ordinary
`try await` behavior.

## Related guides

- <doc:BindingsAndPromises>
- <doc:ErrorsAndDiagnostics>
- <doc:SecurityAndUntrustedCode>
