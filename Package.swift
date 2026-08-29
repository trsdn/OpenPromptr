// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "OpenPromptr",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "OpenPromptr",
            targets: ["OpenPromptr"]
        )
    ],
    targets: [
        .target(
            name: "OpenPromptrCore"
        ),
        // Objective-C bridge to the private CGVirtualDisplay API. It lives in
        // its own target because a single SwiftPM target cannot mix Swift and
        // Objective-C sources. Compiled with ARC.
        .target(
            name: "VirtualDisplayBridge",
            cSettings: [
                .unsafeFlags(["-fobjc-arc"])
            ],
            linkerSettings: [
                .linkedFramework("Foundation"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .executableTarget(
            name: "OpenPromptr",
            dependencies: ["OpenPromptrCore", "VirtualDisplayBridge"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("CoreImage"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Metal"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("SwiftUI")
            ]
        ),
        .testTarget(
            name: "OpenPromptrCoreTests",
            dependencies: ["OpenPromptrCore"]
        )
    ],
    swiftLanguageModes: [.v6]
)
