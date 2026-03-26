// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceFlow",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "VoiceFlowLib",
            path: "Sources/VoiceFlowLib",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "VoiceFlow",
            dependencies: ["VoiceFlowLib"],
            path: "Sources/VoiceFlow",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "VoiceFlowTests",
            dependencies: ["VoiceFlowLib"],
            path: "Tests/VoiceFlowTests"
        ),
    ]
)
