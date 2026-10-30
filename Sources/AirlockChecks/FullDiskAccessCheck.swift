// FullDiskAccessCheck.swift
// AirlockChecks

import AppKit
import Combine
import AirlockCore
import AirlockUI

/// Verifies that Full Disk Access is granted.
@MainActor
public final class FullDiskAccessCheck: FlightCheck, ObservableObject {
    public struct FolderHighlight: Identifiable, Equatable {
        public let id = UUID()
        public let icon: String
        public let name: String

        public init(icon: String, name: String) {
            self.icon = icon
            self.name = name
        }
    }

    public struct Note: Equatable {
        public let icon: String
        public let message: String
        public let tint: NSColor

        public init(icon: String = "lock.shield", message: String, tint: NSColor = .green) {
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
        public let foldersTitle: String?
        public let folderHighlights: [FolderHighlight]
        public let note: Note?

        public init(
            title: String = "Full Disk Access",
            description: String = "Grant Full Disk Access to continue.",
            icon: String = "externaldrive.fill",
            actionLabel: String = "Open Settings",
            detailTitle: String = "Full Disk Access",
            detailDescription: String = "This app needs Full Disk Access to work with files in protected locations.",
            instructions: [String] = [
                "Click \"Open Settings\" to open System Settings.",
                "Find this app in the application list.",
                "Enable Full Disk Access for the app.",
                "Return here after macOS updates the permission."
            ],
            foldersTitle: String? = nil,
            folderHighlights: [FolderHighlight] = [],
            note: Note? = Note(message: "Your files stay on your Mac unless your app explicitly uploads them.")
        ) {
            self.title = title
            self.description = description
            self.icon = icon
            self.actionLabel = actionLabel
            self.detailTitle = detailTitle
            self.detailDescription = detailDescription
            self.instructions = instructions
            self.foldersTitle = foldersTitle
            self.folderHighlights = folderHighlights
            self.note = note
        }

        public static func `default`(
            appName: String = "This app",
            purpose: String = "read and organize files in protected locations",
            folderHighlights: [FolderHighlight] = [],
            foldersTitle: String? = nil,
            privacyNote: String = "Your files stay on your Mac unless your app explicitly uploads them."
        ) -> Configuration {
            Configuration(
                description: "Grant Full Disk Access to let \(appName) continue.",
                detailDescription: "\(appName) needs Full Disk Access to \(purpose).",
                instructions: [
                    "Click \"Open Settings\" to open System Settings.",
                    "Find \"\(appName)\" in the application list.",
                    "Enable Full Disk Access for the app.",
                    "Return here after macOS updates the permission."
                ],
                foldersTitle: foldersTitle,
                folderHighlights: folderHighlights,
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

    let configuration: Configuration
    fileprivate var currentAuthorizationState: PermissionGrantState = PermissionType.fullDiskAccess.authorizationState

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

    public var detailView: NSViewController {
        NativeCheckViewController(check: self)
    }

    public func performAction() {
        PermissionType.fullDiskAccess.openSettings()
    }

    public func confirmManualReview() {
        if case .requiresManualVerification = currentAuthorizationState {
            status = .success
        }
    }

    @MainActor
    public func validate() async -> Bool {
        currentAuthorizationState = PermissionType.fullDiskAccess.authorizationState
        return currentAuthorizationState.isGranted
    }
}
