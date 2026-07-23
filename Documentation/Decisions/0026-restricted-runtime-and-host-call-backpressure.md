# ADR 0026: Restricted runtime defaults and host-call backpressure

- Status: Accepted
- Date: 2026-07-23

## Context

QuickJS memory, stack, and active execution limits did not bound live Swift host
objects or asynchronous JavaScript-to-Swift operations. A script could create
large numbers of native Promise capabilities and Swift tasks while QuickJS was
not actively executing. The memory-only usage name also no longer described the
runtime's observable resources.

## Decision

Keep the default configuration unrestricted for general-purpose compatibility
and add a customizable `restricted` starting point. It limits QuickJS memory to
64 MiB, JavaScript stack to 512 KiB, active execution to one second, live host
objects to 1,024, and pending asynchronous host calls to 256.

Check pending-call capacity inside the runtime actor before allocating a Promise
capability, operation identifier, or producer task. A rejected call creates no
tracked work and becomes JavaScript `RangeError`. Every admitted operation owns
one slot until its existing exactly-once settlement or teardown path removes
it. Synchronous callbacks are not counted.

Rename memory-only observability to `JavaScriptResourceUsage` and include stable
allocator, host-object, and pending-call counts and limits. Do not expose
QuickJS-specific diagnostic counters.

## Consequences

Applications can apply consistent defensive defaults and observe the resources
QuickJSKit itself owns. Admission remains race-free because it uses the existing
runtime actor and Promise registry; no semaphore, lock, queue, or parallel task
registry is introduced.

The restricted preset is not an operating-system sandbox. QuickJS and exported
Swift capabilities still execute in-process. Applications handling hostile code
must use process isolation and a minimal allowlisted host API.
