// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EdgePeek",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "EdgePeek", targets: ["EdgePeek"]),
        .executable(name: "edgepeek-cli", targets: ["EdgePeekCLI"])
    ],
    targets: [
        .target(
            name: "EdgePeekCore",
            path: "Sources/EdgePeekCore"
        ),
        .executableTarget(
            name: "EdgePeek",
            dependencies: ["EdgePeekCore"],
            path: "Sources/EdgePeek",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .executableTarget(
            name: "EdgePeekCLI",
            dependencies: ["EdgePeekCore"],
            path: "Sources/EdgePeekCLI"
        ),
        .testTarget(
            name: "EdgePeekCoreTests",
            dependencies: ["EdgePeekCore"],
            path: "Tests/EdgePeekCoreTests"
        ),
        .testTarget(
            name: "EdgePeekTests",
            dependencies: ["EdgePeek", "EdgePeekCore"],
            path: "Tests/EdgePeekTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
