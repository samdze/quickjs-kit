# ADR 0028: Native Windows time and CRT support for QuickJS

- Status: Accepted
- Date: 2026-08-02

## Context

The native Swift Windows toolchain does not provide the POSIX `sys/time.h`
header. QuickJS 2026-06-04 includes it in both its core engine and float
conversion source. The float conversion source does not use it. The core uses
`gettimeofday` only to seed `Math.random()` and implement `Date.now()`.

The same core uses the Microsoft CRT's `_msize` allocator query on Windows,
which is declared by `malloc.h`.

## Decision

Remove the unused float conversion include. In the core engine, use
`GetSystemTimeAsFileTime` and `ULARGE_INTEGER` only on Windows to produce Unix
microseconds. Non-Windows platforms retain the existing `gettimeofday` path.
Include `malloc.h` only on Windows for `_msize`.

Record the change as the second serial local QuickJS patch with its base and
resulting source checksums.

## Consequences

Windows retains millisecond `Date.now()` values and a time-based
`Math.random()` seed without depending on POSIX compatibility headers or a
separate portability library. The change is private to the vendored C core and
does not alter QuickJSKit's Swift API or concurrency model.
