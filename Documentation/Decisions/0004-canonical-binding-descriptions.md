# ADR 0004: Canonical binding descriptions

- Status: Accepted; invocation storage refined by ADR 0009
- Date: 2026-07-15

## Context

Runtime bindings, TypeScript declarations, documentation, IDE workspaces, and
future macros describe the same exported Swift surface. Separate models would
drift and make synchronization unreliable.

## Decision

Registration APIs and future macros produce one canonical internal binding
description containing JavaScript identity, Swift/TypeScript type shapes,
documentation, and effects. As refined by ADR 0009, executable invocation
thunks are paired actor-owned records rather than part of the detached
description. Declaration and workspace generation operate deterministically on
descriptions and do not require a running QuickJS instance.

## Consequences

Handwritten and generated bindings share behavior. Metadata design must support
extension without becoming a public reflection system. This abstraction will be
introduced with the first function-registration feature, not prematurely in
Phase 1.
