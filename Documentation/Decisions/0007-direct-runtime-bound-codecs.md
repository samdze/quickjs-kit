# ADR 0007: Direct runtime-bound Codable conversion

- Status: Accepted
- Date: 2026-07-15

## Context

QuickJSKit needs strongly typed Swift conversion without making JSON a universal
bridge. JSON loses `undefined`, BigInt, binary buffers, dates, live objects, and
precise integer intent. A detached intermediate value tree would add allocation
and duplicate the traversal already defined by `Codable`.

## Decision

`JavaScriptEncoder` and `JavaScriptDecoder` are `Sendable` value types bound to
a `JavaScriptRuntime`. They implement Swift `Encoder` and `Decoder` containers
directly over actor-isolated QuickJS values. Typed evaluation decodes from its
temporary result before that value is released or inserted into the live-value
registry.

Integers encode as JavaScript `number` only in the inclusive safe-integer range
±(2^53−1); other signed and unsigned values encode as native `bigint`. Integer
decoding is integral, precision-safe, and destination-range checked. Data maps
to `Uint8Array`, Date to JavaScript `Date`, and URL to a string, with explicitly
documented additional decode forms.

Keyed decoding uses own enumerable string properties. Optional absence includes
missing properties, `null`, and `undefined`. Conversion has a configurable
container nesting limit of 64 by default. Ordinary representation and depth
failures use `EncodingError` or `DecodingError` with coding paths; engine
exceptions and runtime mismatches remain `JavaScriptError`.

## Consequences

Common conversions require no JSON serialization or package-defined
intermediate representation. Codec instances retain their runtime and may
produce live values. Value-based `Codable` conversion does not preserve
reference sharing, and cyclic JavaScript graphs terminate through the nesting
limit rather than an identity-based cycle detector. Changing the representation
policy is a compatibility decision and requires an ADR plus public executable
tests.
