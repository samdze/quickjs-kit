# ADR 0029: Fixed-width QuickJS closure bit-field on Windows

- Status: Accepted
- Date: 2026-08-04

## Context

QuickJS stores the closure-reference kind in a three-bit field of
`JSClosureVar`. The field was declared with the enum type
`JSClosureTypeEnum`. Clang targeting the Microsoft ABI does not preserve the
expected value when the enum is used as the bit-field base type. Evaluating a
global identifier such as `undefined` then reaches the impossible closure-kind
branch in `js_closure2()` and calls `abort()`.

The failure occurs inside the vendored C engine before control returns to
Swift. Other primitive expressions and direct global-property lookup do not
exercise the same closure-variable path.

## Decision

Declare `JSClosureVar.closure_type` as a fixed-width `uint8_t` bit-field while
retaining `JSClosureTypeEnum` as the symbolic value set. This preserves the
three-bit layout and the QuickJS semantics on every platform, while avoiding
the Microsoft enum bit-field representation.

Record the change as the third serial local QuickJS patch with its base and
resulting source checksums.

## Consequences

Global identifier evaluation returns the correct JavaScript value on Windows
instead of terminating the process. The change is private to the vendored C
engine, does not alter QuickJSKit's Swift API, and is covered by the Windows
platform smoke test and promise/conversion regression tests.
