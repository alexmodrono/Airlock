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
public class AnyFlightCheck: ObservableObject, Identifiable {
    public let id: UUID
    public let title: String
    public let description: String
    public let icon: String
    public let actionLabel: String

    @Published public var status: CheckStatus

    private let _detailView: () -> AnyView
    private let _performAction: () -> Void
    private let _validate: @MainActor () async -> Bool
    private var cancellables = Set<AnyCancellable>()

    public init<C: FlightCheck>(_ check: C) {
        self.id = check.id
        self.title = check.title
        self.description = check.description
        self.icon = check.icon
        self.actionLabel = check.actionLabel
        self.status = check.status

        self._detailView = { check.detailView }
        self._performAction = check.performAction
        self._validate = check.validate

        // Observe changes to the underlying check's status
        check.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.status = check.status
                }
            }
            .store(in: &cancellables)
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
