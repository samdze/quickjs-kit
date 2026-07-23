// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "QuickJSKitFuzzing",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "QuickJSKitFuzzer",
            dependencies: [
                .product(name: "QuickJSKit", package: "quickjs-kit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
