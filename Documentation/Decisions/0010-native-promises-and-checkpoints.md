# ADR 0010: Native promises and actor-owned checkpoints

- Status: Accepted
- Date: 2026-07-15

## Context

Swift async functions and JavaScript promises have compatible suspension and
failure semantics, but QuickJS jobs are explicit and its promise capabilities
use manual ownership. A separate host future abstraction would fragment the API
and break JavaScript expectations.

## Decision

Async bindings return native QuickJS promises. The runtime actor owns promise
capabilities, producer tasks, host waiters, provenance, and settlement state.
Pending jobs drain to exhaustion after every outermost engine operation and
settlement. Typed root reads automatically await native promises; raw reads
return immediately and mark the promise host-observed. Thenables are not
assimilated by host decoding.

Host waiter cancellation normally removes only that waiter. Direct Swift-origin
promises additionally cancel their producer and reject the shared promise.
Unhandled rejections are reported once after a full checkpoint, excluding
same-checkpoint handlers and host-observed promises.

## Consequences

JavaScript retains native Promise behavior and Swift callers use ordinary
`async throws`. Async bindings may re-enter the actor after suspension. Sync
callbacks remain nested in the current QuickJS call and cannot re-enter.
Teardown must cancel producers and resume continuations exactly once before
freeing capabilities or the context.
