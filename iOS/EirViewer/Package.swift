// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EirViewer",
    platforms: [.iOS(.v17)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "EirViewer",
            dependencies: [
                "Yams",
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/EirViewer"
        ),
        .testTarget(
            name: "EirViewerTests",
            dependencies: ["EirViewer", "Yams"],
            path: "Tests/EirViewerTests"
        ),
    ]
)
