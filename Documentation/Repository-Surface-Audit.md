# Repository Surface Audit

This document classifies repository-only tooling by the value it provides
relative to its maintenance cost. It does not change the public package or
remove files. Items marked as removal candidates should not gain new behavior
before the repository is simplified.

## Classification

- **Retain**: enforces a QuickJSKit-specific invariant that is not expressed
  clearly by another tool.
- **Consolidate**: provides useful behavior, but its current standalone form is
  unnecessary.
- **Removal candidate**: duplicates an existing command or has not demonstrated
  enough value to justify its files, dependencies, and workflow surface.

The classification is intentionally strict. Convenience alone does not justify
a repository abstraction.

## Package Components

| Component | Status | Responsibility | Why it stays or could change |
| --- | --- | --- | --- |
| `Sources/CQuickJS/` | **Retain** | The pinned upstream JavaScript engine and its module map. | It is the only engine implementation. Removing it means replacing QuickJSKit's purpose; keeping it vendored gives deterministic builds and one audited engine version. |
| `Sources/QuickJSKit/` | **Retain** | The public Swift API, actor-owned runtime, ownership boundary, conversions, bindings, modules, templates, and tooling metadata. | This is the package itself. The internal folders may be reorganized only when it removes a concrete ownership or execution ambiguity. |
| `Sources/QuickJSKitMacros/` | **Retain as an optional product** | Public macro declarations and generated metadata surface. | It remains separate so applications that do not use macros do not import a compiler plugin. It could be removed only by deliberately dropping automatic export generation. |
| `Sources/_QuickJSKitMacroPlugin/` | **Retain as an implementation boundary** | Compile-time syntax analysis and macro expansion. | Swift requires a compiler-plugin target for these macros. It must never become a runtime dependency of `QuickJSKit`. |
| `Benchmarks/QuickJSKitBenchmarks/` | **Retain, then consolidate** | Reproducible measurements of runtime creation, calls, modules, templates, and provisioners. | The executable is the right boundary because performance claims need evidence. It should absorb the separate aggregation script rather than gain more helper scripts. |
| `Tests/QuickJSKitTests/` | **Retain** | Public executable examples and internal ownership, concurrency, and teardown invariants. | Tests are the primary specification of behavior and cannot be replaced by workflow checks. |
| `Tests/QuickJSKitMacroTests/` | **Retain** | Expansion, diagnostics, and integration contracts for macros. | Macro behavior is compile-time behavior; package runtime tests cannot prove it. |
| `Tests/TypeScriptIntegration/` | **Retain** | Verifies generated declarations with the actual TypeScript and TSDoc tools. | Swift tests can compare strings but cannot prove that editors and the TypeScript parser accept the output. Keep the fixture small and dependency-locked. |

No public runtime feature is a removal candidate in this audit. The candidates
below are repository mechanics, not JavaScript embedding capabilities.

## Removed Fuzzing Harness

Status: **Removed**

Coverage-guided fuzzing mutates inputs and keeps mutations that reach new code
paths. Sanitizers then turn invalid memory access, traps, and hangs into
actionable failures. This differs from unit tests, which exercise fixed known
inputs, and from a sanitizer-only run, which checks only the paths reached by
the ordinary test suite.

The former `Fuzzing` package had a poor value-to-complexity ratio:

- it adds a package, executable, corpus, launcher, and workflow job;
- one multiplexed entry point combines unrelated runtime and tooling surfaces;
- bridging the synchronous fuzzer entry point through a detached task and
  semaphore obscures failures and lifetime behavior;
- the small seed corpus and short scheduled campaign provide limited coverage;
- JavaScript parser coverage substantially overlaps upstream QuickJS work;
- no current QuickJSKit regression depends on a fuzz-discovered input.

The useful invariant is that every discovered failure becomes a deterministic
unit test. That invariant does not require retaining a repository-owned harness.
Focused fuzzing can be run externally or reintroduced only when a wrapper-
specific boundary has a concrete corpus and ownership model.

Removed paths:

- `Fuzzing/`
- `Scripts/run-fuzzing.sh`
- the `fuzz` job in `.github/workflows/quality.yml`

## Scripts

| Path | Status | Reason |
| --- | --- | --- |
| `Scripts/check-symbol-graphs.sh` | **Retain** | Enforces two package-specific public API invariants: no C declarations and no undocumented intentional public symbols. It is reused for CI and release artifacts. |
| `Scripts/verify-vendored-quickjs.sh` | **Retain** | Cross-platform verification of the pinned upstream version and every vendored source checksum is unique to this repository. |
| `Scripts/summarize-benchmarks.swift` | **Removed** | Its aggregation mode now belongs to `QuickJSKitBenchmarks`, so one executable owns benchmark production and summary output. |
| `Scripts/check-api-compatibility.sh` | **Removed** | The reusable CI workflow invokes the SwiftPM command directly. |
| `Scripts/validate-typescript.sh` | **Removed** | The reusable CI workflow invokes the fixture's `npm test` command directly. |
| `Scripts/validate-examples.sh` | **Removed** | CI uses direct build commands, with no hidden sequencing logic. |
| `Scripts/generate-sbom.sh` | **Removed** | The handwritten release-only output did not justify a permanent custom generator. Release artifacts retain licenses and vendored-source records. |
| `Scripts/run-fuzzing.sh` | **Removed** | It existed only for the removed harness. |

