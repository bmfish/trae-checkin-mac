// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "TraeCheckinMac",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TraeCheckinMac",
            path: "Sources/TraeCheckinMac"
        )
    ]
)
