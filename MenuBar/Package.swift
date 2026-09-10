// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ETHZVPNMenuBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "VPNShared"),
        .executableTarget(name: "ETHZVPNHelper", dependencies: ["VPNShared"]),
        .executableTarget(name: "ETHZVPNCLI", dependencies: ["VPNShared"]),
        .testTarget(name: "VPNSharedTests", dependencies: ["VPNShared"]),
        .executableTarget(
            name: "ETHZVPNMenuBar",
            dependencies: ["VPNShared"],
            path: "Sources/ETHZVPNMenuBar",
            resources: [.copy("Resources")]
        )
    ]
)
