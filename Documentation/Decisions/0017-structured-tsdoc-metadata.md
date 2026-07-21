# ADR 0017: Structured TSDoc metadata

- Status: Accepted
- Date: 2026-07-21

## Context

A single documentation string can describe a symbol, but it cannot reliably
describe parameters, results, error conditions, examples, related declarations,
defaults, or migrations. Inferring these sections from prose would be
nondeterministic, and Swift source comments are not available to a runtime
library. Generated declaration files must give TypeScript-aware editors enough
structure for useful hover cards, signature help, completion details, and
deprecation diagnostics.

Documentation also belongs to the same declared JavaScript environment as type
metadata. A separate registry would make replacement, rollback, snapshots, and
future runtime templates disagree about the surface exposed to scripts.

## Decision

QuickJSKit represents declaration and function documentation with immutable,
`Sendable`, `Hashable` values. General documentation contains a summary,
remarks, examples, see-also references, and deprecation guidance. Function
documentation additionally maps JavaScript parameter names to descriptions and
records return and thrown-error documentation. Properties may provide a
canonical documented default.

The binding, export, module, schema, and environment pipelines retain these
values beside their existing detached type shapes. Publication remains
transactional, and snapshots contain only metadata rather than closures,
actors, runtime identities, or QuickJS state. Future macros must emit these same
values when deriving documentation from Swift declarations and DocC comments.

The renderer emits a deterministic subset of standard TSDoc. It preserves
Markdown and inline links, normalizes line endings and outer blank lines,
escapes comment terminators, and prevents user prose from injecting block tags.
Source-module companion declarations remain opaque and document their own
members.

Type completeness and documentation completeness are independent. The default
permits missing documentation. The explicit complete policy requires summaries
for generated symbols, documentation for every function parameter, return
documentation for non-`Void` functions, and at least one error condition for
throwing functions.

## Consequences

Generated workspaces carry rich editor documentation without a running runtime
or a documentation-specific synchronization system. Applications may enforce a
fully documented scripting environment in tests or build tooling while
incrementally adopting metadata under the default policy.

Documentation stored in a nonliteral Swift `String` now requires an explicit
`TypeScriptDocumentation` or `TypeScriptFunctionDocumentation` initializer.
String literals continue to provide concise summary-only syntax. Arbitrary
custom tags, source-comment reflection, declaration source maps, and automatic
DocC extraction remain deferred to the macro phase.
