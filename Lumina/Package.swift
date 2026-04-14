// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.
// Lumina – AI-powered reminders, task management, and focus app for macOS/iOS/watchOS.

import PackageDescription

let package = Package(
    name: "Lumina",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .executable(name: "Lumina", targets: ["Lumina"])
    ],
    targets: [
        .executableTarget(
            name: "Lumina",
            path: "Sources/Lumina",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "LuminaTests",
            dependencies: ["Lumina"],
            path: "Tests/LuminaTests"
        )
    ]
)
