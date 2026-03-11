// AirlockNavigator.swift
// AirlockCore
//
// State management for onboarding flows.

import SwiftUI
import Combine

/// Manages navigation state for an onboarding flow.
///
/// The navigator tracks the current step, handles navigation between steps,
/// and manages the continue button state. It's automatically injected into
/// the environment for all step content views.
///
/// Example:
/// ```swift
/// @StateObject private var navigator = AirlockNavigator(steps: mySteps)
///
/// AirlockFlowView(navigator: navigator)
///     .onComplete { navigator.complete() }
/// ```
@MainActor
public final class AirlockNavigator: ObservableObject {
    // MARK: - Published Properties

    /// The steps in the onboarding flow.
    @Published public private(set) var steps: [AnyAirlockStep]

    /// The index of the currently displayed step.
    @Published public private(set) var currentIndex: Int = 0

    /// Whether the continue button is enabled for the current step.
    @Published public private(set) var canContinue: Bool = false

    /// Status of each step (pending, current, completed).
    @Published public private(set) var stepStatuses: [String: AirlockStepStatus] = [:]

    /// Whether the onboarding flow is complete.
    @Published public private(set) var isComplete: Bool = false

    /// Whether the onboarding is currently active.
    @Published public var isActive: Bool = true

    /// Whether a validation is currently running.
    @Published public private(set) var isValidating: Bool = false

    // MARK: - Configuration

    /// The app name to display in the UI.
    public let appName: String

    /// The app icon name (from asset catalog).
    public let appIconName: String?

    /// Callback when the flow is completed.
    public var onComplete: (() -> Void)?

    // MARK: - Computed Properties

    /// The current step.
    public var currentStep: AnyAirlockStep? {
        guard currentIndex >= 0, currentIndex < steps.count else { return nil }
        return steps[currentIndex]
    }

    /// Whether the user can go back from the current step.
    public var canGoBack: Bool {
        guard currentIndex > 0 else { return false }
        return currentStep?.allowsGoingBack ?? true
    }

    /// Whether this is the last step.
    public var isLastStep: Bool {
        currentIndex == steps.count - 1
    }

    /// Progress through the flow (0.0 to 1.0).
    public var progress: Double {
        guard steps.count > 1 else { return 1.0 }
        return Double(currentIndex) / Double(steps.count - 1)
    }

    // MARK: - Initialization

    /// Creates a navigator with the given steps.
    /// - Parameters:
    ///   - appName: The name of the app
    ///   - appIconName: Optional asset catalog image name for the app icon
    ///   - steps: The steps in the onboarding flow
    public init(
        appName: String,
        appIconName: String? = nil,
        steps: [AnyAirlockStep]
    ) {
        self.appName = appName
        self.appIconName = appIconName
        self.steps = steps

        // Initialize statuses
        for (index, step) in steps.enumerated() {
            stepStatuses[step.id] = index == 0 ? .current : .pending
        }
    }

    /// Creates a navigator using the step builder.
    /// - Parameters:
    ///   - appName: The name of the app
    ///   - appIconName: Optional asset catalog image name for the app icon
    ///   - steps: Step builder closure
    public convenience init(
        appName: String,
        appIconName: String? = nil,
        @AirlockStepBuilder steps: () -> [AnyAirlockStep]
    ) {
        self.init(appName: appName, appIconName: appIconName, steps: steps())
    }

    // MARK: - Navigation

    /// Enables or disables the continue button.
    ///
    /// Called by step content views when their requirements are met.
    public func setContinueEnabled(_ enabled: Bool) {
        canContinue = enabled
    }

    /// Advances to the next step.
    ///
    /// If validation is configured for the current step, it will run first.
    /// The continue button is disabled until the next step enables it.
    public func goToNext() {
        guard !isValidating else { return }

        Task {
            // Run validation if present
            if let step = currentStep, step.hasValidation {
                isValidating = true
                let passed = await step.validate()
                isValidating = false

                guard passed else { return }
            }

            // Mark current step as completed
            if let step = currentStep {
                stepStatuses[step.id] = .completed
            }

            // Check if we're at the end
            if isLastStep {
                complete()
                return
            }

            // Move to next step
            let nextIndex = currentIndex + 1
            if nextIndex < steps.count {
                // Reset continue state for new step
                canContinue = false

                // Update statuses
                currentIndex = nextIndex
                if let step = currentStep {
                    stepStatuses[step.id] = .current
                }
            }
        }
    }

    /// Goes back to the previous step.
    public func goToPrevious() {
        guard canGoBack else { return }

        // Update statuses
        if let step = currentStep {
            stepStatuses[step.id] = .pending
        }

        currentIndex -= 1

        if let step = currentStep {
            stepStatuses[step.id] = .current
        }

        // Re-enable continue for completed steps
        canContinue = true
    }

    /// Jumps to a specific step by index.
    ///
    /// Only allows jumping to completed steps (going back).
    public func goTo(index: Int) {
        guard index >= 0, index < steps.count else { return }
        guard index <= currentIndex else { return } // Can only go back

        // Update statuses for skipped steps
        for i in (index + 1)...currentIndex {
            stepStatuses[steps[i].id] = .pending
        }

        currentIndex = index

        if let step = currentStep {
            stepStatuses[step.id] = .current
        }

        canContinue = true
    }

    /// Marks the flow as complete.
    public func complete() {
        // Mark final step as completed
        if let step = currentStep {
            stepStatuses[step.id] = .completed
        }

        isComplete = true
        isActive = false
        onComplete?()
    }

    /// Resets the navigator to the first step.
    public func reset() {
        currentIndex = 0
        canContinue = false
        isComplete = false
        isActive = true

        // Reset all statuses
        for (index, step) in steps.enumerated() {
            stepStatuses[step.id] = index == 0 ? .current : .pending
        }
    }

    // MARK: - Step Status

    /// Returns the status of a step by its ID.
    public func status(for stepId: String) -> AirlockStepStatus {
        stepStatuses[stepId] ?? .pending
    }

    /// Returns the status of a step by its index.
    public func status(at index: Int) -> AirlockStepStatus {
        guard index >= 0, index < steps.count else { return .pending }
        return stepStatuses[steps[index].id] ?? .pending
    }
}

// MARK: - FlightCheck Adapter

/// Extension to create a navigator from FlightCheck-based checks.
public extension AirlockNavigator {
    /// Creates a navigator from FlightCheck instances.
    ///
    /// This adapter allows using the existing FlightCheck-based checks
    /// with the new declarative navigation system.
    convenience init(
        appName: String,
        appIconName: String? = nil,
        checks: [AnyFlightCheck]
    ) {
        let steps = checks.map { check in
            AnyAirlockStep(FlightCheckStepAdapter(check: check))
        }
        self.init(appName: appName, appIconName: appIconName, steps: steps)
    }
}

/// Internal adapter that wraps a FlightCheck as an AirlockStep.
private struct FlightCheckStepAdapter: View {
    let check: AnyFlightCheck

    var body: some View {
        check.detailView
    }
}

private extension AnyAirlockStep {
    init(_ adapter: FlightCheckStepAdapter) {
        self.init(
            id: adapter.check.id.uuidString,
            title: adapter.check.title,
            icon: adapter.check.icon,
            subtitle: adapter.check.description,
            allowsGoingBack: true,
            content: AnyView(adapter),
            validation: {
                await adapter.check.validate()
            }
        )
    }
}
