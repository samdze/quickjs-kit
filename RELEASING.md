# Release Process

QuickJSKit releases are reproducible, reviewed operations. Phase 9 prepares the
automation but does not publish a release.

## Candidate checklist

1. Start from a clean checkout and update the `Unreleased` changelog.
2. Verify `Package.resolved`, npm locks, vendored QuickJS checksums, licenses,
   and the SPDX SBOM.
3. Run the blocking platform matrix, complete test suite, strict-concurrency
   checks, DocC, TypeScript/TSDoc fixtures, and symbol-graph audit.
4. Run AddressSanitizer, LeakSanitizer, supported undefined-behavior and thread
   sanitizers, fuzzing, and long stress suites.
5. Run five comparable release benchmark passes with at least 100 samples and
   investigate repeated regressions above ten percent.
6. Build every standalone example and a clean source archive.
7. Run the manual release-readiness workflow and review every uploaded artifact.
8. Review public API changes against the recorded compatibility baseline.

## Release checklist

1. Choose a semantic `vX.Y.Z` tag matching the changelog.
2. Ensure the release commit and candidate artifacts are reviewed and signed
   according to repository policy.
3. Push the tag. The tag-triggered workflow revalidates its version and changelog
   entry before creating the GitHub release.
4. Verify release notes, checksums, licenses, SBOM, DocC archive, symbol graphs,
   and benchmark report.
5. Update supported versions in `SECURITY.md`.

Never publish QuickJS bytecode as an artifact or accept externally supplied
bytecode as input.
