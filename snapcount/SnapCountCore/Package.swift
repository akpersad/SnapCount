// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SnapCountCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SnapCountCore", targets: ["SnapCountCore"]),
    ],
    targets: [
        .target(name: "SnapCountCore"),
        // Offline enrollment and threshold tuning over ReferencePhotos/. macOS only; the app
        // does its own enrollment from the photo picker.
        .executableTarget(name: "snapcount-enroll", dependencies: ["SnapCountCore"]),
        .testTarget(name: "SnapCountCoreTests", dependencies: ["SnapCountCore"]),
    ]
)
