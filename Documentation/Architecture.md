# QuickJSKit Architecture

## Scope

This document describes the implemented Phase 2 architecture and the stable
boundaries reserved for later platform capabilities. Features identified as
future work are design constraints, not current API promises.

## System shape

```text
Swift tasks
    │ await
    ▼
JavaScriptRuntime actor
    ├── evaluation, globals, and runtime-bound codecs
    ├── live-value identity and lifetime coordination
    └── QuickJSEngine (internal, non-Sendable)
            ├── one JSRuntime heap and one JSContext realm
            ├── canonical actor-owned live-value registry
            ├── direct Encoder and Decoder containers
            ├── RAII owners for temporary and retained JSValue values
            └── CQuickJS
```

The actor, rather than a lock or dispatch queue, is the synchronization
boundary. It owns the complete QuickJS object graph. Swift actors can migrate
between operating-system threads, so each top-level engine entry refreshes
QuickJS's stack top before touching the engine.

The public API divides values into two categories:

- Detached values are Swift-owned primitives, `JavaScriptBigInt` values, and
  decoded models. They can cross actors without engine access.
- Live values are pointer-free object, array, and function handles. They retain
  their runtime and delegate every operation to its actor.

No public or `Sendable` stored property contains a C value or pointer.

## Evaluation data flows

Untyped evaluation preserves live identity:

1. `JavaScriptRuntime.evaluate` enters actor isolation.
2. `QuickJSEngine` refreshes the stack top and evaluates the source.
3. A +1 result enters an RAII owner immediately.
4. Primitives and BigInt are copied into detached Swift values.
5. Objects, arrays, and functions are looked up in the canonical registry.
6. The caller receives a `JavaScriptValue` containing a lifetime token and
   stable registry ID, never the engine address.

Typed evaluation avoids unnecessary registry traffic:

1. QuickJS evaluates into a temporary owned result.
2. The custom decoder traverses that result while it remains alive.
3. The temporary is freed after decoding succeeds or throws.
4. The caller receives the requested Swift value directly.

Execution and parsing failures remain `JavaScriptError`. Shape, range, and
coding failures are standard `DecodingError` values with complete coding paths.

## Live-value registry and ownership

The actor-owned registry maps the internal address of each QuickJS object to one
monotonic ID and one retained QuickJS value. Repeated observation of the same
object reuses that ID, so public equality and hashing preserve canonical
identity within a runtime. Runtime identity participates in equality to prevent
collisions between independent heaps.

A public handle shares an internal lifetime token. The token strongly retains
its runtime and schedules release by the runtime actor when its last Swift
reference disappears. The registry separately counts public tokens produced for
the same object. Release is idempotent, serialized, and never calls QuickJS from
an arbitrary deinitializer executor.

ID zero is reserved for the global object. It is acquired only for the duration
of each operation and therefore needs no persistent registry entry.

Teardown order is strict:

1. release every retained registry value;
2. destroy the context;
3. destroy the runtime.

Temporary +1 values and stored registry values use one immutable RAII owner per
QuickJS reference. Swift code may temporarily share that owner, but ownership of
the raw value is never copied.
Borrowed values are never freed unless first duplicated. Property setters pass
duplicates to consuming QuickJS APIs so the Swift owner remains balanced on
both success and failure paths.

## Direct conversion

`JavaScriptEncoder` and `JavaScriptDecoder` are `Sendable` value types bound to
one runtime. Their mutable configuration is local value state; executing a
codec operation enters the runtime actor. A codec may therefore safely move
between tasks while retaining runtime affinity.

The implementation conforms directly to Swift's `Encoder` and `Decoder`
container protocols against QuickJS values. It does not use JSON, property-list
serialization, or a package-defined intermediate tree.

The representation policy is:

- booleans, strings, and floating-point values require matching JavaScript
  primitive kinds and never use implicit coercion;
- integer encodes use `number` through ±(2^53−1) and `bigint` outside it;
- integer decodes are integral, lossless, safe-number checked, and destination
  range checked;
- `nil` encodes as `null`; missing properties, `null`, and `undefined` decode
  as absent optionals;
- Swift arrays and string-keyed dictionaries map to JavaScript arrays and
  plain objects;
- keyed decoding sees only own enumerable string properties, respecting
  `CodingKeys` and excluding inherited, non-enumerable, and symbol properties;
- `Data` encodes as `Uint8Array` and decodes from array buffers, typed-array
  views, and arrays of valid bytes;
- `Date` encodes as JavaScript `Date` and decodes from a valid date object,
  finite Unix milliseconds, or an ISO-8601 string;
- `URL` encodes as a string and decodes from a string or an object with a string
  `href` property;
- `JavaScriptBigInt` carries arbitrary-size integers as canonical decimal text
  outside a runtime and maps to native `bigint` inside it.

The configurable nesting limit defaults to 64 keyed or unkeyed containers. It
bounds recursive conversion, including cyclic JavaScript object graphs, and
reports the path at which traversal exceeded the limit. Reference sharing is
not preserved by value-based `Codable` conversion.

