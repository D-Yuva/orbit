// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Orbit",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Orbit", targets: ["Orbit"])],
    targets: [
        .target(name: "OrbitCore"),
        .executableTarget(name: "Orbit", dependencies: ["OrbitCore"], resources: [.process("Assets")]),
        .testTarget(name: "OrbitCoreTests", dependencies: ["OrbitCore"])
    ]
)
