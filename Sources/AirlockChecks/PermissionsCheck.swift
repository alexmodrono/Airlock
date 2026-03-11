// PermissionsCheck.swift
// AirlockChecks
//
// A configurable flight check that verifies multiple permissions at once.

import SwiftUI
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
    @Published private var permissionStates: [PermissionType: PermissionGrantState] = [:]

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

    public var detailView: AnyView {
        AnyView(PermissionsCheckDetailView(check: self))
    }

    public func performAction() {
        let unresolvedPermissions = permissions.filter { !resolvedState(for: $0).isGranted }
        let preferredPermission = unresolvedPermissions.first {
            switch $0.requestAvailability {
            case .inAppPrompt, .openSystemSettings:
                return true
            case .requiresCustomHandling:
                return false
            }
        } ?? unresolvedPermissions.first

        if let permission = preferredPermission {
            Task { @MainActor in
                _ = await requestAccess(for: permission)
            }
        }
    }

    @MainActor
    public func validate() async -> Bool {
        var updatedStates: [PermissionType: PermissionGrantState] = [:]
        for permission in permissions {
            updatedStates[permission] = stateProvider(permission)
        }
        permissionStates = updatedStates

        // All permissions must be granted
        return permissions.allSatisfy { updatedStates[$0]?.isGranted == true }
    }

    /// The list of permissions being checked
    public var requiredPermissions: [PermissionType] {
        permissions
    }

    /// Current permission states.
    public var currentStates: [PermissionType: PermissionGrantState] {
        permissionStates
    }

    /// Currently granted permissions
    public var currentlyGranted: Set<PermissionType> {
        Set(permissionStates.compactMap { $0.value.isGranted ? $0.key : nil })
    }

    /// Returns the current state for a permission.
    public func state(for permission: PermissionType) -> PermissionGrantState {
        permissionStates[permission] ?? stateProvider(permission)
    }

    fileprivate func resolvedState(for permission: PermissionType) -> PermissionGrantState {
        state(for: permission)
    }

    @MainActor
    fileprivate func requestAccess(for permission: PermissionType) async -> PermissionGrantState {
        let state = if let requestHandler {
            await requestHandler(permission)
        } else {
            await permission.requestAccess()
        }

        permissionStates[permission] = state
        return state
    }
}

// MARK: - Detail View

struct PermissionsCheckDetailView: View {
    @ObservedObject var check: PermissionsCheck
    @StateObject private var permissionChecker: PermissionChecker

    @Environment(\.colorScheme) private var colorScheme

    init(check: PermissionsCheck) {
        self.check = check
        self._permissionChecker = StateObject(
            wrappedValue: PermissionChecker(
                permissions: check.requiredPermissions,
                stateProvider: { permission in
                    check.resolvedState(for: permission)
                },
                requestHandler: { permission in
                    await check.requestAccess(for: permission)
                }
            )
        )
    }

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
                permissionStates: permissionChecker.permissionStates
            ) { permission in
                Task {
                    _ = await permissionChecker.requestAccess(for: permission)
                }
            }
            .padding(.horizontal, 24)

            // Instructions
            if !permissionChecker.allGranted {
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
            permissionChecker.startMonitoring(interval: 1.0)
        }
        .onDisappear {
            permissionChecker.stopMonitoring()
        }
        .onChange(of: permissionChecker.allGranted) { _, allGranted in
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
