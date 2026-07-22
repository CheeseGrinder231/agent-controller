// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "AgentController",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AgentController", targets: ["AgentControllerApp"])
    ],
    targets: [
        .target(name: "AgentControllerCore"),
        .target(
            name: "AgentControllerMac",
            dependencies: ["AgentControllerCore"]
        ),
        .executableTarget(
            name: "AgentControllerApp",
            dependencies: ["AgentControllerCore", "AgentControllerMac"]
        ),
        .testTarget(
            name: "AgentControllerCoreTests",
            dependencies: ["AgentControllerCore"]
        ),
        .testTarget(
            name: "AgentControllerMacTests",
            dependencies: ["AgentControllerCore", "AgentControllerMac"]
        )
    ]
)
