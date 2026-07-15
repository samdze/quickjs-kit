# ADR 0006: Canonical actor-owned live-value registry

- Status: Accepted
- Date: 2026-07-15

## Context

JavaScript objects, arrays, and functions have identity and mutable state. They
must remain alive beyond the evaluation that produced them, but a public Swift
handle cannot safely store a QuickJS value or free one from an arbitrary
deinitializer executor. Observing the same JavaScript object more than once must
also preserve equality and hashing.

## Decision

Each `JavaScriptRuntime` actor owns a canonical registry for its QuickJS heap.
The registry maps internal object addresses to monotonic IDs and retains one
duplicated QuickJS value per live entry. Repeated observation increments a
client count and reuses the ID.

Public `JavaScriptObject`, `JavaScriptArray`, and `JavaScriptFunction` values
share a pointer-free lifetime token containing the runtime and registry ID. The
token schedules release through the owning actor when its last Swift reference
is destroyed. Equality and hashing combine runtime identity with the canonical
ID. ID zero is reserved for the global object and is not retained persistently.

All registry values are released before context destruction, and the context is
destroyed before the runtime. Every registry entry point refreshes QuickJS's
stack top through the same engine-entry convention as evaluation.

## Consequences

Live handles are `Sendable` without declaring C storage sendable. Their methods
are asynchronous across actor isolation and their lifetime retains the runtime.
Release is eventually actor-serialized rather than synchronously performed in
`deinit`. Object addresses remain entirely internal and are never treated as a
durable public identity. Multiple independent runtimes cannot exchange live
values and report a deterministic runtime error if attempted.
