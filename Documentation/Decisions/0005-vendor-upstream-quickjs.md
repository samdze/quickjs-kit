# ADR 0005: Vendor a pinned upstream QuickJS release

- Status: Accepted
- Date: 2026-07-15

## Context

System QuickJS packages are inconsistent across supported platforms and versions.
QuickJS bytecode and C details are version-coupled, so reproducible behavior
requires a known engine revision.

## Decision

Vendor upstream QuickJS 2026-06-04 in `CQuickJS`. The official source archive
SHA-256 is `b376e839b322978313d929fd20663b11ba58b75df5a46c126dd19ea2fa70ad2a`.
Compile only `quickjs.c`, `dtoa.c`, `libregexp.c`, `libunicode.c`, and `cutils.c`.
Exclude command-line programs and `quickjs-libc` host modules. Build the sources
as GNU C11, matching upstream constructs such as its ARM inline assembly. The
release archive comes from <https://bellard.org/quickjs/>.
`Sources/CQuickJS/UPSTREAM.json` records the source URL, archive checksum,
compiled source set, exclusions, local module map, and patches.
`Sources/CQuickJS/CHECKSUMS.sha256` makes every retained upstream file
machine-verifiable.

## Consequences

Builds are reproducible and do not depend on a system installation. Upgrades are
intentional, reviewable changes. The package repository carries upstream source
and must retain its MIT license.
