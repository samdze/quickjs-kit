# ADR 0009: Detached binding descriptions and runtime trampolines

- Status: Accepted; refines ADR 0004
- Date: 2026-07-15

## Context

Runtime invocation needs executable Swift captures, while TypeScript, IDE
artifacts, documentation, and future macros need deterministic metadata that is
safe to inspect without a running engine. Mixing both concerns would retain
application objects in tooling and make declaration generation depend on
runtime state.

## Decision

Every typed binding has a detached `BindingDescription` containing its
location, names, Swift type shapes, effects, documentation, and deterministic
order. The actor-owned registry pairs that description with a separate
type-erased invocation thunk.

Swift parameter packs construct typed decoding and invocation thunks without a
public variadic callback API. One global C trampoline obtains a runtime-local
opaque bridge and binding ID. It duplicates borrowed arguments before direct
decoding and duplicates owned results when returning them to QuickJS.
The trampoline temporarily pauses QuickJS's JavaScript stack accounting while
the non-reentrant Swift thunk runs, then restores the exact configured limit
before returning. This prevents generic host conversion frames from being
misclassified as recursive JavaScript stack usage.

## Consequences

Runtime registration and future generators share one metadata model without
making closures or QuickJS values `Sendable`. Handwritten exports and future
macros can emit the same descriptions. The trampoline is a small unsafe boundary
and must retain borrowed-ownership and teardown tests.
