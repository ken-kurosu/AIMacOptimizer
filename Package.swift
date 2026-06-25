// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIMacOptimizer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "AIMacOptimizer",
            path: "AIMacOptimizer/Sources"
        )
    ]
)
