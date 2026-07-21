# ADR 0018: Unified TypeScript declaration scopes

- Status: Accepted
- Date: 2026-07-21

## Context

The original declaration renderer placed every Swift model in one configurable
`QuickJSKit` namespace. Applications need independent model namespaces, ambient
global types, and types that can be imported from the same JavaScript modules
that expose their runtime functions and values.

Namespaces and modules have different runtime meaning. A TypeScript namespace
only qualifies erased type names, while a QuickJS module provides values through
JavaScript imports. Treating module-owned schemas as namespaces would prevent
`import type`; automatically copying schemas into every module that uses them
would make ownership ambiguous and produce unstable duplicate declarations.

## Decision

Every schema and definition may carry one `TypeScriptDeclarationScope`: global,
a dotted namespace, or a known JavaScript module. Unscoped schemas inherit the
generation options' default scope. Named references are relative to their
containing scope unless they identify a destination explicitly.

Schema resolution is a pure normalization step over the detached environment.
It validates identifiers and module ownership, resolves references to
`(scope, name)` identities, deduplicates identical definitions, and rejects
conflicts before syntax rendering. Equal names in different scopes are valid.

Global definitions render at ambient top level. Namespace definitions render in
deterministically ordered `declare namespace` blocks. Module definitions become
exports in the matching ambient module and share its block with generated Swift
exports or opaque source-module companions. Cross-module references use
`import("specifier").Type`, which is erased and performs no runtime import.

One schema retains one canonical scope when used by several globals or modules.
Consumers qualify or import that single type; QuickJSKit never duplicates it
automatically. Explicit global references that lexical declarations would
shadow are rejected rather than rendered ambiguously.

## Consequences

Applications can model their scripting SDK with the same boundaries scripts
actually use: ambient host types, project namespaces, and importable module
types. Future runtime templates and macros can emit the same detached scope
metadata without a running QuickJS engine or a second declaration pipeline.

This is a pre-release source break. `typeNamespace` becomes `defaultTypeScope`,
`TypeScriptDefinition` becomes an extensible struct with a nested `Kind`, and
cross-scope references must state their destination. Module scopes must match a
module known to the captured environment, preserving the snapshot's promise to
describe the available host surface exactly.
