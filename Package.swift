// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kagami",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Kagami", targets: ["Kagami"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Kagami",
            dependencies: [
                "CBZip2",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Kagami"
        ),
        // libbz2 ships with macOS but has no Swift module of its own.
        .systemLibrary(name: "CBZip2", path: "Sources/CBZip2"),
        .testTarget(name: "KagamiTests", dependencies: ["Kagami"], path: "Tests/KagamiTests"),
    ]
)
