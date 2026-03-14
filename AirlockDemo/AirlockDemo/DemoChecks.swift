// DemoChecks.swift
// AirlockDemo
//
// FlightCheck-based demo examples.

import SwiftUI
import Airlock

/// Creates a welcome check with demo content.
func createDemoWelcomeCheck() -> WelcomeCheck {
    WelcomeCheck(
        appName: "Airlock Demo",
        subtitle: "This example shows the FlightCheck API in action.",
        features: [
            .init(
                icon: "checkmark.shield.fill",
                title: "Structured Onboarding",
                description: "Move through setup steps with a predictable flow.",
                color: .green
            ),
            .init(
                icon: "rectangle.split.2x1.fill",
                title: "Contextual Help",
                description: "Keep status and detailed instructions visible together.",
                color: .blue
            ),
            .init(
                icon: "paintbrush.fill",
                title: "Native UI",
                description: "Use materials, motion, and SwiftUI on macOS.",
                color: .orange
            )
        ],
        highlightFeatures: [
            .init(icon: "checkmark.shield.fill", title: "Structured Flow", color: .green),
            .init(icon: "rectangle.split.2x1.fill", title: "Contextual Detail", color: .blue),
            .init(icon: "paintbrush.fill", title: "Native macOS UI", color: .orange)
        ],
        autoAdvanceAfter: 4.0
    )
}

/// Creates a permission check using the reusable permission components.
func createDemoPermissionCheck() -> PermissionsCheck {
    PermissionsCheck(
        permissions: [.accessibility, .screenRecording],
        title: "Permissions",
        description: "Grant the sample permissions used by this demo.",
        icon: "lock.shield.fill"
    )
}

/// Creates a setup check with simulated tasks.
func createDemoSetupCheck() -> SetupCheck {
    SetupCheck(
        taskNames: [
            "Preparing workspace...",
            "Loading configuration...",
            "Starting local services...",
            "Finalizing setup..."
        ],
        taskDuration: 0.6,
        title: "Setup",
        description: "Run a few simulated setup tasks."
    )
}
