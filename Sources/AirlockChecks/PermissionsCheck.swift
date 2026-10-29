// PermissionsCheck.swift
// AirlockChecks
//
// A configurable flight check that verifies multiple permissions at once.

import AppKit
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
@MainActor
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

    public var detailView: NSViewController {
        NativeCheckViewController(check: self)
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
