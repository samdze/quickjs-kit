# ADR 0013: Scoped isolated runtime access

- Status: Superseded in naming by ADR 0015
- Date: 2026-07-21

## Context

Applications sometimes need several immediate JavaScript operations without
repeated actor hops, and synchronous host code needs a safe way to use results
that cannot require external asynchronous progress. A blocking facade, hidden
serial queue, worker thread, or second runtime type would duplicate isolation
and create deadlock or ownership risks.

Swift isolated closure parameters can expose the actor's existing synchronous
surface directly while preserving compiler-checked isolation. They can also
support asynchronous workflows without pretending suspension is atomic.

## Decision

`JavaScriptRuntime.perform` has two overloads. The synchronous overload accepts
a non-suspending closure with an `isolated JavaScriptRuntime` parameter and runs
as one actor turn. The asynchronous overload accepts an async isolated closure;
it may use ordinary `try await` and is actor-reentrant at every suspension.

A synchronous typed `evaluate` overload is available inside isolated code. It
drains immediately runnable QuickJS jobs and decodes an already fulfilled
Promise. A Promise that still needs external progress throws `.wouldSuspend`.
No thread is blocked and no event loop is spun.

## Consequences

Callers gain concise batching and natural async composition while
`JavaScriptRuntime` remains the only executor and ownership root. The async
overload is explicitly not transactional. Broad synchronous duplication of
object, array, global, function, and codec APIs is deferred until concrete use
cases justify the larger surface.
