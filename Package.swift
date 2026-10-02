// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "VolumeTweak",
    platforms: [.macOS("14.2")],
    targets: [
        .executableTarget(name: "VolumeTweak", path: "Sources/VolumeTweak")
    ]
)
