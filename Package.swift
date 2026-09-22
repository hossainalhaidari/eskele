// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Eskele",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Eskele", targets: ["Eskele"]),
        .library(name: "DockPrefsKit", targets: ["DockPrefsKit"]),
        .library(name: "TrashKit", targets: ["TrashKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"),
    ],
    targets: [
        .executableTarget(
            name: "Eskele",
            dependencies: [
                "DockPrefsKit",
                "TrashKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/Eskele"
        ),
        .target(name: "DockPrefsKit", path: "Sources/DockPrefsKit"),
        .target(name: "TrashKit", path: "Sources/TrashKit"),
        .testTarget(name: "EskeleTests", dependencies: ["Eskele"], path: "Tests/EskeleTests"),
        .testTarget(name: "DockPrefsKitTests", dependencies: ["DockPrefsKit"], path: "Tests/DockPrefsKitTests"),
        .testTarget(name: "TrashKitTests", dependencies: ["TrashKit"], path: "Tests/TrashKitTests"),
    ]
)
