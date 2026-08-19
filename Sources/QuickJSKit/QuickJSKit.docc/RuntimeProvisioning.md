# Runtime Provisioning

Use ``JavaScriptRuntimeProvisioner`` when a template should prepare runtimes
before application demand arrives.

## Create a provisioner

```swift
let provisioner = try JavaScriptRuntimeProvisioner(
    template: template,
    warmCapacity: 4
)
try await provisioner.warmUp()

let runtime = try await provisioner.makeRuntime()
```

The provisioner creates runtimes from a ``JavaScriptRuntimeTemplate`` and keeps
up to the configured ready capacity. `warmUp()` waits for the requested
capacity to be ready or reports provisioning failure.

## Understand transfer semantics

The returned runtime leaves the provisioner permanently. It is not reset,
returned, or reused. Every runtime has its own heap, context, module graph,
Promise queue, globals, limits, and failure domain.

Replenishment creates another independent runtime. The provisioner never
shares live JavaScript values between consumers.

## Observe and shut down

Inspect ``JavaScriptRuntimeProvisioner/status`` to distinguish ready,
provisioning, and waiting work. `shutdown()` affects pending provisioning and
runtimes that have not yet been transferred; it does not reclaim runtimes
already handed to callers.

## Choose the right abstraction

Use a template alone when runtime creation latency is acceptable or demand is
unpredictable. Use a provisioner when predictable acquisition latency is worth
the memory required for ready runtimes.

See <doc:RuntimeTemplates> for template construction and
<doc:PerformanceAndResourceUsage> for measurement.
