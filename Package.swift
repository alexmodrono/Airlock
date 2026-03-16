// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Airlock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
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
        // ObjC helpers for exception-safe AppKit interop
        .target(
            name: "AirlockObjC",
            dependencies: [],
            publicHeadersPath: "include"
        ),
        // UI: SwiftUI views and components
        .target(
            name: "AirlockUI",
            dependencies: [
                "AirlockCore",
                "AirlockObjC",
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
        .testTarget(
            name: "AirlockTests",
            dependencies: ["Airlock"]
        ),
    ]
)
