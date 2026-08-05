# QuickJSKit Contributor and Agent Guide

## Project vision

QuickJSKit is a production-quality Swift package for embedding the upstream
QuickJS engine. It should feel designed for Swift rather than translated from C.
The public API owns memory automatically, uses Swift errors, participates in
structured concurrency, and remains identical on every supported platform.

The ambition is to become the reference QuickJS integration for Swift: a small,
trustworthy core plus a coherent developer platform for typed bindings, modules,
async interoperability, TypeScript declarations, IDE workspaces, and future
macro-generated exports.

## Long-term goals

- Support Swift 6.3 and later with complete strict-concurrency checking.
- Support macOS, iOS, tvOS, watchOS where upstream permits it, visionOS, Linux,
  Windows, and Android without changing the public API.
- Hide every QuickJS pointer, C type, reference count, and integer error code.
- Provide loss-aware direct conversions for Swift primitives, collections,
  `Data`, `Date`, `URL`, optionals, and `Codable` values without defaulting to
  JSON serialization.
- Bridge typed Swift closures, `async`, `throws`, and `async throws` functions to
  JavaScript functions and native promises.
- Support ES modules, Swift-defined modules, custom loaders, cancellation,
  interrupts, timeouts, and resource limits.
- Derive deterministic TypeScript declarations and editor workspaces from the
  same binding metadata used at runtime.
- Support immutable runtime templates that efficiently instantiate many
  independent, consistently configured QuickJS heaps.
- Permit macros to generate binding metadata later without making macros a
  runtime dependency or a second binding system.
- Maintain strong documentation, diagnostics, tests, and release discipline.

## Architectural philosophy

Keep the architecture shallow. There are three conceptual layers:

1. Vendored QuickJS C sources in `CQuickJS`.
2. A tiny internal Swift engine boundary that owns C resources and translates
   engine outcomes into Swift data.
3. The public, actor-isolated Swift API.

Do not add a protocol, box, factory, service, or generic parameter unless it
solves a demonstrated extension or testing problem. Prefer concrete types and
composition. Keep hot paths direct. Runtime binding metadata is the intentional
extension seam for functions, exported objects, TypeScript, documentation, and
future macros.

Correctness comes first, followed by simplicity, API quality, and measured
performance. Optimize from profiling evidence. The simplest safe path should be
the fastest path: direct conversion, limited allocation, static dispatch, and
no intermediate JSON representation by default.

## Ownership model

`JavaScriptRuntime` is the root owner. Internally it owns exactly one QuickJS
`JSRuntime` heap and, initially, one `JSContext` realm. Additional public
contexts may be introduced only as handles that delegate to the same owning
runtime actor; contexts never create independent synchronization domains.

The rules are:

- Every C value entering Swift is immediately classified as borrowed or owned.
- A QuickJS `JSValue` returned at +1 ownership is immediately placed in one
  immutable RAII owner object. That owner performs exactly one `JS_FreeValue`.
- Borrowed callback arguments are never freed unless first duplicated.
- Runtime-bound values retain a lifetime token owned by the runtime. They never
  expose their pointer and never execute engine work in `deinit` on an arbitrary
  executor.
- Long-lived values are stored in an actor-owned canonical registry. Public handles
  carry stable IDs, not C pointers. Registry teardown releases values before the
  context, and contexts are released before the runtime.
- Detached primitives and converted Swift models own ordinary Swift storage and
  are `Sendable`.
- QuickJS bytecode is version-specific and unsafe for untrusted persistence; do
  not expose it as a stable serialization format.

Any change to ownership must be described in an architectural decision record
and covered by success, throw, cancellation, and teardown tests.

## Concurrency model

QuickJS permits no concurrent use within a runtime. Each `JavaScriptRuntime` is
therefore an actor and is the sole executor boundary for its runtime, contexts,
jobs, callbacks, loaders, and value registry.

- Never mark the low-level engine or raw holders `Sendable` or
  `@unchecked Sendable`.
- Never use a global lock to make QuickJS appear thread-safe.
- Multiple runtime actors may execute independently and concurrently.
- Public detached values, errors, configuration, and binding descriptions must
  conform to `Sendable`.
- Public runtime operations are actor-isolated. Do not add hidden dispatch
  queues or worker threads.
- Swift actors are not pinned to an OS thread. Call `JS_UpdateStackTop` at the
  beginning of every top-level entry into a runtime so QuickJS stack-overflow
  checks use the current executor thread's stack. Keep nested engine calls
  synchronous within that entry.
- Swift callbacks invoked by JavaScript run within the runtime's serialized
  operation. Reentrancy must be explicit and tested before it is enabled.
- Promise jobs are drained by the owning actor. Async Swift work may suspend,
  but promise settlement must re-enter that actor.
