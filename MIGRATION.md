# Pre-release Migration Notes

QuickJSKit has not published a compatibility release. These notes record
intentional source changes made while finalizing the first public API.

## Phase 9

Resource observability now describes every stable actor-owned resource:

```swift
let usage: JavaScriptResourceUsage = await runtime.resourceUsage()
```

Replace:

- `JavaScriptMemoryUsage` with `JavaScriptResourceUsage`;
- `runtime.memoryUsage()` with `runtime.resourceUsage()`.

The new value retains allocator fields and adds host-object and pending-host-call
counts and limits. No deprecated aliases remain.

`JavaScriptRuntime.Configuration()` is still unlimited. Use a mutable copy of
`.restricted` when adopting defensive defaults:

```swift
var configuration = JavaScriptRuntime.Configuration.restricted
configuration.maximumPendingHostCallCount = 64
let runtime = try JavaScriptRuntime(configuration: configuration)
```
