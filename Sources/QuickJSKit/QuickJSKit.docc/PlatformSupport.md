# Platform Support

Use one public API across Apple platforms, Linux, Windows, and Android.

QuickJSKit requires Swift 6.3 or newer. Apple deployment targets are macOS 13,
iOS 16, tvOS 16, watchOS 9, and visionOS 1. Linux, Windows x86-64, and Android
use the same Swift and C sources.

The core library does not depend on Darwin, Glibc, WinSDK, Android APIs,
Objective-C, or UI frameworks. A platform-specific upstream incompatibility is
isolated behind a minimal documented patch rather than changing public API.

The release qualification matrix builds and tests native desktop platforms,
builds generic Apple device consumers, and builds Android AArch64 plus an
emulator smoke application. The portable smoke consumer exercises typed
evaluation, Codable, macros, native Promises, modules, and runtime templates.

When troubleshooting:

- verify the exact Swift 6.3 toolchain;
- verify vendored sources with `Scripts/verify-vendored-quickjs.sh`;
- clean only the affected package build directory;
- confirm the target has the package's documented minimum platform;
- reproduce with the standalone `IntegrationTests/PlatformSmoke` package.
