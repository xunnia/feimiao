// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QingJiCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "QingJiCore", targets: ["QingJiCore"]),
    ],
    targets: [
        .target(name: "QingJiCore"),
        .testTarget(name: "QingJiCoreTests", dependencies: ["QingJiCore"]),
    ]
)
