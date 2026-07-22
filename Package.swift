// swift-tools-version: 6.3

import PackageDescription
import CompilerPluginSupport

let package = Package(
    name: "QuickJSKit",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    products: [
        .library(name: "QuickJSKit", targets: ["QuickJSKit"]),
        .library(name: "QuickJSKitMacros", targets: ["QuickJSKitMacros"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/swiftlang/swift-syntax.git",
            from: "603.0.0"
        ),
    ],
    targets: [
        .target(
            name: "CQuickJS",
            path: "Sources/CQuickJS",
            sources: [
                "cutils.c",
                "dtoa.c",
                "libregexp.c",
                "libunicode.c",
                "quickjs.c",
            ],
            publicHeadersPath: "include",
            cSettings: [
                .define("_GNU_SOURCE"),
                .define("CONFIG_VERSION", to: "\"2026-06-04\""),
            ]
        ),
        .target(
            name: "QuickJSKit",
            dependencies: ["CQuickJS"]
        ),
        .target(
            name: "QuickJSKitMacros",
            dependencies: ["QuickJSKit", "_QuickJSKitMacroPlugin"]
        ),
        .macro(
            name: "_QuickJSKitMacroPlugin",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
            ]
        ),
        .executableTarget(
            name: "QuickJSKitBenchmarks",
            dependencies: ["QuickJSKit", "QuickJSKitMacros"],
            path: "Benchmarks/QuickJSKitBenchmarks"
        ),
        .testTarget(
            name: "QuickJSKitTests",
            dependencies: ["QuickJSKit"]
        ),
        .testTarget(
            name: "QuickJSKitMacroTests",
            dependencies: [
                "QuickJSKit",
                "QuickJSKitMacros",
                "_QuickJSKitMacroPlugin",
            ]
        ),
    ],
    swiftLanguageModes: [.v6],
    cLanguageStandard: .gnu11
)