- Script interruption and active-execution deadlines use QuickJS's interrupt
  handler and Swift task cancellation. Suspended Swift work is intentionally
  outside the execution deadline. Interrupt callbacks may only inspect the
  current actor-owned execution scope; they must not suspend or call into
  JavaScript.
- Avoid locks. A narrow atomic flag is acceptable for an interrupt callback
  when actor access is impossible, provided the decision is documented.

## Package structure

```text
QuickJSKit/
├── Package.swift
├── AGENTS.md
├── Sources/
│   ├── CQuickJS/
│   │   ├── include/module.modulemap
│   │   └── upstream QuickJS sources
│   └── QuickJSKit/
│       ├── Bindings/
│       ├── Conversion/
│       ├── Errors/
│       ├── Modules/
│       ├── Runtime/
│       └── Values/
└── Tests/QuickJSKitTests/
    ├── PublicAPI/
    └── Internal/
```

Future capabilities should start as folders in `QuickJSKit`, not new targets.
Add a target only for a real dependency or compilation boundary, such as a
future macro target or a test-support module. Target proliferation makes the
package harder to build and understand.

## Target responsibilities

### `CQuickJS`

- Contains an unmodified, pinned upstream QuickJS release and its upstream
  license.
- Compiles only the engine files needed by the library; it excludes the command
  line tools and platform-heavy `quickjs-libc` standard library.
- Exposes a Clang module through `include/module.modulemap` for the Swift wrapper.
- Contains no QuickJSKit-specific public shim API and is never re-exported.
- Receives source updates as isolated commits with version, checksum, patch,
  and platform verification recorded.

### `QuickJSKit`

- Owns the complete public API and all Swift implementation.
- Imports `CQuickJS` with internal visibility only.
- Contains the sole unsafe engine boundary, ownership wrappers, conversions,
  binding registry, module loading, job queue, and public actor API.
- Must remain portable Swift in its core. Platform services go behind small
  internal concrete adapters selected with conditional compilation.

### `QuickJSKitTests`

- Tests public behavior by default and uses `@testable` only for important
  invariants that cannot be observed publicly.
- Owns correctness, error, concurrency, resource, stress, and regression tests.
- Must not create a second wrapper around the C API.

## Unsafe code guidelines

Unsafe code belongs only in files under `Sources/QuickJSKit/Runtime` or a future
explicitly named low-level directory.

- Keep pointer scopes lexical and short.
- Never assume actor serialization implies OS-thread affinity. Every top-level
  C entry refreshes the QuickJS stack top before other engine work.
- Convert strings with explicit byte counts; never assume JavaScript strings are
  NUL-free.
- Use one immutable RAII owner object for each +1 C value. Sharing the owner is
  safe; transferring its raw value requires an explicit QuickJS duplication.
- Do not use force unwraps, force casts, `unsafeBitCast`, unmanaged global state,
  or unchecked `Sendable` to silence the compiler.
- State the ownership convention in a comment whenever it is not obvious from a
  QuickJS function's documented contract.
- Do not let a pointer appear in a public or `Sendable` stored property.
- Treat compiler warnings, sanitizer findings, and concurrency diagnostics as
  bugs.
- Prefer a small C compatibility patch only when Swift cannot correctly import
  a cross-platform upstream construct. Document and test every patch; do not
  create a parallel public C wrapper.

## Coding conventions

- Use Swift 6 language mode and strict concurrency.
- Prefer structs, enums, actors, and `final` classes. Use protocols only at real
  substitution boundaries.
- Default to `internal`; make API public intentionally.
- Use access-controlled imports so C declarations cannot leak into public API.
- Prefer immutable `let` storage. Limit mutable state to actor isolation.
- Avoid force operations and implicit invariants. Use `guard` with actionable
  errors.
- Favor typed throws only when it materially improves callers and all failure
  paths can honestly uphold the type.
- Use `some`, `any`, ownership modifiers, and noncopyable types when they clarify
  behavior, not merely because they are new.
- Do not add Objective-C annotations or Foundation dependencies to the core
  without a cross-platform requirement.
- Name Swift API for its role, never by mechanically stripping a `JS_` prefix.
- Keep files focused and normally name them after their primary type.

## Swift style guidelines

Follow the Swift API Design Guidelines. At call sites, code should read as a
sentence. Use full words and role-based argument labels. Prefer:

```swift
try await runtime.evaluate(source, sourceURL: "plugin.js")
```

over abbreviations, builder chains, and C-shaped option flags. Use four spaces,
trailing commas in multiline declarations and calls, one primary declaration
per file, and early exits. Keep functions small enough for ownership and error
paths to remain visible. Run `swift format` only if the repository adopts and
pins a shared configuration; do not introduce formatting churn incidentally.

## Public API philosophy

Public API should resemble Foundation and Swift Collections: compact,
discoverable, strongly typed, unsurprising, and difficult to misuse.

