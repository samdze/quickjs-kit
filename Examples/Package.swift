// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "QuickJSKitExamples",
    platforms: [
        .macOS(.v13),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "QuickJSKitExamples",
            dependencies: [
                .product(name: "QuickJSKit", package: "quickjs-kit"),
                .product(name: "QuickJSKitMacros", package: "quickjs-kit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
