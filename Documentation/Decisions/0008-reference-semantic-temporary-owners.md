# ADR 0008: Reference-semantic temporary value owners

- Status: Accepted
- Date: 2026-07-15

## Context

ADR 0002 selected noncopyable RAII owners for temporary +1 QuickJS values. That
model is ideal for a single lexical evaluation result, but Swift's copyable
`Encoder` and `Decoder` container protocols require temporary ownership to move
through existential containers, child coders, closures, and argument arrays.
Copying the raw QuickJS value would still risk double frees.

## Decision

Each +1 temporary QuickJS value is immediately placed in one internal `final`
RAII owner object with immutable raw value and context storage. Swift references
to that owner may be shared while a conversion or call is active; the owner
performs exactly one `JS_FreeValue` when its last reference is destroyed.

Passing ownership to a consuming QuickJS API always uses `JS_DupValue`, leaving
the owner balanced. Persistent registry entries use a distinct owner type so
their client counts and canonical IDs cannot be confused with temporary scope.
Neither owner is `Sendable` or exposed outside the actor-isolated engine layer.

## Consequences

Temporary values can participate safely in standard `Codable` container
machinery without raw-value copies or manual cleanup branches. This introduces
one Swift owner allocation per live temporary; profiling may later justify an
actor-scoped value arena, provided it preserves the same duplication and
teardown rules. ADR 0002's narrow C boundary and values-before-context teardown
remain unchanged; only its temporary owner representation is amended.
