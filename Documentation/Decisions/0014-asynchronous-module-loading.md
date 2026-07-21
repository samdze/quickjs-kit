# ADR 0014: Asynchronous module loading outside QuickJS callbacks

- Status: Accepted
- Date: 2026-07-21

## Context

QuickJS resolves and loads static modules through synchronous C callbacks.
Swift module sources may come from asynchronous stores, and blocking a Swift
executor inside the callback would undermine structured concurrency and risk
deadlock. No borrowed QuickJS pointer or value may survive a suspension.

Module normalization must also remain stable after QuickJS caches compiled
module identities. Swift-defined modules should not introduce a second binding
metadata or Promise implementation.

## Decision

QuickJS callbacks consume only actor-owned registered or preloaded source.
Static graph loading follows compile, discover, release, suspend, load,
register, and retry. A failed compile that identifies a missing dependency is
not published; all compile-only owned values are released before the runtime
actor awaits the loader. Requests for one canonical specifier share an async
loader task, and cancelling one waiter preserves work needed by other waiters.

The portable default resolver normalizes relative specifiers lexically against
their referrer. Bare and scheme-prefixed specifiers remain unchanged. Custom
resolution and loading become immutable when the first compilation begins.
Unknown dynamic imports must be registered or preloaded because their native
callback cannot suspend.

Swift modules use QuickJS native modules internally and finalize the same
canonical binding drafts used by globals and object exports with a module
location. Definition validates and encodes all members before publication and
rolls provisional bindings back on failure.

## Consequences

Module loading composes with Swift concurrency without a hidden thread, queue,
or lock, and no C state crosses suspension. QuickJS preserves native module
identity, cycles, re-exports, top-level await, and evaluation-once semantics.
Published Swift modules remain alive until runtime teardown because QuickJS
does not provide a safe public module-unload boundary.

Built-in filesystem, network, package-manager, and JSON loaders remain outside
the core package; applications provide policy through the loader closure.
