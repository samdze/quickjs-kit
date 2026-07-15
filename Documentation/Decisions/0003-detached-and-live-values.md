# ADR 0003: Separate detached values from live handles

- Status: Accepted
- Date: 2026-07-15

## Context

Primitives and decoded Swift models are naturally `Sendable`, while JavaScript
objects have identity, mutable state, runtime affinity, and manual C ownership.
Treating both as raw pointer wrappers would undermine the concurrency model.

## Decision

`JavaScriptValue` is an opaque Swift value with detached primitive storage in
Phase 1. Live objects, arrays, and functions will be runtime-bound public handle
types whose operations delegate to their owning runtime actor via registry IDs.
Typed evaluation may decode directly to Swift without creating a public live
handle.

## Consequences

Primitive results cross actors cheaply and safely. Live operations remain
asynchronous across isolation. The opaque struct can evolve without exposing an
exhaustive storage enum or a C representation.