- Never expose `CQuickJS`, C types, pointers, contexts, atoms, reference counts,
  or raw engine flags.
- Prefer value semantics for configuration, errors, detached values, binding
  descriptions, and generated artifacts.
- Use runtime-bound handle types only when JavaScript identity or mutation must
  be preserved.
- Preserve actor isolation in the surface instead of claiming synchronous
  thread safety.
- Offer generic typed conveniences above a small set of concrete primitives.
- Do not use JSON as the default conversion protocol.
- Avoid public protocols until conformances are genuinely useful outside the
  package. Seal implementation details internally.
- Design for source stability. A public type should have room to evolve without
  exhaustive client switching or exposed storage.
- Every public API addition needs documentation, tests, an ergonomic call-site
  example, and a reason it belongs in the stable surface.

## Binding and TypeScript design

Runtime registration, TypeScript generation, IDE workspace generation, and
future macros must consume one canonical detached binding description. It
describes JavaScript location, names, parameters, result, sync/async and
throwing behavior, documentation, and deterministic ordering. The runtime
pairs it with a separate actor-owned invocation thunk.

Descriptions must contain no closure, root object, QuickJS value, or runtime
pointer, so declaration generation remains deterministic and does not need a
running JavaScript engine. Macros should emit the same records handwritten
registration uses. Do not create macro-only runtime pathways.

## Documentation guidelines

Documentation is part of the API contract.

- Every public symbol and public member requires a DocC comment before merge.
- Type documentation explains isolation, lifetime, identity, and ownership.
- Method documentation covers parameters, result, errors, cancellation,
  reentrancy, and important performance costs.
- Include small compiling examples for primary workflows.
- Never promise behavior that is only an implementation accident.
- Keep boundary and data-flow changes documented in the relevant DocC catalog,
  README guidance, and focused source comments.
- User-facing diagnostics should name the operation and recovery action when
  possible, while preserving JavaScript stack traces.

## Testing philosophy

Test observable behavior and architectural invariants at the lowest useful
level. New behavior includes success, failure, boundary, teardown, and
concurrency coverage.

Keep repository-only tooling focused on checks that protect a package contract
or a platform promise; do not add checks that merely duplicate package tests.

The long-term suite includes:

- evaluation and diagnostic source names;
- syntax errors, thrown values, error subclasses, and stack traces;
- exact primitive, integer-boundary, optional, collection, binary, date, URL,
  and `Codable` conversions;
- closure arities, throwing callbacks, exported object lifetime, and actor
  exports;
- promise fulfillment/rejection, job draining, async callbacks, cancellation,
  and reentrancy;
- script and ES module loading, resolution, normalization, and loader failure;
- global bindings and deterministic TypeScript declarations;
- concurrent callers and independent concurrent runtimes;
- timeouts, interrupts, memory limits, stack limits, and recovery after errors;
- repeated creation/destruction, leak checks, sanitizers, and stress tests;
- build validation on every supported operating system and architecture.

Prefer Swift Testing for new tests. Tests must be deterministic, must not depend
on wall-clock sleeps, and must not reach the network. Run `swift test` locally.
Platform CI should additionally run address and thread sanitizers where the
toolchain supports them.

## Platform rules

- Core code must not import Darwin, Glibc, WinSDK, Android, Objective-C, or UI
  frameworks directly.
- Use standard Swift first. Isolate unavoidable platform code behind a small
  internal adapter with one file per platform family.
- Use conditional compilation based on capabilities when possible, not lists of
  presumed operating systems.
- Apple minimum versions belong only in `Package.swift`; non-Apple platforms are
  not second-class and must retain the same public API.
- A feature unsupported by upstream on one platform should fail at capability
  discovery or runtime with a Swift error, not disappear from the API.

## Contribution workflow

1. Read this file and the relevant source, tests, and package configuration.
2. Keep the change within one coherent capability and state what is deferred.
3. Discuss a new public abstraction or ownership strategy before implementing a
   large surface.
4. Add tests and DocC alongside code.
5. Run `swift build` and `swift test` with Swift 6.3 or newer.
6. Check strict-concurrency diagnostics and inspect public API for leaked C
   declarations.
7. Update relevant DocC catalogs and roadmap status when the design changes.
8. Keep vendored upstream changes separate from handwritten wrapper changes.

### Commit messages

Use the Conventional Commits format for every commit:

```text
<type>(<scope>): <imperative summary>
```

Do not combine formatting, a QuickJS upgrade, and a feature in one review. A
change is complete only when its failure and cleanup paths are as clear as its
happy path.

## Roadmap

### Phase 1 — architecture validation (completed)

- Package targets and pinned QuickJS integration.
- Actor-isolated runtime/context ownership.
- RAII ownership for temporary values.
- Primitive evaluation and structured exceptions.
- Basic memory and stack configuration.
- Architecture, decisions, contributor guidance, and focused tests.

