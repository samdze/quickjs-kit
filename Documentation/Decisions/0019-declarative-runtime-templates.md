# ADR 0019: Declarative runtime templates and independent heaps

- Status: Accepted
- Date: 2026-07-21

## Context

Applications may need many runtimes with the same globals, Swift exports,
modules, loader, documentation, and TypeScript environment. Repeating immediate
registration is verbose and reparses identical source. Sharing contexts in one
QuickJS runtime would still serialize execution and would share limits, jobs,
module identity, and failure state. Cloning evaluated heaps or resetting an
arbitrarily used runtime cannot provide a clear ownership or correctness
contract.

Some applications also need independent Swift actors or objects behind each
runtime, while others intentionally share a `Sendable` service. Tooling must be
available before a per-runtime factory or QuickJS engine exists.

## Decision

`JavaScriptRuntimeTemplate` is an immutable, `Sendable`, declarative
provisioning plan. Every `makeRuntime()` creates one independent `JSRuntime`,
`JSContext`, actor, registry, job queue, module graph, and resource-limit domain.
Templates store reusable binding and export definitions, source modules,
loaders, and detached environment metadata, never live QuickJS state.

Static definitions may capture shared `Sendable` state. Per-runtime state uses
one async-throwing root factory plus root-aware builders for globals, object
exports, and Swift modules. The root is a Swift-only function parameter and is
excluded from JavaScript arity and tooling metadata. Factories run sequentially
in declaration order for one creation; independent creations may run
concurrently.

Template construction validates the declarative surface. Runtime creation
returns only after publication completes. Failure or cancellation discards the
partial runtime and releases created roots. Runtime-bound `JavaScriptValue`
exports are rejected because they cannot cross heaps.

QuickJSKit does not provide a pool, lease, reset, batch-creation, hidden queue,
or worker abstraction. Applications compose `makeRuntime()` with Swift task
groups and own capacity and backpressure policy.

## Consequences

One definition path now serves immediate runtime registration, templates,
TypeScript generation, and future macros. Template descriptions can generate
editor workspaces without allocating QuickJS or invoking application factories.

Independent heaps cost more memory than shared contexts, but preserve true
parallel progress, isolation, per-instance limits, and deterministic teardown.
Pooling can be added by applications that know when their own environment is
safe to reuse; QuickJSKit does not claim a general reset invariant it cannot
enforce.
