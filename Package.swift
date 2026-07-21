// swift-tools-version: 6.3

import PackageDescription

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
        .executableTarget(
            name: "QuickJSKitBenchmarks",
            dependencies: ["QuickJSKit"],
            path: "Benchmarks/QuickJSKitBenchmarks"
        ),
        .testTarget(
            name: "QuickJSKitTests",
            dependencies: ["QuickJSKit"]
        ),
    ],
    swiftLanguageModes: [.v6],
    cLanguageStandard: .gnu11
)
