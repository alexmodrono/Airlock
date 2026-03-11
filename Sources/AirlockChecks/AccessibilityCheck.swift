// AccessibilityCheck.swift
// AirlockChecks

import SwiftUI
import AirlockCore

/// Verifies that Accessibility permissions are granted.
public final class AccessibilityCheck: FlightCheck, ObservableObject {
    public struct Note: Equatable {
        public let icon: String
        public let message: String
        public let tint: Color

        public init(icon: String = "lock.shield", message: String, tint: Color = .green) {
            self.icon = icon
            self.message = message
            self.tint = tint
        }
    }

    public struct Configuration {
        public let title: String
        public let description: String
        public let icon: String
        public let actionLabel: String
        public let detailTitle: String
        public let detailDescription: String
        public let instructions: [String]
        public let note: Note?

        public init(
            title: String = "Accessibility Access",
            description: String = "Grant accessibility access to continue.",
            icon: String = "hand.raised.fill",
            actionLabel: String = "Open Settings",
            detailTitle: String = "Accessibility Access",
            detailDescription: String = "This app needs Accessibility access to observe and interact with other applications.",
            instructions: [String] = [
                "Click \"Open Settings\" to open System Settings.",
                "Find this app in the application list.",
                "Enable the Accessibility toggle.",
                "Return here after macOS updates the permission."
            ],
            note: Note? = Note(message: "Accessibility access is only used for the features you enable.")
        ) {
            self.title = title
            self.description = description
            self.icon = icon
            self.actionLabel = actionLabel
            self.detailTitle = detailTitle
            self.detailDescription = detailDescription
            self.instructions = instructions
            self.note = note
        }

        public static func `default`(
            appName: String = "This app",
            purpose: String = "observe and interact with other applications",
            privacyNote: String = "Accessibility access is only used for the features you enable."
        ) -> Configuration {
            Configuration(
                description: "Grant accessibility access to let \(appName) continue.",
                detailDescription: "\(appName) needs Accessibility access to \(purpose).",
                instructions: [
                    "Click \"Open Settings\" to open System Settings.",
                    "Find \"\(appName)\" in the application list.",
                    "Enable the Accessibility toggle.",
                    "Return here after macOS updates the permission."
                ],
                note: Note(message: privacyNote)
            )
        }
    }

    public let id = UUID()
    public let title: String
    public let description: String
    public let icon: String
    public let actionLabel: String

    @Published public var status: CheckStatus = .pending

    fileprivate let configuration: Configuration

    public convenience init() {
        self.init(configuration: .default())
    }

    public init(configuration: Configuration = .default()) {
        self.configuration = configuration
        self.title = configuration.title
        self.description = configuration.description
        self.icon = configuration.icon
        self.actionLabel = configuration.actionLabel
    }

    public var detailView: AnyView {
        AnyView(AccessibilityDetailView(check: self))
    }

    public func performAction() {
        PermissionType.accessibility.openSettings()
    }

    @MainActor
    public func validate() async -> Bool {
        PermissionType.accessibility.isGranted
    }
}

// MARK: - Detail View

struct AccessibilityDetailView: View {
    @ObservedObject var check: AccessibilityCheck

    var body: some View {
        CheckDetailView(
            icon: check.configuration.icon,
            title: check.configuration.detailTitle,
            description: check.configuration.detailDescription,
            status: check.status
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("How to Enable")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .tracking(1)

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(check.configuration.instructions.enumerated()), id: \.offset) { index, instruction in
                        InstructionStep(index + 1, instruction)
                    }
                }

                if let note = check.configuration.note {
                    HStack(spacing: 8) {
                        Image(systemName: note.icon)
                            .foregroundStyle(note.tint)
                        Text(note.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(note.tint.opacity(0.1))
                    )
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 16)
        }
    }
}
