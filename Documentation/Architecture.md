# QuickJSKit Architecture

## Scope

This document defines the intended stable boundaries and the Phase 1 validation
slice. It is not a claim that every described capability is implemented.

## System shape

```text
Swift tasks
    │ await
    ▼
JavaScriptRuntime actor
    ├── public evaluation and future registration/module APIs
    ├── future binding metadata and live-value registry
    └── QuickJSEngine (internal, non-Sendable)
            ├── one JSRuntime heap
            ├── one or more JSContext realms
            ├── noncopyable owned JSValue scopes
            └── CQuickJS
```

An actor, not a lock, is the synchronization boundary. It owns the complete
QuickJS object graph. Actors serialize calls but can move between OS threads, so
every top-level engine entry first calls `JS_UpdateStackTop`; this is required
for QuickJS's native stack-overflow check. Public detached values and errors are
ordinary `Sendable` Swift data. A future live object handle will contain an
opaque registry identity and a reference to its runtime actor; it will never
contain a raw value.

## Phase 1 data flow

1. `JavaScriptRuntime` creates `QuickJSEngine` inside its initializer.
2. The engine creates `JSRuntime`, applies limits, then creates `JSContext`.
3. `evaluate` enters through actor isolation, refreshes QuickJS's stack top for
   the current executor thread, and calls `JS_Eval` directly.
4. The +1 result is immediately wrapped in a noncopyable RAII owner.
5. An exception is copied into `JavaScriptError`; a primitive is copied into
   `JavaScriptValue`; unsupported live values fail explicitly.
6. RAII frees the result on every return and throw path.
7. Runtime teardown frees the context before the runtime.

There is no dispatch queue, global registry, hidden worker, JSON round trip, or
public C declaration.

## Stable conceptual boundaries

### Runtime ownership

One public runtime actor maps to one QuickJS runtime heap. Multiple realms share
that same actor because QuickJS contexts in a runtime share objects and cannot
be accessed concurrently. Independent runtime actors can run concurrently.

### Detached and live values

Detached values are copied Swift primitives or models and can cross actors at
normal Swift cost. Live values preserve JavaScript identity and must delegate
operations back to their owning runtime. This distinction avoids the false
safety of marking a pointer wrapper `Sendable`.

Phase 1 deliberately returns only detached primitives. Phase 2 can extend the
opaque `JavaScriptValue` storage and introduce `JavaScriptObject`,
`JavaScriptArray`, and `JavaScriptFunction` handles without changing runtime
ownership.

### Conversion

Conversion will be a direct, type-directed operation executed inside the actor.
Primitive and collection paths traverse QuickJS values without serialization.
Binary data maps to `ArrayBuffer`/typed arrays. `Date` and `URL` have explicit
representations. `Codable` integration will traverse encoder/decoder containers
against JavaScript values; JSON remains an opt-in interoperability format.

Integer conversions must detect precision and range loss. JavaScript `number`
and `bigint` are distinct inputs. Conversion failure is a structured Swift error
rather than silent truncation.

### Binding metadata

A future internal `BindingDescription` is the shared source of truth for:

- runtime registration and invocation;
- parameter/result conversion;
- sync, throws, async, and async-throws semantics;
- documentation;
- TypeScript declaration rendering;
- IDE workspace artifacts;
- macro-generated registrations.

Invocation thunks may contain runtime behavior, but declaration generation uses
pure, detached metadata and is deterministic. Handwritten APIs and macros both
produce the same descriptions.

### Async and promises

QuickJS native promises remain the JavaScript abstraction. A Swift async binding
returns a pending promise, launches structured Swift work, and re-enters the
runtime actor to settle it. JavaScript promise results are driven by QuickJS's
pending-job queue and exposed as Swift async operations.

The runtime tracks outstanding jobs and continuation ownership. Cancellation
requests the corresponding bridge operation and rejects/abandons settlement
according to a documented policy. No JavaScript operation runs outside the
runtime actor.

### Modules

Module name normalization, resolution, source loading, and evaluation are
separate internal responsibilities but initially remain in the main Swift
target. Loaders return owned source plus an identity. The architecture reserves
an async preload/resolution layer because the immediate QuickJS loader callback
is synchronous. Async module loading must not block an executor while waiting.

### Interrupts and limits

Memory and stack limits are runtime configuration. Deadlines and cancellation
will use the QuickJS interrupt handler. Because that handler is a C callback
during engine execution, it may read only a narrow thread-safe cancellation or
deadline token and return an interrupt decision. Error translation happens back
in the actor-isolated Swift operation.

## Error model

`JavaScriptError` is an extensible struct containing a category and diagnostic
fields. It copies JavaScript name, message, stack, and source identity while the
exception value is alive. Planned timeout and cancellation categories already
have stable semantic homes. C error codes and exception sentinels never escape
the engine boundary.

## Platform strategy

The main target uses portable Swift. The C target vendors the upstream core
engine but not `quickjs-libc`, whose `std` and `os` modules introduce unnecessary
host dependencies. Platform-specific services such as clocks or file-backed
module sources will be small internal adapters. Unsupported capabilities remain
present in public API and report a Swift capability error.

Swift Package Manager declares Apple minimum deployment versions. Linux,
Windows, and Android are supported through their Swift toolchains and require
CI build validation as the implementation grows.

## Performance strategy

- Actor isolation provides serialization without a second queue or lock.
- Calls cross one Swift-to-C boundary for evaluation.
- Temporary C values use stack-scoped noncopyable owners.
- Primitive conversion copies only the resulting Swift data.
- Live values will use stable registry IDs and avoid repeated encode/decode.
- Binding invocation favors generated or generic static thunks over reflection
  and dynamic dispatch.
- TypeScript generation operates off metadata and never starts QuickJS.

Benchmarks will cover creation, evaluation, conversion, callbacks, promises, and
module loading before performance-specific abstractions are accepted.

## Key decisions

| Decision | Choice | Consequence |
| --- | --- | --- |
| Serialization | One actor per QuickJS runtime | Correct concurrent callers; API operations require `await` across isolation |
| C boundary | Internal import and one Swift engine layer | C is invisible publicly; unsafe review surface stays small |
| Ownership | Noncopyable RAII plus actor-owned future registry | Deterministic frees; no public manual ownership |
| Values | Detached `Sendable` values vs runtime-bound live handles | Safe cross-actor use without pretending pointers are thread-safe |
| Bindings | One canonical description model | Runtime, TypeScript, docs, IDE files, and macros cannot drift |
| Portability | Portable core; tiny internal platform adapters | Identical public API on all supported platforms |
| QuickJS distribution | Pinned upstream source in a C target | Reproducible builds and easy auditing at the cost of repository size |

Detailed rationale is retained in `Documentation/Decisions`.
