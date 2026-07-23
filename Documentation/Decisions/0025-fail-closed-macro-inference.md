# ADR 0025: Macro inference is syntax-based and fail-closed

- Status: Accepted
- Date: 2026-07-23

## Context

`@JavaScriptExport` generates runtime definitions, Codable value schemas,
TypeScript declarations, TSDoc, and source locations. These outputs must agree.
The first implementation analyzed raw enums twice and derived model types from
rendered source text. It could therefore accept syntax whose encoded shape was
ambiguous or let the runtime and tooling descriptions drift.

Swift macros operate on syntax rather than the compiler's resolved semantic
type graph. Inference must not pretend to know behavior that syntax cannot
prove, especially for custom Codable implementations, property wrappers,
arbitrary generic containers, and unsupported member signatures.

## Decision

One concrete syntax analyzer produces a normalized parsed export for every
supported declaration. Both attached macro roles invoke that analyzer directly;
there is no global cache. The member role alone reports validation errors so a
single invalid declaration produces one deterministic diagnostic.

The parsed export is the sole input to:

- `JavaScriptValueTypeDefinition` and `JavaScriptHostTypeDefinition`;
- generated binding and accessor definitions;
- TypeScript schemas and dependencies;
- structured documentation;
- declaration source locations.

Type syntax is inspected structurally. Optional, array, and string-keyed
dictionary sugar and their standard generic spellings lower to the same model.
Unknown nominal types become explicit schema dependencies. Tuples, functions,
metatypes, unsupported generic containers, and non-string dictionary keys fail
during expansion.

Codable model inference includes stored instance properties, including private
ones, and applies explicit `CodingKeys`. Computed and static properties are
excluded. Custom Codable implementations, wrappers, lazy storage, and malformed
keys fail with stable `QuickJSKitMacros` diagnostic identifiers and guidance to
provide handwritten capabilities.

Host exports use the same analyzer for initializers, methods, static members,
properties, names, documentation, and duplicate detection. Unsupported
signatures fail at their precise syntax. Refinement attributes alter that one
model rather than a separate tooling path.

## Consequences

- Runtime behavior and generated tooling cannot use different enum or member
  interpretations.
- Supported declarations remain direct and allocation-free at runtime because
  the refactor affects only compile-time analysis.
- Ambiguous declarations require handwritten
  `TypeScriptSchemaProviding`, `JavaScriptValueTypeProviding`, or explicit
  export definitions.
- Expansion diagnostics are part of the package contract and are tested by
  stable ID, message, severity, location, and highlight.
- Future macro support must extend the normalized syntax model instead of
  adding a parallel parser or text-based resolver.
