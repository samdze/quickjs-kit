# ADR 0015: Consolidated execution and reusable binding definitions

- Status: Accepted
- Date: 2026-07-21

## Context

The first four phases established the correct public capabilities, but some
internal paths still prepared QuickJS independently, binding construction was
duplicated across globals and builders, module reads had a separate Promise
implementation, and async definitions captured their installation runtime.
Those differences increased code size and prevented one definition from being
installed safely into many independent runtimes.

Synchronous module APIs also represented only the subset of modules requiring
neither asynchronous loading nor external top-level-await progress. Their
behavior duplicated the complete asynchronous path while being less capable.

## Decision

Every C-touching operation enters one outer `withEngineEntry` scope. The scope
owns stack-top refresh, active execution state, interruption translation, and
the requested job checkpoint. Low-level engine methods assume that scope and
never prepare themselves independently.

Globals, object exports, and Swift modules use one `JavaScriptExportBuilder`
and one reusable `BindingDefinition`. A definition contains Sendable Swift
captures and invocation logic but no runtime identity or QuickJS state. During
installation it becomes a `BoundFunction` by receiving its JavaScript location,
deterministic order, and a settlement callback for the destination runtime.
Only `RegisteredBinding` contains per-runtime lifecycle state.

All typed root reads use one Promise pipeline. It marks observation before the
checkpoint, transforms immediate results, installs one pending waiter, and
balances observation on every exit. Cancelling a waiter affects only that
waiter. Producer cancellation is explicit through binding removal with
`cancellingInFlight: true`.

Scoped actor access is named `run`. Modules expose only asynchronous import and
evaluation. Swift modules use `JavaScriptExportBuilder`; the redundant module
builder and synchronous module paths are removed without compatibility shims.

## Consequences

Stack refresh and checkpoint ownership are auditable from one boundary. Promise
semantics no longer depend on which API produced the root value. The binding
implementation is smaller while retaining exact Swift effect metadata.

Reusable definitions can be installed into multiple independent runtime actors
without settling a Promise through the wrong heap. This reserves a future
immutable runtime-template API. Such templates will remain declarative and may
use QuickJS bytecode only as a private, disposable, exact-version cache; source
remains canonical, live values never cross heaps, and evaluated heap snapshots
are not part of the design.

Removing synchronous modules is source-breaking before the first tagged
release. Callers use asynchronous module APIs and retain synchronous typed
script evaluation inside `run` when immediate execution is genuinely useful.
