# Errors and Diagnostics

QuickJSKit keeps JavaScript failures and Swift conversion failures distinct so
callers can respond at the right boundary.

## Handle JavaScript errors

``JavaScriptError`` preserves a stable error kind, JavaScript constructor name,
message, stack, and source URL when available:

```swift
do {
    let _: Int = try await runtime.evaluate(
        "missing.value",
        sourceURL: "Scripts/example.js"
    )
} catch let error as JavaScriptError {
    print(error.kind)
    print(error.message)
    print(error.stack ?? "No stack")
}
```

Kinds distinguish syntax, exceptions, runtime failures, timeouts,
cancellation, module failures, interruption, pending synchronous Promises,
conversion, resource limits, and invariant failures.

## Handle conversion failures

Use `EncodingError` and `DecodingError` for shape, range, and coding-path
failures. These errors mean that JavaScript executed, but the value did not
match the requested Swift representation.

```swift
do {
    let _: Int = try await runtime.evaluate("({ value: 'not an integer' })")
} catch let error as DecodingError {
    print(error)
}
```

Do not catch every failure as a JavaScript exception: preserve the distinction
when presenting diagnostics or deciding whether to retry.

## Promise rejection reporting

Install an unhandled rejection handler for background JavaScript work. The
handler runs on the runtime actor and should return quickly; launch a separate
Swift task for slow reporting.

## Runtime recovery

Timeouts, interruptions, and cancellation leave the runtime usable after the
operation returns. Still treat resource-limit failures and loader failures as
application-level events, and record the source URL and operation that caused
them.

## Related guides

- <doc:EvaluationAndConversion>
- <doc:CancellationAndExecutionControl>
- <doc:SecurityAndUntrustedCode>
