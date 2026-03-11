// AirlockManager.swift
// Airlock

import SwiftUI
import Combine

/// Manages the state and lifecycle of the onboarding "Flight Check" sequence.
///
/// The manager orchestrates validation of all checks and determines when
/// the user can proceed to the main application.
@MainActor
public final class AirlockManager: ObservableObject {
    /// All flight checks in order
    @Published public private(set) var checks: [AnyFlightCheck]

    /// Index of the currently focused check
    @Published public var focusedIndex: Int = 0

    /// Whether all checks have passed
    @Published public private(set) var isComplete: Bool = false

    /// Whether the airlock sequence is currently active
    @Published public var isActive: Bool = true

    /// The app name to display in the UI
    public let appName: String

    /// The app icon name (from asset catalog)
    public let appIconName: String?

    private var validationTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var isRunningValidationLoop = false

    /// Creates a new AirlockManager with the specified checks.
    ///
    /// - Parameters:
    ///   - appName: The name of the app (e.g., "MyApp")
    ///   - appIconName: Optional asset catalog image name for the app icon
    ///   - checks: Array of flight checks to validate
    public init<C: FlightCheck>(
        appName: String,
        appIconName: String? = nil,
        checks: [C]
    ) {
        self.appName = appName
        self.appIconName = appIconName
        self.checks = checks.map { AnyFlightCheck($0) }

        setupObservers()
    }

    /// Convenience initializer accepting type-erased checks directly.
    public init(
        appName: String,
        appIconName: String? = nil,
        erasedChecks: [AnyFlightCheck]
    ) {
        self.appName = appName
        self.appIconName = appIconName
        self.checks = erasedChecks

        setupObservers()
    }

    private func setupObservers() {
        // Observe all check statuses
        for check in checks {
            check.$status
                .sink { [weak self] _ in
                    self?.updateCompletionStatus()
                }
                .store(in: &cancellables)
        }
    }

    /// Starts the validation loop for all checks.
    public func startValidation() {
        validationTask?.cancel()
        validationTask = Task {
            await runValidationLoop()
        }
    }

    /// Stops the validation loop.
    public func stopValidation() {
        validationTask?.cancel()
        validationTask = nil
    }

    /// Marks the airlock as complete and transitions to the main app.
    public func complete() {
        isActive = false
        stopValidation()
    }

    /// Focuses on a specific check by index.
    public func focusCheck(at index: Int) {
        guard index >= 0, index < checks.count else { return }
        focusedIndex = index
    }

    /// Returns the currently focused check.
    public var focusedCheck: AnyFlightCheck? {
        guard focusedIndex >= 0, focusedIndex < checks.count else { return nil }
        return checks[focusedIndex]
    }

    // MARK: - Private

    private func runValidationLoop() async {
        isRunningValidationLoop = true
        defer { isRunningValidationLoop = false }

        // Initial pass: set all to checking then validate
        for (index, check) in checks.enumerated() {
            guard !Task.isCancelled else { return }

            // Focus on current check
            focusedIndex = index
            check.status = .checking

            // Small delay for visual feedback
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

            let passed = await check.validate()
            check.status = passed ? .success : .active

            // If passed, move to next; if not, stay focused
            if !passed {
                // Wait for user action, then re-validate periodically
                await waitForCheckToPass(check, at: index)
            } else {
                // Pause to let user see the success state before moving to next check
                try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
            }
        }

        updateCompletionStatus()
    }

    private func waitForCheckToPass(_ check: AnyFlightCheck, at index: Int) async {
        while !Task.isCancelled && check.status != .success {
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            guard !Task.isCancelled else { return }

            // Re-validate
            let passed = await check.validate()
            if passed {
                check.status = .success
            }
        }
    }

    private func updateCompletionStatus() {
        isComplete = checks.allSatisfy { $0.status == .success }

        // Auto-advance focus to next non-success check (only when not running the main loop)
        // The validation loop handles focus changes during initial validation
        if !isRunningValidationLoop {
            if let nextIndex = checks.firstIndex(where: { $0.status != .success }) {
                if nextIndex != focusedIndex {
                    focusedIndex = nextIndex
                }
            }
        }
    }
}
