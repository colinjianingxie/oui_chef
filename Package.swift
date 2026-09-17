// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OuiChefCore",
    platforms: [.macOS(.v13), .iOS(.v17)],
    products: [.library(name: "OuiChefCore", targets: ["OuiChefCore"])],
    targets: [
        .target(name: "OuiChefCore", path: "OuiChef/Core", resources: [.process("Resources")]),
        .testTarget(name: "OuiChefCoreTests", dependencies: ["OuiChefCore"], path: "Tests")
    ]
)
