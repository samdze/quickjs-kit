# ADR 0004: Canonical binding descriptions

- Status: Accepted
- Date: 2026-07-15

## Context

Runtime bindings, TypeScript declarations, documentation, IDE workspaces, and
future macros describe the same exported Swift surface. Separate models would
drift and make synchronization unreliable.

## Decision

Future registration APIs and macros will produce one canonical internal binding
description containing JavaScript identity, Swift/TypeScript type shapes,
documentation, effects, and an invocation thunk. Declaration and workspace
generation operate deterministically on detached descriptions and do not require
a running QuickJS instance.

## Consequences

Handwritten and generated bindings share behavior. Metadata design must support
extension without becoming a public reflection system. This abstraction will be
introduced with the first function-registration feature, not prematurely in
Phase 1.