### Phase 2 — value and conversion system (completed)

- Runtime-bound object, array, and function handles backed by an actor registry.
- Direct primitive, optional, collection, binary, date, URL, and integer-safe
  conversion protocols.
- Typed `evaluate<T>` and global access.
- Explicit `Codable` policy without making JSON the universal bridge.

### Phase 3 — bindings and async (completed)

- Canonical binding descriptions and typed Swift closure registration.
- Throws and async-throws bridging to native JavaScript promises.
- Job queue draining, cancellation, reentrancy policy, and lifecycle tests.
- Exported Swift values and actors.

### Phase 4 — runtime execution, modules, and observability (completed)

- Unified top-level execution scopes, synchronous and asynchronous `run`,
  and immediate typed evaluation.
- Cancellation, execution deadlines, custom interruption, memory reporting,
  and explicit garbage collection.
- ES modules, Swift-defined modules, lexical resolution, asynchronous custom
  loading, preload, top-level await, and canonical namespace identity.

### Phase 5 — TypeScript and IDE tooling (completed)

- Explicit macro-ready schemas and detached environment snapshots.
- Deterministic `.d.ts` generation for global, namespaced, and module-owned
  types plus globals, exports, models, docs, and enum literal unions.
- Structured TSDoc for hover cards, signature help, examples, links, defaults,
  errors, and deprecation, with an independent documentation-completeness gate.
- Reproducible managed editor workspaces with safe explicit regeneration.

### Phase 6 — runtime templates and provisioning (completed)

- Immutable declarative templates that create independently isolated runtimes.
- Concrete Result Builder declarations with conditional and repeated composition.
- Shared Sendable definitions and typed per-runtime Swift root factories.
- Environment and TypeScript snapshots without constructing QuickJS.
- Private source-canonical compile-only module artifacts with safe fallback.
- A dependency-free runtime-provisioning benchmark executable.
- Reusable precompiled global programs with canonical source fallback.
- Explicit linked and evaluated startup actions after complete publication.
- Batched template installation and one-shot prewarmed runtime provisioning.
- Percentile benchmarks for startup, calls, modules, and ready acquisition.

### Phase 7 — compile-time exports and models (completed)

- Optional macro product emitting canonical schemas and binding definitions.
- `@JavaScriptExport` actors, Sendable classes, and uniquely transferred
  runtime-local non-Sendable final classes.
- Typed live property accessors and compiler-checked runtime-isolated async
  adapters without unchecked Sendability.
- Schema generation for Codable structs and raw enums through the unified
  `@JavaScriptExport` annotation.
- Shared DocC-to-TSDoc extraction, logical declaration origins, and Source Map
  v3 workspace artifacts.

### Phase 8 — JavaScript-visible Swift types (completed)

- One `@JavaScriptExport` macro selecting value or host semantics from the
  declaration kind.
- Explicit global and Swift-module publication through `JavaScriptType`.
- Validating struct constructors and frozen raw-enum validators.
- Constructible live Swift classes and actors with exact identity, ownership,
  overload selection, static members, and Promise-based async factories.
- Direct host references, host-object resource limits, complete TypeScript,
  TSDoc, source maps, tests, and interoperability benchmarks.

### Phase 8.1 — macro contract hardening (completed)

- One syntax-aware parsed export model shared by runtime definitions, value
  schemas, TSDoc, dependencies, and source locations.
- Fail-closed Codable inference with equivalent optional, array, and
  string-keyed dictionary spellings.
- Central host-signature, naming, duplicate, accessor, and documentation
  validation.
- Stable diagnostic identifiers plus exact expansion and diagnostic contract
  tests.

### Phase 9 — release readiness (completed)

- Restricted runtime defaults, pending async host-call backpressure, and unified
  resource observability.
- Expanded conversion, Promise, access, provisioning, and standalone startup
  benchmarks.
- Concise README compatibility guidance, complete DocC, and portable examples.
- Reproducible vendored-source verification, dependency locks, API
  compatibility, sanitizer, and stress gates.
- Blocking qualification for Apple platforms, Linux, Windows, and Android plus
  non-mutating release automation.

## Design principles checklist

Before adding an abstraction, ask:

- Does it remove a misuse or make a future capability possible?
- Can a contributor explain its ownership and isolation in one paragraph?
- Does it keep C and unsafe state out of public API?
- Does it work without Apple-only facilities?
- Does it avoid allocations, copies, boxing, dynamic dispatch, and JSON on the
  common path?
- Is it simpler than the alternatives at the call site and in maintenance?
- Can it evolve without forcing a breaking architectural replacement?
- Are documentation and tests sufficient to make its contract durable?

If the answer is unclear, keep the implementation concrete and internal until
real use cases establish the missing abstraction.
