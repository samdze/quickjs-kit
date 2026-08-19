# Performance and Resource Usage

Measure the workload before trading away isolation, deterministic cleanup, or
clear ownership.

## Avoid repeated parsing

Use ``JavaScriptProgram`` when one global script is evaluated repeatedly or in
several runtimes:

```swift
let bootstrap = JavaScriptProgram(
    "globalThis.answer = 20 + 22",
    sourceURL: "Scripts/bootstrap.js"
)

try await runtime.prepare(bootstrap)
try await runtime.evaluate(bootstrap)
```

Templates can prepare programs once and use their canonical source as a
portable fallback for each runtime.

## Reuse definitions, not heaps

``JavaScriptRuntimeTemplate`` reuses detached bindings, modules, schemas, and
private compile artifacts. It never shares a mutable heap or live value. Use
``JavaScriptRuntimeProvisioner`` when runtime creation latency should be moved
ahead of demand.

## Choose value or identity semantics

Typed `Codable` conversion is the direct value path and is usually the clearest
choice for snapshots. Live objects, arrays, functions, modules, and host
objects add registry lifetime and identity costs. Retain a
``JavaScriptFunction`` when calling the same function repeatedly.

## Observe resources

```swift
let before = await runtime.resourceUsage()
_ = try await runtime.evaluate("Array.from({ length: 1000 }, (_, i) => ({ i }))")
let after = await runtime.resourceUsage()
await runtime.collectGarbage()
```

``JavaScriptResourceUsage`` reports allocation, heap, host-object, and pending
host-call information. Use it with representative workloads rather than
microbenchmarks alone.

## Related guides

- <doc:RuntimeTemplates>
- <doc:RuntimeProvisioning>
- <doc:SecurityAndUntrustedCode>
