# Compatibility Policy

QuickJSKit requires Swift 6.3 or later and strict concurrency. The declared
platforms are macOS 13, iOS 16, tvOS 16, watchOS 9, visionOS 1, Linux, Windows,
and Android where supported by the official Swift SDK and upstream QuickJS.
The public Swift API is identical on every supported platform.

The package remains pre-release until an explicit release decision. Before 1.0,
source-breaking cleanup may occur with migration notes. After 1.0, public Swift
APIs and documented JavaScript-visible behavior follow Semantic Versioning.

The following are part of the compatibility contract:

- public Swift declarations and actor isolation;
- documented conversion and error behavior;
- JavaScript-visible names, signatures, module specifiers, and property rules;
- generated TypeScript type shapes and managed workspace file formats;
- stable macro diagnostic identifiers.

Diagnostic wording may improve without a major version when the identifier and
meaning remain stable. Formatting-only changes to generated declarations may be
made compatibly when they preserve TypeScript semantics and deterministic output.

QuickJS bytecode is private, process-local, version-specific cache data. It is
never a persistence or compatibility format. The exact vendored engine version
is recorded in `Sources/CQuickJS/UPSTREAM.json`.

QuickJS upgrades require an isolated commit, updated checksums, review of
upstream behavior changes, the complete platform matrix, sanitizer validation,
and comparable before-and-after benchmarks.
