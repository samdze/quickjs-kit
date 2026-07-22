# ADR 0022: Concrete Result Builder runtime-template declarations

- Status: Accepted
- Date: 2026-07-22

## Context

Runtime templates are declarative, but their original public syntax mutated an
`inout` builder at every nesting level. This exposed construction mechanics and
made a template harder to scan than its immutable provisioning model implied.

A SwiftUI-style Result Builder can express hierarchy, optional declarations,
branches, and repeated components. Retaining a generic syntax tree, however,
would duplicate the canonical detached definition model, increase compile-time
complexity, and provide no runtime benefit.

Swift also parses adjacent implicit-member expressions beginning with `.` as a
single member chain. A clean multiline Result Builder therefore cannot use
`.globals`, `.module`, and similar expressions without semicolons or other
artificial separators.

## Decision

`JavaScriptRuntimeTemplate` accepts a synchronous Result Builder whose nominal
components include `Globals`, `Function`, `Value`, `SwiftModule`,
`SourceModule`, `RuntimeInstance`, and `Startup`. Per-runtime components use
explicit names such as `RuntimeObject`, `InstanceFunction`, and
`InstanceValue`, making the hidden Swift root visible at the declaration site.

Every component contains a concrete, type-erased group of the existing runtime
template definitions. Builder operations concatenate those groups in lexical
order and support optional, conditional, repeated, and availability-controlled
content. The completed component is passed directly to the existing normalized
provisioning plan. No syntax tree survives template construction.

Immediate runtime exports retain their mutable transactional builder because
they perform an actor-isolated operation rather than describe a reusable
template. Template declarations deliberately omit live `JavaScriptValue`
exports because such values belong to one existing heap.

## Consequences

Template call sites resemble the immutable environment they describe and can
use standard Swift control flow. The DSL reuses the same binding thunks,
metadata, validation, TypeScript schemas, startup actions, and provisioning
pipeline as immediate registration.

The nominal components add public vocabulary, but avoid fragile separators,
global functions with capitalized names, and SwiftUI-style generic trees.
Template construction remains synchronous and allocation costs occur once,
while runtime creation and execution performance remain unchanged.
