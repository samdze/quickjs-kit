# ADR 0011: Explicit transactional exports

- Status: Accepted
- Date: 2026-07-15

## Context

Reflection cannot describe arbitrary Swift APIs reliably, actor isolation must
remain visible, and future macros need a stable lower-level export mechanism.
Publishing partially validated objects would also leave surprising global
state after an encoding or metadata failure.

## Decision

Object and actor export uses an explicit builder over `AnyObject & Sendable`.
Functions reuse canonical binding descriptions and typed thunks. Values are
encoded snapshots or same-runtime live values. The runtime validates and
encodes every member before publishing the global object.

Methods are read-only non-enumerable properties. Snapshot values are read-only
enumerable properties. The binding registry retains the root and closures;
explicit removal or runtime teardown owns lifecycle. No reflection or implicit
`deinit` unregistration is used.

## Consequences

Exported surfaces are deliberate, testable, and ready for future macros without
a second runtime pathway. Failure leaves the global object unchanged. Mutable
or computed properties require explicit methods until a later design addresses
their isolation and declaration semantics.
