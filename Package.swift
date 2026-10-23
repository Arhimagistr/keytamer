// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Keytamer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Keytamer",
            path: "Sources/Keytamer",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])],
            linkerSettings: [.linkedFramework("IOKit")]
        )
    ]
)
