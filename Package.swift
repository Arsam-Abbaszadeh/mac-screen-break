// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacScreenBreak",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacScreenBreak", targets: ["MacScreenBreak"])
    ],
    targets: [
        .executableTarget(
            name: "MacScreenBreak",
            path: "Sources"
        )
    ]
)
