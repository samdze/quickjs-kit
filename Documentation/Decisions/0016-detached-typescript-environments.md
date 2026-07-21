# ADR 0016: Detached TypeScript environment snapshots

- Status: Accepted
- Date: 2026-07-21

## Context

QuickJSKit must generate declarations for the exact host surface exposed to
scripts, and future runtime templates must produce the same tooling before any
QuickJS heap exists. Reflection cannot recover reliable Codable structure,
runtime inspection would include arbitrary script mutations, and retaining
binding closures or live values would couple editor tooling to engine lifetime.

Workspace regeneration also needs to be useful in application build and setup
flows without granting the runtime actor ambient filesystem responsibilities or
overwriting files maintained by the application.

## Decision

Swift models describe tooling structure explicitly through
`TypeScriptSchemaProviding`. Schemas are immutable values consisting of a
primary type and flat named definitions, so recursive models do not require
recursive Swift storage. Runtime encoding remains independent: a custom Codable
type without a schema is still valid at runtime.

All Swift-provided globals, explicit object exports, Swift modules, source
module companions, and reachable schemas publish into one actor-owned metadata
registry. Publication follows successful QuickJS publication. Binding IDs own
replaceable entries so stale removal cannot erase a newer declaration.

The runtime copies that registry into `JavaScriptEnvironmentDescription`, which
contains no closure, actor, live value, runtime ID, or QuickJS state. TypeScript
rendering is a pure deterministic transformation over this snapshot. Strict
mode rejects missing structural metadata; permissive mode emits explicit
untyped fallbacks. Source modules require companion declaration bodies because
QuickJSKit does not infer types from JavaScript source.

IDE workspaces are detached file artifacts. Their writer uses a private manifest
of content hashes, stages all new contents before replacement, rejects unsafe
paths and managed symlinks, preserves unrelated files, and only overwrites
modified generated files under an explicit policy. No watcher, CLI target, or
runtime filesystem access is introduced.

## Consequences

Applications can generate declarations and editor configuration only when
their host environment changes, then release the originating runtime. Two
identically configured runtimes produce byte-identical output regardless of
runtime identity or registration order. A future `JavaScriptRuntimeTemplate`
can emit the same environment description without redesigning tooling.

Explicit schemas add a small amount of handwritten code until macros can
synthesize it. This cost keeps runtime conversion simple, makes incomplete
declarations visible, supports non-reflectable Codable designs, and avoids a
second metadata system. Declaration source maps remain deferred until macros
can provide reliable Swift source locations.
