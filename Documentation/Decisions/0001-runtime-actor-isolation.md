# ADR 0001: Runtime actor isolation

- Status: Accepted
- Date: 2026-07-15

## Context

QuickJS runtimes and their contexts cannot be used concurrently. A wrapper must
make correct access natural under Swift strict concurrency without relying on
callers to coordinate queues or locks.

## Decision

`JavaScriptRuntime` is an actor and the exclusive owner/executor for one QuickJS
runtime heap, all of its contexts, pending jobs, callbacks, and live values.
Independent runtimes use independent actors. The low-level engine is not
`Sendable`. Because actor executors are not OS-thread-affine, every top-level
entry calls QuickJS's `JS_UpdateStackTop` before other engine work.

## Consequences

Cross-isolation operations use `await`, even where QuickJS evaluation itself is
synchronous. The package adds no hidden queue. Multiple runtimes can make
parallel progress. Future contexts are handles into the same runtime actor, not
actors of their own. New engine entry points must preserve the stack-top refresh;
actor serialization alone is insufficient for QuickJS stack checks.
