// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "QuickJSKitPlatformSmoke",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .tvOS(.v16),
        .watchOS(.v9),
        .visionOS(.v1),
    ],
    dependencies: [
        .package(path: "../.."),
    ],
    targets: [
        .executableTarget(
            name: "QuickJSKitPlatformSmoke",
            dependencies: [
                .product(name: "QuickJSKit", package: "quickjs-kit"),
                .product(name: "QuickJSKitMacros", package: "quickjs-kit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
