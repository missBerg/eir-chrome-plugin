// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "EirViewer",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "EirViewer",
            dependencies: ["Yams"],
            path: "Sources/EirViewer",
            resources: [.process("Resources/")],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist"
                ])
            ]
        ),
        .testTarget(
            name: "EirViewerTests",
            dependencies: ["EirViewer", "Yams"],
            path: "Tests/EirViewerTests"
        ),
    ]
)