## Live operations

`JavaScriptObject` exposes typed and untyped property reads, encoded and live
value writes, lookup, deletion, and own enumerable property names.
`JavaScriptArray` adds length, indexed access, mutation, sparse-slot behavior,
and append. `JavaScriptFunction` supports heterogeneous encodable parameter
packs, inferred or explicit decoded results, an explicit `this` receiver, and
raw `[JavaScriptValue]` arguments when preserving live identity matters.

Every operation validates runtime affinity before materializing a live value.
Cross-runtime use fails deterministically with `JavaScriptError` instead of
passing an invalid engine value.

## Stable future boundaries

### Binding metadata

A future internal `BindingDescription` will be the shared source of truth for
runtime registration, conversion thunks, documentation, TypeScript rendering,
IDE artifacts, and macro output. It is introduced with Swift function
registration, not retrofitted into the general value codec.

### Async and promises

QuickJS native promises remain the JavaScript abstraction. A Swift async binding
will create a pending promise, perform structured Swift work, and re-enter the
runtime actor to settle it. JavaScript promises returned to Swift will use the
QuickJS pending-job queue. Cancellation and continuation ownership belong to
the runtime actor.

### Modules

Module normalization, resolution, source loading, and evaluation remain
separate internal responsibilities. The synchronous QuickJS loader callback
will consume preloaded source so a future async loader never blocks a Swift
executor while waiting.

### Interrupts and resource controls

Memory and stack limits are current runtime configuration. Deadlines and task
cancellation will use a narrow state token readable from QuickJS's synchronous
interrupt callback. The callback will only decide whether to interrupt; error
translation remains actor-isolated.

## Error model

`JavaScriptError` is an extensible, detached struct containing a category and
copied diagnostics. Syntax, thrown-value, runtime-affinity, engine-resource,
and internal failures have stable semantic homes. C error codes and exception
sentinels never cross the engine boundary.

Conversion deliberately uses two error families. JavaScript exceptions and
runtime failures are `JavaScriptError`; ordinary `Codable` representation,
range, and nesting failures are `EncodingError` or `DecodingError`.

## Platform strategy

The Swift target uses portable Foundation and standard Swift. The C target
vendors the upstream core engine but excludes `quickjs-libc`, whose `std` and
`os` modules add host-specific dependencies. Platform services such as clocks
or file-backed module sources will be small internal adapters. Unsupported
capabilities remain source-compatible in the public API and report Swift errors.

Swift Package Manager declares Apple deployment minimums. Linux, Windows, and
Android use their native Swift toolchains and remain equal API targets.

## Performance strategy

- Actor isolation provides serialization without a second queue or lock.
- Typed evaluation decodes the temporary result without registry insertion.
- Codecs traverse QuickJS values directly without JSON or an intermediate tree.
- Detached primitives copy only their Swift representation.
- Canonical live IDs avoid repeated encode/decode and preserve identity.
- QuickJS receives source and strings with explicit UTF-8 byte lengths.
- Binding invocation will favor generated or generic static thunks over
  reflection and dynamic dispatch.
- TypeScript generation will operate on detached metadata without starting
  QuickJS.

Benchmarks will cover creation, evaluation, conversion, callbacks, promises,
and module loading before performance-specific abstractions are accepted.

## Test architecture

`Tests/QuickJSKitTests/PublicAPI` imports only `QuickJSKit`. Its sentence-style
tests are complete consumer examples for typed evaluation, globals, live
values, codecs, Foundation types, errors, depth limits, and concurrency. README
and future DocC snippets must have an equivalent executable example there.

`Tests/QuickJSKitTests/Internal` uses `@testable` only for registry identity,
lifetime, teardown, and other invariants that public behavior cannot observe.
Sanitizers and warning-as-error builds are release gates, not optional cleanup.

## Key decisions

| Decision | Choice | Consequence |
| --- | --- | --- |
| Serialization | One actor per QuickJS runtime | Concurrent callers are safe; cross-isolation operations use `await` |
| C boundary | Internal import and one engine layer | Public symbol graphs contain no C declarations |
| Ownership | RAII values plus actor-owned canonical registry | Deterministic frees with no public manual ownership |
| Values | Detached data and pointer-free live handles | Swift concurrency safety without pretending pointers are `Sendable` |
| Conversion | Runtime-bound direct Encoder/Decoder | Native representations and coding paths without JSON |
| Integer policy | Safe `number`, otherwise `bigint` | Signed and unsigned integers remain lossless |
| Bindings | One future canonical description model | Runtime, TypeScript, docs, IDE files, and macros can stay synchronized |
| Portability | Portable core and tiny future adapters | Identical public API across supported platforms |
| Distribution | Pinned upstream source in a C target | Reproducible builds and auditable upgrades |

Detailed rationale is retained in `Documentation/Decisions`.
