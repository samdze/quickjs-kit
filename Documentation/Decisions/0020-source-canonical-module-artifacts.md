# ADR 0020: Source-canonical compile-only module artifacts

- Status: Accepted
- Date: 2026-07-21

## Context

Creating many identically configured runtimes repeatedly parses the same
registered module source. QuickJS can serialize compile-only module objects,
but its bytecode format is tied to the exact engine build and is unsafe as an
untrusted or stable interchange format.

An optimization must not alter module identity, resolution, diagnostics,
evaluation timing, or the ownership rule that every runtime has an independent
heap.

## Decision

Template construction parses each explicitly registered source module with
compile-only evaluation. Syntax errors fail construction with the canonical
source URL. Successful compilation may be serialized into a private copied byte
buffer. Serialization failure is nonfatal and leaves the module source-only.

Each created runtime first registers canonical source, then reads eligible
artifacts into its own context without evaluating them. Imports continue
through the existing resolver and native module path. Module bodies execute
only when imported and retain QuickJS evaluation-once semantics.

Artifacts never cross a process boundary, are never public or persisted, and
are never accepted from callers. Loader-provided and transient modules are not
cached. If an artifact cannot be read, the incomplete runtime is destroyed and
creation retries once from canonical source before any Swift factory runs.
Logical module resolution and evaluation failures do not trigger fallback.

## Consequences

High-volume provisioning avoids repeated parsing for eligible source while
preserving source as the diagnostic and behavioral authority. Cache failure
cannot leave a partially polluted runtime or invoke a factory twice.

The cache is deliberately narrower than a build artifact system. Persistent
bytecode, cache directories, public cache keys, externally supplied bytecode,
and evaluated heap snapshots remain unsupported.
