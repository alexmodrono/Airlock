// FlightCheck.swift
// Airlock

import SwiftUI
import Combine

/// Protocol defining a single check in the onboarding "Flight Check" sequence.
///
/// Each check represents a system requirement that must be satisfied before
/// the user can proceed to the main application.
public protocol FlightCheck: Identifiable, ObservableObject {
    /// Unique identifier for this check
    var id: UUID { get }

    /// Display title (e.g., "Accessibility Access")
    var title: String { get }

    /// Explanation of why this check is needed
    var description: String { get }

    /// SF Symbol name for the check icon
    var icon: String { get }

    /// Current status of this check
    var status: CheckStatus { get set }

    /// The view to display in the right column when this check is focused
    @ViewBuilder
    var detailView: AnyView { get }

    /// Label for the action button (e.g., "Grant Access", "Connect")
    var actionLabel: String { get }

    /// Performs the required action (e.g., opens System Settings)
    func performAction()

    /// Validates whether the check passes.
    /// This is called periodically to update the status.
    @MainActor
    func validate() async -> Bool
}

// MARK: - Default Implementations

public extension FlightCheck {
    var actionLabel: String { "Enable" }
}

// MARK: - Type Erasure

/// A type-erased wrapper around any FlightCheck.
///
/// The wrapper does not store its own copy of the status. Reads and writes
/// pass straight through to the underlying check, so there is a single source
/// of truth and the two can never drift. Any change to the underlying check is
/// republished so SwiftUI views observing the wrapper stay up to date.
public class AnyFlightCheck: ObservableObject, Identifiable {
    public let id: UUID
    public let title: String
    public let description: String
    public let icon: String
    public let actionLabel: String

    /// Read/write pass-through to the wrapped check's status.
    public var status: CheckStatus {
        get { _getStatus() }
        set { _setStatus(newValue) }
    }

    private let _getStatus: () -> CheckStatus
    private let _setStatus: (CheckStatus) -> Void
    private let _detailView: () -> AnyView
    private let _performAction: () -> Void
    private let _validate: @MainActor () async -> Bool
    private var cancellable: AnyCancellable?

    public init<C: FlightCheck>(_ check: C) {
        self.id = check.id
        self.title = check.title
        self.description = check.description
        self.icon = check.icon
        self.actionLabel = check.actionLabel

        self._getStatus = { check.status }
        self._setStatus = { check.status = $0 }
        self._detailView = { check.detailView }
        self._performAction = check.performAction
        self._validate = check.validate

        // Forward the underlying check's change notifications so views observing
        // the wrapper re-render. objectWillChange fires before the value lands,
        // so consumers that need the post-change value must read it after the
        // current run-loop turn (see AirlockManager).
        self.cancellable = check.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    public var detailView: AnyView {
        _detailView()
    }

    public func performAction() {
        _performAction()
    }

    @MainActor
    public func validate() async -> Bool {
        await _validate()
    }
}