The likely steady state is two repository scripts:

1. vendored QuickJS verification;
2. public symbol graph verification.

Benchmark aggregation should remain part of the benchmark executable, not a
third general repository script.

## Other Repository-Only Surfaces

| Path | Status | Reason |
| --- | --- | --- |
| `IntegrationTests/PlatformSmoke/` | **Retain** | Proves that an external consumer can use both products without `@testable` imports or C APIs and is the portable platform qualification unit. |
| `Examples/` | **Consolidated** | One executable with focused subcommands preserves five consumer workflows without five target definitions. |
| `Documentation/Benchmarks/Phase-9-Before.json` | **Removed** | The concise benchmark report retains the meaningful comparison; generated raw reports did not participate in a gate. |
| `Documentation/Benchmarks/Phase-9-After.json` | **Removed** | The concise benchmark report retains the meaningful comparison; generated raw reports did not participate in a gate. |
| `.github/workflows/release.yml` | **Consolidate** | Keep a tag-triggered publication path, but reduce it to tag and changelog validation, one reusable readiness workflow, and artifact publication. |
| `.github/workflows/release-readiness.yml` | **Consolidate** | The artifact job is useful, but orchestration overlaps the reusable CI, platform, and quality workflows and should be reduced after candidate removals. |

## Workflows and Documentation

| Path | Status | Responsibility | Why it stays or could change |
| --- | --- | --- | --- |
| `.github/workflows/ci.yml` | **Retain** | Fast, reusable Swift build, test, API, TypeScript, example, and symbol checks on ordinary changes. | It is the normal feedback loop. Keep its commands explicit and avoid moving ordinary commands into wrapper scripts. |
| `.github/workflows/platforms.yml` | **Retain** | Builds the package and the portable consumer for the platforms the package promises to support. | A cross-platform promise needs evidence. It is separate because the matrix has distinct toolchains and runtimes from ordinary CI. |
| `.github/workflows/quality.yml` | **Consolidated** | Runs slow diagnostics such as DocC, sanitizers, and stress repetitions. | The fuzz job is removed; deep checks run on schedule, manually, or from release readiness rather than duplicating ordinary CI. |
| `.github/workflows/release-readiness.yml` | **Consolidate** | Composes the retained CI, platform, and deep-quality workflows and packages release artifacts. | It should be the one reusable release-validation workflow. It should contain orchestration and artifact collection, not a second copy of every check. |
| `.github/workflows/release.yml` | **Consolidate and retain** | Validates a version tag and publishes artifacts only after readiness succeeds. | Publication is worth keeping. The clean form is a very small tag-triggered orchestrator: validate tag and changelog, call readiness, publish the resulting artifacts. |
| `.github/dependabot.yml` | **Retain** | Proposes controlled updates for SwiftPM, npm fixtures, and workflow actions. | It has near-zero architectural cost and keeps dependencies visible. |
| `Documentation/Architecture.md` | **Retain** | Explains the current system boundaries and data flow. | It is the shortest route for a contributor to understand the package. |
| `Documentation/Decisions/` | **Retain** | Preserves why long-lived architectural constraints were chosen. | ADRs prevent rediscovering rejected designs. They should remain append-only rather than be replaced by a summary. |
| `AGENTS.md` | **Retain** | Contributor rules, ownership/concurrency model, and roadmap. | It prevents agents and contributors from adding incompatible abstractions. |
| README, `CHANGELOG.md`, and workflows | **Retain** | State the user-facing compatibility, change, and publication contract. | The former standalone policy guides were removed because they repeated repository rules or workflow behavior. |

## Minimal Publication Workflow

The publication path should have exactly two layers:

1. **`release-readiness.yml`** — callable manually or by another workflow. It
   invokes the reusable CI, platform, and deep-quality workflows, then produces
   one verified artifact set: source archive checksums, DocC, symbol graphs,
   benchmark summary, and license metadata.
2. **`release.yml`** — triggered only by a semantic version tag. It verifies
   that the tag has a matching changelog entry, calls readiness, and creates the
   GitHub release from that artifact set. It does not rebuild the package or
   repeat validation logic.

This preserves a reliable publication workflow while making the data flow easy
to read: validate once, package once, publish once.

## Applied Simplification

1. Removed the fuzzing package, launcher, and workflow job.
2. Inlined API compatibility and TypeScript validation into reusable CI.
3. Moved multi-run aggregation into `QuickJSKitBenchmarks`.
4. Removed generated benchmark JSON after preserving the concise report.
5. Consolidated five example targets into one example executable.
6. Kept publication as a small tag-triggered workflow over one reusable
   readiness workflow.

After each step, run the same package tests and public symbol checks. Repository
simplification must not weaken runtime ownership, concurrency, conversion, or
public API guarantees.
