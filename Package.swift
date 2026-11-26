// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tacet",
    platforms: [.macOS(.v26)],
    targets: [
        .executableTarget(name: "Tacet"),
        .testTarget(name: "TacetTests", dependencies: ["Tacet"]),
    ]
)
