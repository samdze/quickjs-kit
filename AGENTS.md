# QuickJSKit Contributor Guide

QuickJSKit is a Swift package that embeds the upstream QuickJS engine behind an
actor-isolated, type-safe API. Keep the public surface small, predictable, and
portable. Prefer a direct implementation over a new abstraction when the
existing binding metadata and runtime boundaries are sufficient.

## Repository layout

- `Sources/CQuickJS` contains the pinned upstream C sources and the module map.
- `Sources/QuickJSKit` contains the public API, engine boundary, conversions,
  bindings, modules, runtime templates, and TypeScript tooling.
- `Sources/QuickJSKitMacros` and `_QuickJSKitMacroPlugin` contain the optional
  compile-time export product.
- `Tests/QuickJSKitTests` covers public runtime behavior and invariants.
- `Tests/QuickJSKitMacroTests` covers macro expansion, diagnostics, and runtime
  publication of generated definitions.
- `Examples` and `Integration/PlatformSmoke` are standalone consumers.
- `Sources/QuickJSKit/QuickJSKit.docc` is the public API documentation.

Do not add a target, dependency, wrapper, or service object unless an existing
boundary cannot support the demonstrated requirement.

## Runtime and ownership

`JavaScriptRuntime` is an actor and owns one QuickJS heap, context, job queue,
module graph, and live-value registry. Independent runtimes may run
concurrently; operations within one runtime are serialized by that actor.

- Refresh QuickJS's stack top at every top-level engine entry.
- Classify every C value as borrowed or owned immediately.
- Release `+1` QuickJS values exactly once through the existing RAII owners.
- Keep borrowed callback arguments borrowed unless explicitly duplicated.
- Keep runtime-bound values in the actor-owned registry. Public handles carry
  stable identities, not C pointers.
- Release registry values before the context, and the context before the runtime.
- Keep detached values, errors, configurations, descriptions, and artifacts
  independent of runtime state and `Sendable` where their API requires it.
- Never execute engine work from `deinit` on an arbitrary executor.
- Do not expose QuickJS pointers, C types, contexts, atoms, reference counts,
  or engine flags through a public or `Sendable` type.

Async Swift work may suspend outside the engine entry, but Promise settlement
must re-enter the owning runtime actor. Cancellation, deadlines, backpressure,
and reentrancy must preserve cleanup and leave the runtime usable after errors.

## Swift and API design

- Use Swift 6 language mode and strict concurrency.
- Prefer structs, enums, actors, and final classes. Add protocols only at a
  real substitution boundary.
- Keep mutable state actor-isolated or local. Prefer immutable `let` storage.
- Use `guard` and typed Swift errors for invalid state and failed operations.
- Do not use force unwraps, force casts, `unsafeBitCast`, unchecked Sendability,
  hidden locks, or hidden dispatch queues to silence a design problem.
- Keep unsafe code under the runtime boundary, with short lexical pointer
  scopes and explicit ownership comments where the C contract is not obvious.
- Avoid JSON as the default conversion path and avoid platform-specific APIs in
  the portable core.
- Design call sites as clear Swift sentences and document every public symbol.
- Preserve source and binary compatibility unless a breaking change is
  explicitly required and tested.

Runtime binding descriptions are detached metadata. They may describe names,
locations, types, effects, documentation, and ordering, but never closures,
roots, live values, or runtime pointers. Runtime invocation state belongs to
the actor-owned implementation beside that metadata.

Macro-generated exports and handwritten bindings must use the same metadata
model. `Globals`, `SwiftModule`, `RuntimeGlobals`, and `RuntimeModule` own the
JavaScript and TypeScript publication location; an exported Swift type must not
carry an intrinsic host scope.

## Documentation

README and DocC explain the supported public workflows: evaluation and
conversion, bindings and Promises, modules and loaders, runtime templates,
macros, TypeScript tooling, security, ownership, cancellation, and platforms.

- Describe current behavior, not plans or historical implementation phases.
- Keep examples small, accurate, and aligned with compiling tests.
- Explain isolation, lifetime, ownership, errors, cancellation, and important
  costs where they affect callers.
- Keep TypeScript and TSDoc metadata documented because they are product APIs.
- Do not add internal architecture journals or historical decision logs to the
  repository. Put durable user-facing contracts in source comments, README,
  DocC, and tests.

## Testing and quality

Use Swift Testing for new tests. Tests must be deterministic, local, and free
of sleeps, network access, uncontrolled randomness, and shared runtime state.
Cover successful execution, failure, cancellation, rollback, teardown, and
concurrency for each new behavior.

Before submitting a change, run the checks relevant to its scope. For a normal
package change, run:

```sh
swift build
swift test
swift test -c release -Xswiftc -warnings-as-errors
swift build --package-path Examples
swift build --package-path Integration/PlatformSmoke
Scripts/verify-vendored-quickjs.sh
Scripts/check-symbol-graphs.sh
git diff --check
```

For TypeScript or documentation changes, also run the TypeScript integration
fixture (`npm ci --ignore-scripts && npm test` in
`Tests/TypeScriptIntegration`) and build the DocC catalog with warnings as
errors on an Apple toolchain. Run sanitizers when the platform supports them.

Inspect public symbol graphs for missing documentation and leaked C
declarations. Keep vendored QuickJS changes separate from Swift and
documentation changes.

## Change workflow

1. Read the relevant source, tests, public documentation, and package targets.
2. Make the smallest coherent change within the existing architecture.
3. Add or update tests and public documentation with the behavior change.
4. Run the appropriate build, test, documentation, and symbol checks.
5. Review the diff for unrelated edits, generated artifacts, stale wording,
   and accidental API exposure.
6. Use a Conventional Commit message:

   ```text
   <type>(<scope>): <imperative summary>
   ```

Do not commit `.build` output, temporary files, credentials, or generated
artifacts that are not part of an explicit package contract.
