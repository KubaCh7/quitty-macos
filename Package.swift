// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Quitty",
    platforms: [.macOS(.v12)],
    targets: [
        .executableTarget(
            name: "Quitty",
            path: "Sources/Quitty",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("SwiftUI"),
            ]
        ),
    ]
)
