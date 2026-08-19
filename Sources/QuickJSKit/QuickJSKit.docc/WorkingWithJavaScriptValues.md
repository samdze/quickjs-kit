# Working with JavaScript Values

Use live handles when JavaScript identity, mutation, or repeated calls matters.

## Inspect an object

```swift
let value: JavaScriptValue = try await runtime.evaluate("({ answer: 42 })")
if let object = value.objectValue {
    let answer: Int = try await object.value(
        forProperty: "answer",
        as: Int.self
    )
    let names = try await object.propertyNames()
    print(answer, names)
}
```

Typed property reads use the same direct conversion rules as typed evaluation.
If a property contains a native Promise, the typed read awaits it.

## Mutate an object

```swift
try await object.set(43, forProperty: "answer")
let updated: Int = try await object.value(
    forProperty: "answer",
    as: Int.self
)
```

Use encoded Swift values for snapshots, or assign another live value when
identity must be preserved. Values assigned to an object must belong to the
same runtime.

## Work with arrays

``JavaScriptArray`` exposes length, indexed reads and writes, sparse slots, and
append operations. Decode elements directly when the array represents data;
use live operations when JavaScript mutability is part of the behavior.

## Call functions

```swift
let functionValue: JavaScriptValue = try await runtime.evaluate("""
    (name => `Hello, ${name}`)
    """)
if let function = functionValue.functionValue {
    let greeting: String = try await function.call("Ada")
    print(greeting)
}
```

``JavaScriptFunction`` also supports heterogeneous encodable arguments,
explicit result types, an explicit `this` receiver, and raw live arguments.

## Identity and lifetime

Repeatedly observing the same JavaScript object in one runtime produces handles
with the same identity. A live handle is pointer-free and safe to pass between
Swift concurrency domains, but each operation is routed back to its owning
runtime actor. The handle also keeps that runtime alive.

Use a `Codable` snapshot instead of a live handle when data should outlive or
move between runtimes.

## Related guides

- <doc:RuntimeModel>
- <doc:EvaluationAndConversion>
- <doc:ErrorsAndDiagnostics>
