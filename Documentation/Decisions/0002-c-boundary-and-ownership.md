# ADR 0002: Narrow C boundary and deterministic ownership

- Status: Accepted
- Date: 2026-07-15

## Context

QuickJS uses reference-counted `JSValue` values and manually destroyed runtimes,
contexts, strings, and atoms. Copyable pointer wrappers can leak or double free,
especially across throws and concurrency boundaries.

## Decision

Only the internal runtime layer imports `CQuickJS`. Every +1 temporary value is
immediately moved into a noncopyable RAII owner. Long-lived values will reside in
an actor-owned registry keyed by stable IDs. Teardown order is values, contexts,
then runtime. Public API contains no C declaration or ownership operation.

## Consequences

Unsafe review is concentrated in one directory and cleanup is lexical. A live
public handle cannot directly free its value during arbitrary-executor `deinit`;
the registry/lifetime-token design must arrange actor-owned reclamation.
