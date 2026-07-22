# ADR 0024: JavaScript-visible Swift types use separate value and host capabilities

- Status: Accepted
- Date: 2026-07-22

## Context

QuickJSKit can already export typed closures, object surfaces, schemas, and
runtime-local roots. JavaScript applications also need to import Swift-defined
types, construct values, create live services, and pass both forms back through
typed Swift bindings. A single runtime representation would obscure the
essential ownership difference between a Codable value and a retained Swift
reference.

## Decision

`@JavaScriptExport` is the only automatic annotation. Declaration kind selects
one of two detached capabilities:

- structs and supported raw enums conform to
  `JavaScriptValueTypeProviding`;
- final classes and actors conform to `JavaScriptHostTypeProviding`.

Publication remains explicit through `JavaScriptType`, `registerType`, or a
Swift-module export builder. A type has one permanent global or module location
per environment.

Struct construction is decode–re-encode canonicalization. The temporary Swift
value is discarded before returning the JavaScript object. Enum exports are
frozen validators over their raw primitive values. These value types never
enter the runtime root registry.

All host types share one private QuickJS native class. Opaque payloads contain
only runtime-local root and type identifiers. The runtime actor owns Swift
instances, while QuickJS owns wrappers, constructors, and prototypes. A borrowed
identity-cache entry is removed by the native finalizer and never owns a QuickJS
reference. Active asynchronous calls retain their root independently until
settlement.

Constructor candidates decode arguments without constructing roots. Exactly
one candidate must match. Direct host references verify the shared native class
and exact type identifier; Codable values continue through the existing direct
codec.

## Consequences

- Annotation and documentation are unified without conflating memory models.
- Value construction is structural and identity-free; host construction keeps
  Swift identity and actor isolation.
- JavaScript cannot forge a live host reference with a plain object.
- Type registration cannot be replaced or removed safely and therefore lasts
  for the runtime lifetime.
- Nested collections of live host references require a future recursive
  actor-isolated codec rather than an implicit extension of Codable.
- JavaScript subclassing and cross-runtime host transfer remain unsupported.
