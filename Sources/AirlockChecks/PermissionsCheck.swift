// PermissionsCheck.swift
// AirlockChecks
//
// A configurable flight check that verifies multiple permissions at once.

import SwiftUI
import Combine
import AirlockCore
import AirlockUI

/// A flight check that verifies multiple system permissions.
///
/// Use this check when your app requires multiple permissions. It displays
/// all permissions in a list and validates that all are granted before passing.
///
/// Example:
/// ```swift
/// PermissionsCheck(
///     permissions: [.accessibility, .fullDiskAccess],
///     title: "System Permissions",
///     description: "Grant the required permissions to continue."
/// )
/// ```
public final class PermissionsCheck: FlightCheck, ObservableObject {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon: String
    public let actionLabel: String = "Review Permissions"

    @Published public var status: CheckStatus = .pending

    private let permissions: [PermissionType]
    private let stateProvider: (PermissionType) -> PermissionGrantState
    private let requestHandler: PermissionChecker.RequestHandler?

    // Single source of truth for permission state and the only poller. Created
    // lazily on the main actor (PermissionChecker is @MainActor) and shared by
    // both `validate()` and the detail view.
    private var _checker: PermissionChecker?
    private var checkerCancellable: AnyCancellable?

    /// Creates a permissions check for the specified permission types.
    ///
    /// - Parameters:
    ///   - permissions: The permissions to check
    ///   - title: Display title for the check (default: "Permissions")
    ///   - description: Description of why permissions are needed
    ///   - icon: SF Symbol for the check (default: "lock.shield")
    public init(
        permissions: [PermissionType],
        title: String = "Permissions",
        description: String = "Grant the required system permissions.",
        icon: String = "lock.shield",
        stateProvider: ((PermissionType) -> PermissionGrantState)? = nil,
        requestHandler: PermissionChecker.RequestHandler? = nil
    ) {
        self.permissions = permissions
        self.title = title
        self.description = description
        self.icon = icon
        self.stateProvider = stateProvider ?? { $0.authorizationState }
        self.requestHandler = requestHandler
    }

    /// The shared permission checker. Lazily created on first access.
    @MainActor
    public var checker: PermissionChecker {
        if let checker = _checker {
            return checker
        }
        let checker = PermissionChecker(
            permissions: permissions,
            stateProvider: stateProvider,
            requestHandler: requestHandler
        )
        // Re-publish so views observing the check react to permission changes.
        checkerCancellable = checker.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        _checker = checker
        return checker
    }

    public var detailView: AnyView {
        AnyView(PermissionsCheckDetailView(check: self))
    }

    public func performAction() {
        Task { @MainActor in
            let checker = self.checker
            checker.checkAllPermissions()
            let unresolved = permissions.filter { !checker.state(for: $0).isGranted }
            let preferred = unresolved.first {
                switch $0.requestAvailability {
                case .inAppPrompt, .openSystemSettings:
                    return true
                case .requiresCustomHandling:
                    return false
                }
            } ?? unresolved.first

            if let permission = preferred {
                _ = await checker.requestAccess(for: permission)
            }
        }
    }

    @MainActor
    public func validate() async -> Bool {
        checker.checkAllPermissions()
        return checker.allGranted
    }

    /// The list of permissions being checked
    public var requiredPermissions: [PermissionType] {
        permissions
    }

    /// Current permission states.
    @MainActor
    public var currentStates: [PermissionType: PermissionGrantState] {
        checker.permissionStates
    }

    /// Currently granted permissions
    @MainActor
    public var currentlyGranted: Set<PermissionType> {
        checker.grantedPermissions
    }

    /// Returns the current state for a permission.
    @MainActor
    public func state(for permission: PermissionType) -> PermissionGrantState {
        checker.state(for: permission)
    }
}

// MARK: - Detail View

struct PermissionsCheckDetailView: View {
    @ObservedObject var check: PermissionsCheck

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 16)

            // Icon
            ZStack {
                Circle()
                    .fill(iconBackgroundColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: check.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            // Title & Description
            VStack(spacing: 8) {
                Text(check.title)
                    .font(.title3)
                    .fontWeight(.semibold)

                Text(check.description)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // Permissions list
            PermissionsGroupView(
                title: "Required Permissions",
                permissions: check.requiredPermissions,
                permissionStates: check.checker.permissionStates
            ) { permission in
                Task {
                    _ = await check.checker.requestAccess(for: permission)
                }
            }
            .padding(.horizontal, 24)

            // Instructions
            if !check.checker.allGranted {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to grant permissions")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    HStack(spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundStyle(.blue)
                        Text("Use the action button to request access directly when supported. Some permissions require System Settings, and app-specific permissions like Automation may require a custom handler from the host app.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(colorScheme == .dark ? 0.15 : 0.08))
                    )
                }
                .padding(.horizontal, 24)
            }

            Spacer()
                .frame(height: 16)
        }
        .onAppear {
            check.checker.startMonitoring(interval: 1.0)
        }
        .onDisappear {
            check.checker.stopMonitoring()
        }
        .onChange(of: check.checker.allGranted) { _, allGranted in
            if allGranted {
                check.status = .success
            }
        }
    }

    private var iconColor: Color {
        switch check.status {
        case .success: return .green
        case .active: return .orange
        default: return .blue
        }
    }

    private var iconBackgroundColor: Color {
        iconColor
    }
}
