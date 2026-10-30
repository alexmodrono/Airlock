// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Airlock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "AirlockDemo", targets: ["AirlockDemo"]),
        // Umbrella library - use this for most cases
        .library(
            name: "Airlock",
            targets: ["Airlock"]
        ),
        // Individual modules for fine-grained control
        .library(
            name: "AirlockCore",
            targets: ["AirlockCore"]
        ),
        .library(
            name: "AirlockUI",
            targets: ["AirlockUI"]
        ),
        .library(
            name: "AirlockChecks",
            targets: ["AirlockChecks"]
        ),
    ],
    dependencies: [
        // Lottie for animations (using lightweight SPM variant)
        .package(url: "https://github.com/airbnb/lottie-spm.git", from: "4.4.0")
    ],
    targets: [
        // Core: Data models, protocols, state management
        .target(
            name: "AirlockCore",
            dependencies: []
        ),
        // UI: Native AppKit window and view controllers
        .target(
            name: "AirlockUI",
            dependencies: [
                "AirlockCore",
                .product(name: "Lottie", package: "lottie-spm")
            ],
            resources: [
                .process("Resources")
            ]
        ),
        // Checks: Pre-built flight checks
        .target(
            name: "AirlockChecks",
            dependencies: ["AirlockCore", "AirlockUI"]
        ),
        // Umbrella: Re-exports all modules
        .target(
            name: "Airlock",
            dependencies: ["AirlockCore", "AirlockUI", "AirlockChecks"]
        ),
        .executableTarget(
            name: "AirlockDemo",
            dependencies: ["Airlock"],
            path: "AirlockDemo/AirlockDemo",
            exclude: ["Assets.xcassets", "AirlockDemo.entitlements", "Info.plist"]
        ),
        .testTarget(
            name: "AirlockTests",
            dependencies: ["Airlock"]
        ),
    ]
)
