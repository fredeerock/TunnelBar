// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GPVpnGUI",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "GPVpnGUI",
            path: "Sources/GPVpnGUI"
        )
    ]
)
