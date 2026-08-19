# Evaluation and Conversion

QuickJSKit converts directly between JavaScript values and Swift's `Codable`
types. JSON is not used as an intermediate representation.

## Evaluate into Swift

```swift
struct Settings: Codable, Sendable {
    let enabled: Bool
    let tags: [String]
}

let settings: Settings = try await runtime.evaluate("""
    ({ enabled: true, tags: ["stable"] })
    """)
```

Typed evaluation decodes the temporary JavaScript result before releasing it.
It is the simplest choice when the result is a value snapshot.

## Encode and decode explicitly

Use the runtime-bound ``JavaScriptEncoder`` and ``JavaScriptDecoder`` when a
value is exchanged outside evaluation:

```swift
let encoded = try await runtime.encoder.encode(settings)
let decoded = try await runtime.decoder.decode(
    Settings.self,
    from: encoded
)
```

The codecs are `Sendable` configuration values, but their operations retain
affinity to the runtime that created them.

## Supported representations

- Swift booleans, strings, and numbers map to corresponding JavaScript
  primitives.
- Integers use `Number` while exact and native `BigInt` outside the safe
  `Number` range.
- Optionals encode as `null`; missing properties, `null`, and `undefined`
  decode as `nil` for optional destinations.
- Arrays and string-keyed dictionaries map to JavaScript arrays and objects.
- `Data` maps to `Uint8Array`.
- `Date` maps to JavaScript `Date`.
- `URL` maps to a string.
- ``JavaScriptBigInt`` preserves arbitrary-size integer values.

Conversion is value-based. It does not preserve reference sharing between
`Codable` models. Use <doc:WorkingWithJavaScriptValues> when identity matters.

## Conversion failures

Shape and range failures use Swift `EncodingError` or `DecodingError` with a
coding path. JavaScript parsing and execution failures use ``JavaScriptError``.
Neither category silently coerces an incompatible value.

```swift
do {
    let count: Int = try await runtime.evaluate("missing.value")
    print(count)
} catch let error as JavaScriptError {
    print(error.message)
    print(error.stack ?? "")
}
```

## Recursive data

The codecs enforce a configurable nesting limit. This bounds deeply nested or
cyclic JavaScript structures and reports the coding path where the limit is
exceeded.

## Related guides

- <doc:RuntimeModel>
- <doc:WorkingWithJavaScriptValues>
- <doc:ErrorsAndDiagnostics>
