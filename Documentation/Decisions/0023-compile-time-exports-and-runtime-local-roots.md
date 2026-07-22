# ADR 0023: Compile-time exports and runtime-local roots

## Status

Accepted.

## Context

Handwritten template exports are explicit and type-safe, but large host APIs
repeat member selection, TypeScript schemas, and documentation metadata.
Per-runtime factories also need to support uniquely owned classes whose state
is intentionally not safe to share between concurrency domains.

Runtime reflection cannot recover Swift effects, Codable shapes, DocC, source
locations, or actor isolation reliably. Marking arbitrary roots
`@unchecked Sendable` would hide the exact safety boundary QuickJSKit is meant
to enforce.

## Decision

QuickJSKit provides a separate optional macro product. Macros emit the same
detached root-aware definitions, schemas, documentation values, and source
locations consumed by handwritten APIs. They do not introduce a separate
runtime registration path.

Per-runtime factories return `sending Root`. Factory invocation, root
registration, definition materialization, and publication occur on the
destination `JavaScriptRuntime` actor. QuickJS stores only a root identifier.
The synchronous C trampoline recovers the weak runtime owner and calls
`assumeIsolated`, which checks the executor before resolving that identifier.

Ordinary async root closures continue to require `Root: Sendable`.
Runtime-isolated overloads accept any object and expose an
`isolated JavaScriptRuntime` parameter to Swift only. The compiler therefore
rejects unsafe async calls on non-Sendable roots while accepting actors,
Sendable classes, and caller-executor-preserving `nonisolated(nonsending)`
methods.

Live properties are implemented as ordinary registered getter and optional
setter bindings. Source locations are detached metadata and generate standard
Source Map v3 artifacts with logical paths.

## Consequences

- Non-Sendable state can be owned by one runtime without locks or unchecked
  conformances.
- Shared roots remain explicitly `Sendable`.
- Macros remain optional and the core runtime does not depend on SwiftSyntax.
- Macro and handwritten environments render through one TypeScript and TSDoc
  pipeline.
- Unsafe async member calls fail at the application compile site.
- Source maps are deterministic tooling artifacts, not runtime state.
