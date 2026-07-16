// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotchBar",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "NotchBar",
            path: "Sources/NotchBar",
            resources: [
                .process("Resources"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ])
    ]
)
