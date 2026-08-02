# Changelog

All notable changes to QuickJSKit will be documented here.

The format follows Keep a Changelog, and released versions will follow Semantic
Versioning.

## Unreleased

### Changed

- Windows runtimes omit JavaScript's POSIX-thread-based `Atomics` intrinsic
  while retaining the complete QuickJSKit public API.

## [1.0.0-beta.1] - 2026-07-29

### Added

- A modern actor-isolated QuickJS runtime with direct Codable conversion.
- Typed Swift bindings, native Promise bridging, ES modules, custom loaders,
  interruption, resource limits, and runtime observability.
- Deterministic TypeScript declarations, rich TSDoc, source maps, and managed
  editor workspaces.
- Declarative runtime templates, prepared programs, startup actions, and
  prewarmed one-shot provisioning.
- `@JavaScriptExport` support for value types and live Swift host types.
- A restricted configuration profile and pending asynchronous host-call
  backpressure.

### Changed

- Runtime resource reporting is exposed as `JavaScriptResourceUsage` through
  `resourceUsage()`, replacing the former memory-only terminology.
- Repository validation now uses two focused scripts, one benchmark executable,
  one standalone examples executable, and reusable publication workflows.
- Removed the repository-owned fuzzing harness and generated benchmark reports
  that did not participate in a package contract.

### Security

- Added bounded pending host calls and documented the distinction between
  in-process resource controls and operating-system isolation.
