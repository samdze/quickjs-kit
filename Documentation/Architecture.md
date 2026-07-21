# QuickJSKit Architecture

## Scope

This document describes the implemented Phase 5.1 architecture and the stable
boundaries reserved for later platform capabilities. Features identified as
future work are design constraints, not current API promises.

## System shape

```text
Swift tasks
    │ await
    ▼
JavaScriptRuntime actor
    ├── scoped execution, evaluation, globals, and runtime-bound codecs
    ├── native Promise jobs, host waiters, cancellation, and rejection reports
    ├── ES modules, Swift modules, and asynchronous source loading
    ├── live-value identity and lifetime coordination
    ├── detached environment, TypeScript schema, and TSDoc metadata
    └── QuickJSEngine (internal, non-Sendable)
            ├── one JSRuntime heap and one JSContext realm
            ├── one top-level execution scope and interrupt callback
            ├── canonical actor-owned live-value registry
            ├── canonical module and binding registries
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

## Unified execution lifecycle

Every operation that parses, executes, calls, links, evaluates, or drains
JavaScript enters one internal execution scope. The outermost scope refreshes
QuickJS's stack top, resolves the operation timeout, installs diagnostic
context, records nesting, translates interruption, and owns the final job
checkpoint. Nested callbacks inherit that state. Promise settlement after an
asynchronous Swift task starts a fresh actor-isolated entry.

The QuickJS interrupt callback checks, in order, Swift task cancellation, a
monotonic active-execution deadline, and the host's synchronous predicate. It
does not suspend or enter JavaScript. Time awaiting a Swift binding, host
Promise continuation, or module loader is outside the active execution scope,
so these deadlines measure only work performed by QuickJS.

`JavaScriptRuntime.run` exposes actor isolation without creating another
runtime abstraction. The synchronous overload provides one non-suspending actor
turn and permits direct typed evaluation. Its decoder accepts values and
Promises fulfilled by the immediate checkpoint, but reports `.wouldSuspend`
instead of blocking for external progress. The async overload permits ordinary
`try await`; it is explicitly reentrant at suspension points and is not a
transaction.

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

When the root result is a native QuickJS promise, typed evaluation marks it as
host-observed, drains pending jobs, and either decodes the fulfilled value,
throws the copied rejection, or installs an actor-owned host continuation.
Arbitrary thenables remain ordinary objects. The same root-promise rule applies
to typed function calls, codec decoding, globals, object properties, and array
elements.

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

Teardown order is strict: cancel Swift producers and host waiters, release
Swift-module export values and bindings, release every retained live value,
destroy the context, and finally destroy the runtime.

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

## Typed Swift bindings

`JavaScriptRuntime.function` uses Swift parameter packs to create statically
typed invocation thunks for heterogeneous `Decodable & Sendable` parameters and
`Encodable & Sendable` results. Separate overloads preserve all four Swift
effect combinations. Missing JavaScript arguments enter the decoder as
`undefined`, extra arguments are ignored, and `Void` becomes `undefined`.

Each registration passes through three deliberately separate internal values:

- a reusable `BindingDefinition` containing draft metadata and a type-erased
  invocation thunk, with no runtime identity or QuickJS value;
- a runtime-specific `BoundFunction` containing finalized location, order, and
  the destination runtime's Promise settlement callback;
- an actor-owned `RegisteredBinding` containing only lifecycle and QuickJS
  instance state.

The detached record is the future input to TypeScript and IDE artifact
generation. It contains no QuickJS value, runtime pointer, closure, or root
object. Primitive, integer, optional, collection, binary, date, URL, and custom
Codable shapes are recorded at registration time.

A global C trampoline recovers a runtime-specific bridge through QuickJS's
runtime opaque slot and then resolves a monotonic binding ID in the actor-owned
registry. JavaScript arguments are borrowed by QuickJS; the trampoline
duplicates each one before direct decoding. Synchronous results return a
duplicated value to QuickJS. No borrowed or C value becomes public or
`Sendable`.

QuickJS's JavaScript stack budget is paused only while an outermost Swift host
thunk executes, because generic and Codable frames are host stack usage rather
than recursive JavaScript execution. The exact configured budget is restored
before control returns to JavaScript. Job checkpoints refresh the stack top on
their current executor thread.

`JavaScriptBinding` is a pointer-free lifecycle handle. Dropping it has no side
effect. Explicit removal blocks new calls and is idempotent. Global replacement
changes the exposed property without invalidating older JavaScript references;
removing the older binding does not remove its replacement.

## Native promises and checkpoints

Async Swift bindings immediately create a native QuickJS promise and store its
resolve/reject capabilities, producer task, binding ID, and active-call
accounting in the actor-owned engine. Reusable definitions produce detached
completion work; a settlement callback injected during installation re-enters
the correct runtime, encodes or translates the result, and settles exactly
once.

Pending jobs drain to exhaustion at outermost evaluation, calls, binding
operations, and async settlement. Nested C callbacks do not create an
independent drain. After the queue reaches a checkpoint, the runtime resumes
fulfilled or rejected host waiters and reports each still-unhandled rejection
once. Rejections handled during the same checkpoint and promises crossing a
raw or typed host boundary are suppressed.

Cancelling a host waiter removes only that waiter. It never changes a shared
Promise or cancels its producer, regardless of whether JavaScript or Swift
created the Promise. Removing a binding preserves active calls by default;
passing `cancellingInFlight: true` explicitly cancels producer tasks and rejects
their shared promises.

Async bindings may re-enter their runtime after suspension. Sync bindings run
inside the active QuickJS call and must not synchronously re-enter it.

## Explicit exports

`JavaScriptRuntime.export` configures a JavaScript object through an explicit
builder shared with Swift-defined modules. It accepts only
`AnyObject & Sendable` roots. Methods use the same reusable definitions as
global functions; snapshot values use the direct encoder or same-runtime live
values.

Validation and encoding finish before the global property is changed. Duplicate
members, invalid metadata, cross-runtime values, and encoding failures roll the
transaction back. Methods are read-only non-enumerable own properties, while
snapshot values are read-only enumerable own properties. The binding registry
retains roots and closures until removal, active-call completion, or runtime
teardown; it performs no reflection.

## ES module system

Runtime-local ES module source is registered by canonical specifier. The
default resolver normalizes relative path segments lexically against the
referrer while preserving bare and scheme-prefixed specifiers. QuickJS retains
native module identity and evaluation-once behavior, including cycles,
re-exports, dynamic imports of available source, and top-level await. Namespace
objects enter the same canonical live-value registry as other objects.

The QuickJS normalizer and loader callbacks are synchronous and never suspend.
They consume only actor-owned registered source. When static compilation finds
a missing dependency, QuickJSKit releases the compile-only value, leaves the C
boundary, asynchronously loads that dependency, registers ordinary Swift
source storage, and retries compilation. Concurrent consumers of one canonical
specifier share a loader task; cancelling one waiter does not cancel the task
while other waiters remain. Unknown on-demand dynamic imports must be
registered or preloaded because QuickJS's loader callback cannot await.

Loader configuration becomes immutable at the first module compilation. This
keeps normalization deterministic for the lifetime of QuickJS's module cache.
Direct module evaluation allocates an internal unique specifier while retaining
the supplied source URL for diagnostics, relative resolution, and
`import.meta.url`.

Swift-defined modules use QuickJS native C modules internally, but expose no C
concepts. Their builder reuses the same binding drafts, type shapes, invocation
thunks, Promise capabilities, validation, and ordering as global functions and
object exports. Validation and value encoding complete before publication;
failure removes every provisional binding and value. A published Swift module
remains registered for the runtime lifetime because native module identity
cannot be safely unloaded.

## Environment metadata and TypeScript tooling

Every typed function and value records a detached type shape when its runtime
definition is created. Globals, object exports, and Swift modules publish that
metadata through one actor-owned environment registry only after the matching
QuickJS operation succeeds. Registry ownership follows binding identity, so a
stale binding cannot remove metadata for a newer replacement. Direct global
assignments and deletions follow the same success-first rule.

Custom Codable models opt into structural tooling through
`TypeScriptSchemaProviding`. A schema contains a primary `TypeScriptType` plus
flat named definitions, allowing recursive and mutually recursive models
without recursive Swift storage. Primitive and Foundation shapes are inferred
from the same generic types used by direct conversion. Each schema chooses one
canonical declaration scope: ambient global, a dotted namespace, or a known
JavaScript module. Related definitions may override that scope explicitly.
Conflicting definitions fail by `(scope, name)`; identical normalized
definitions are deduplicated, and equal names in different scopes remain
independent.

`JavaScriptRuntime.environmentDescription()` copies the currently exposed
Swift-provided globals, exported objects, Swift modules, known source modules,
and reachable schemas into one immutable snapshot. The snapshot contains no
runtime identifier, live value, closure, actor, QuickJS pointer, or invocation
thunk. JavaScript-created globals and unknown future loader results are excluded.
The same value model is the output boundary reserved for future runtime
templates.

Declaration rendering is a pure transformation over that snapshot. A focused
resolver first validates scopes and named references and replaces relative
schema types with canonical `(scope, name)` identities. The renderer then emits
global definitions at ambient top level, groups namespace definitions, and
merges module-owned definitions with the matching module exports. References
render locally when possible, as qualified namespace names across namespaces,
or as `import("specifier").Type` across module boundaries. These type-only
locations never create JavaScript objects or initiate module loading. Strict
generation rejects custom Codable types without schemas and source modules
without companion declaration bodies. Permissive generation emits explicit
`unknown` types and untyped ambient modules. Rendering order and whitespace are
canonical. Structured TSDoc covers summaries, remarks, parameters, returns,
errors, examples, links, defaults, and deprecation. User text is normalized and
escaped so it cannot terminate a comment or inject an unintended block tag.
Source-module companions remain opaque; generated module-scoped schemas are
placed before their body under the canonical specifier. QuickJSKit does not
infer types from source text. A source module owning generated schemas therefore
requires a companion even in permissive mode; TypeScript cannot safely merge
typed exports with an open-ended shorthand ambient module.

Documentation completeness is an orthogonal generation policy. Its strict mode
requires summaries for every generated declaration, parameter descriptions,
return documentation for non-`Void` functions, and explicit error conditions
for throwing functions. Source companion bodies remain opaque. Documentation
uses the same transactional environment ownership as types, so failed
publication and stale binding removal cannot corrupt later editor snapshots.

`TypeScriptWorkspace` is another detached value. It generates one declaration
file, a strict no-emit `tsconfig.json`, and optionally a private ESM
`package.json`. Filesystem writing occurs outside runtime isolation. A private
content-hash manifest restricts updates to files QuickJSKit previously created;
the default policy preserves modified generated files, both policies preserve
unrelated files, obsolete unchanged files are removed, and staged replacement
restores prior managed content if an operation fails. Relative-path validation
and managed-path symlink rejection keep regeneration inside its destination.

## Resource observability

Runtime configuration includes allocator and stack limits plus a default active
execution timeout. `JavaScriptMemoryUsage` intentionally exposes only stable
allocator bytes, used bytes, and the configured allocation limit; engine-
specific counters remain internal. Garbage collection is an explicit request,
not a promise that all host-retained values will disappear.

## Stable future boundaries

Future runtime templates will produce the same detached environment snapshot
without constructing QuickJS. Future macros must emit the same schemas and
binding drafts and may not create a parallel registration or module system.
Workers, multiple contexts, declaration source maps,
persistent bytecode, import attributes, and blocking Atomics remain deferred.

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
- Binding invocation uses generic static thunks and explicit exports rather
  than reflection.
- TypeScript generation operates on detached metadata without entering or
  retaining QuickJS.

Benchmarks will cover creation, evaluation, conversion, callbacks, promises,
and module loading before performance-specific abstractions are accepted.

## Reusable runtime configuration

Binding definitions and module sources are reusable Swift state; bound
functions, live values, Promise capabilities, namespaces, and registries belong
to exactly one runtime. This separation reserves a future immutable
`JavaScriptRuntimeTemplate` that can instantiate many independent runtime
actors with identical configuration.

Templates will remain declarative. Source is canonical, while QuickJS
compile-only bytecode may become an internal disposable cache keyed by the
exact engine build and compilation settings. Bytecode will not be a public
serialization format, and evaluated heaps will not be cloned or shared.
Templates may reuse `Sendable` Swift captures or invoke factories for
per-runtime actors and objects. Runtime-bound `JavaScriptValue` exports are
intentionally ineligible for reuse.

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
| Bindings | Reusable definitions specialized into runtime-bound functions | Runtime templates, TypeScript, docs, IDE files, and macros share one model |
| Promises | Native QuickJS promises and actor-owned checkpoints | Swift async interoperation preserves JavaScript semantics |
| Exports | Explicit transactional builder | Surfaces are reviewable, typed, and macro-ready without reflection |
| Execution | One nested top-level execution scope | Stack refresh, controls, checkpoints, and diagnostics remain consistent |
| Scoped access | Sync and async isolated `run` closures | Callers can batch work without a blocking facade or second runtime API |
| Modules | Registered source plus compile-discover-load-retry | Async loading never suspends inside a QuickJS callback |
| Swift modules | Native modules using canonical binding drafts | Globals, exports, modules, tooling, and future macros share one model |
| Observability | Stable memory summary and explicit collection | Callers gain useful controls without exposing QuickJS-specific counters |
| Type metadata | Explicit schemas captured with canonical binding shapes | Runtime behavior stays valid without tooling metadata; strict generation remains honest |
| Tooling | Immutable environment snapshots and pure deterministic rendering | Runtimes and future templates share one declaration model |
| Workspace writes | Detached files plus a content-hash ownership manifest | Regeneration is safe without watchers or runtime filesystem access |
| Portability | Portable core and tiny future adapters | Identical public API across supported platforms |
| Distribution | Pinned upstream source in a C target | Reproducible builds and auditable upgrades |

Detailed rationale is retained in `Documentation/Decisions`.
