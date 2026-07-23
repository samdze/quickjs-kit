# Conversions and Errors

Move values directly between Swift and JavaScript without an intermediate JSON
document.

## Canonical representations

QuickJSKit maps Swift primitives, optionals, arrays, string-keyed dictionaries,
`Data`, `Date`, `URL`, and `Codable` models directly. Integers use JavaScript
`Number` when exact and `BigInt` otherwise. `Data` uses `Uint8Array`, and `Date`
uses JavaScript `Date`.

```swift
struct Settings: Codable, Sendable, Equatable {
    let enabled: Bool
    let tags: [String]
}

let runtime = try JavaScriptRuntime()
let settings = Settings(enabled: true, tags: ["stable"])
let value = try await runtime.encoder.encode(settings)
let decoded = try await runtime.decoder.decode(Settings.self, from: value)
```

Encoding and decoding errors retain a complete `codingPath`. Conversion is
value-based and does not preserve reference sharing between Codable models.
Live ``JavaScriptObject`` handles preserve JavaScript identity when identity is
required.

## Handle failures

Parsing and JavaScript execution failures use ``JavaScriptError`` and preserve
the JavaScript name, message, source, and stack when available. Shape failures
use Swift `EncodingError` or `DecodingError`.

```swift
do {
    let count: Int = try await runtime.evaluate("missing.value")
    print(count)
} catch let error as JavaScriptError {
    print(error.message)
    print(error.stack ?? "")
}
```

Cancellation, execution timeout, custom interruption, module failures, pending
synchronous Promises, and resource limits have distinct error kinds.
