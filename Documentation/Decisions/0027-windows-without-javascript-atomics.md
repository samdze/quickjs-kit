# ADR 0027: Windows without the QuickJS Atomics intrinsic

- Status: Accepted
- Date: 2026-08-02

## Context

QuickJS 2026-06-04 enables its `Atomics` intrinsic through
`CONFIG_ATOMICS`. That implementation depends on POSIX `pthread` mutexes and
condition variables, which are not part of Swift's native Windows toolchain.

QuickJSKit does not expose JavaScript `Atomics` through its Swift API and does
not require it for actor isolation, native promises, modules, bindings, or
runtime templates.

## Decision

Disable `CONFIG_ATOMICS` only when compiling the vendored QuickJS core for
Windows. Keep `SharedArrayBuffer` and every QuickJSKit public API available.

Record the exact source change as a local vendored patch. The upstream archive
checksum, original source checksum, patched source checksum, patch file, and
vendored checksum manifest make the deviation reviewable and reproducible.

## Consequences

JavaScript running in a Windows QuickJSKit runtime has no global `Atomics`
object. The package remains source-compatible across platforms and does not
add a pthread emulation dependency, a Windows thread layer, or a second
concurrency model.

If future upstream QuickJS supports the native Windows toolchain without this
limitation, remove this patch as part of an isolated upstream upgrade.
