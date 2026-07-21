# ADR 0012: Unified top-level execution scopes

- Status: Accepted
- Date: 2026-07-21

## Context

Evaluation, function invocation, Promise jobs, callbacks, and module execution
all enter QuickJS. Independently preparing these paths would duplicate stack
refresh, checkpoint, diagnostic, cancellation, and timeout behavior. Swift
actors serialize access but may resume on another operating-system thread, and
QuickJS measures stack limits from a thread-specific top-of-stack value.

QuickJS's interrupt hook is synchronous. It cannot await actor state or call
back into JavaScript, yet it must distinguish Swift task cancellation, an
operation deadline, and a custom host interruption request.

## Decision

The internal engine establishes one execution scope for every outermost period
of active JavaScript work. It refreshes the QuickJS stack top, resolves the
operation timeout, records the diagnostic source, installs nested-call state,
and owns interruption translation and the final microtask checkpoint. Nested
Swift callbacks inherit the active scope. Promise settlement after an async
Swift operation starts a new scope on the runtime actor.

The interrupt callback checks cancellation first, then the monotonic deadline,
then the host predicate. It only reads and records the current execution state.
Suspended Swift bindings, Promise waiting, and module loading occur outside the
scope, so execution timeouts measure active QuickJS work rather than wall-clock
latency.

## Consequences

All execution paths use the same precedence, cleanup, stack refresh, and error
mapping. Cancellation reports `.cancelled`, deadline expiry reports `.timeout`,
and a host predicate reports `.interrupted`. Immediate synchronous reads can
report `.wouldSuspend` without blocking. The runtime remains reusable because
scope state and pending interruption exceptions are cleared on every exit.

An execution timeout is intentionally not an end-to-end deadline. Callers that
need to bound asynchronous loading or Swift work use structured task
cancellation.
