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
            name: "TypedEvaluation",
            dependencies: [.product(name: "QuickJSKit", package: "quickjs-kit")]
        ),
        .executableTarget(
            name: "AsyncHostAPI",
            dependencies: [.product(name: "QuickJSKit", package: "quickjs-kit")]
        ),
        .executableTarget(
            name: "ModuleEmbedding",
            dependencies: [.product(name: "QuickJSKit", package: "quickjs-kit")]
        ),
        .executableTarget(
            name: "RuntimeTemplates",
            dependencies: [.product(name: "QuickJSKit", package: "quickjs-kit")]
        ),
        .executableTarget(
            name: "TypeScriptWorkspace",
            dependencies: [
                .product(name: "QuickJSKit", package: "quickjs-kit"),
                .product(name: "QuickJSKitMacros", package: "quickjs-kit"),
            ]
        ),
    ],
    swiftLanguageModes: [.v6]
)
