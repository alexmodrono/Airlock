// AirlockEnvironment.swift
// AirlockCore
//
// Environment keys for step-to-navigator communication.

import SwiftUI

// MARK: - Environment Keys

/// Environment key for the navigator object.
private struct AirlockNavigatorKey: EnvironmentKey {
    static let defaultValue: AirlockNavigator? = nil
}

/// Environment key for the current step status.
public enum AirlockStepStatus: Equatable {
    case pending
    case current
    case completed
}

private struct AirlockStepStatusKey: EnvironmentKey {
    static let defaultValue: AirlockStepStatus = .pending
}

/// Environment key for whether the continue button is enabled.
private struct AirlockCanContinueKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

/// Environment key for the step index.
private struct AirlockStepIndexKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

/// Environment key for total step count.
private struct AirlockStepCountKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

/// Environment key for whether this is the last step.
private struct AirlockIsLastStepKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

/// Environment key for whether back navigation is available.
private struct AirlockCanGoBackKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

// MARK: - Environment Values Extension

public extension EnvironmentValues {
    /// The navigator managing the onboarding flow.
    var airlockNavigator: AirlockNavigator? {
        get { self[AirlockNavigatorKey.self] }
        set { self[AirlockNavigatorKey.self] = newValue }
    }

    /// The status of the current step.
    var airlockStepStatus: AirlockStepStatus {
        get { self[AirlockStepStatusKey.self] }
        set { self[AirlockStepStatusKey.self] = newValue }
    }

    /// Whether the continue button should be enabled.
    var airlockCanContinue: Bool {
        get { self[AirlockCanContinueKey.self] }
        set { self[AirlockCanContinueKey.self] = newValue }
    }

    /// The index of the current step (0-based).
    var airlockStepIndex: Int {
        get { self[AirlockStepIndexKey.self] }
        set { self[AirlockStepIndexKey.self] = newValue }
    }

    /// The total number of steps.
    var airlockStepCount: Int {
        get { self[AirlockStepCountKey.self] }
        set { self[AirlockStepCountKey.self] = newValue }
    }

    /// Whether this is the last step in the flow.
    var airlockIsLastStep: Bool {
        get { self[AirlockIsLastStepKey.self] }
        set { self[AirlockIsLastStepKey.self] = newValue }
    }

    /// Whether back navigation is currently available.
    var airlockCanGoBack: Bool {
        get { self[AirlockCanGoBackKey.self] }
        set { self[AirlockCanGoBackKey.self] = newValue }
    }
}

// MARK: - View Modifiers for Step Content

public extension View {
    /// Enables the continue button for this step.
    ///
    /// Call this when your step's requirements are met and the user can proceed.
    ///
    /// Example:
    /// ```swift
    /// MyStepContent()
    ///     .airlockEnableContinue()
    /// ```
    func airlockEnableContinue() -> some View {
        modifier(AirlockEnableContinueModifier(enabled: true))
    }

    /// Controls whether the continue button is enabled.
    ///
    /// Example:
    /// ```swift
    /// MyStepContent()
    ///     .airlockContinueEnabled(isReady)
    /// ```
    func airlockContinueEnabled(_ enabled: Bool) -> some View {
        modifier(AirlockEnableContinueModifier(enabled: enabled))
    }

    /// Enables the continue button after a delay.
    ///
    /// Useful for welcome screens where you want users to see content
    /// before allowing them to proceed.
    ///
    /// Example:
    /// ```swift
    /// WelcomeContent()
    ///     .airlockEnableContinueAfter(seconds: 3)
    /// ```
    func airlockEnableContinueAfter(seconds: Double) -> some View {
        modifier(AirlockDelayedContinueModifier(delay: seconds))
    }

    /// Configures the sidebar button with a custom action for this step.
    ///
    /// While the custom action is set, tapping the sidebar button runs the
    /// action instead of advancing. Call ``AirlockNavigator/resetButton()``
    /// from within the action (after success) to switch the button back
    /// to the default advance behavior.
    ///
    /// Example:
    /// ```swift
    /// MyStepContent()
    ///     .airlockButton(label: "Validate", icon: "magnifyingglass") {
    ///         await validateServer()
    ///     }
    /// ```
    func airlockButton(
        label: String,
        icon: String,
        action: @escaping @MainActor () async -> Void
    ) -> some View {
        modifier(AirlockButtonActionModifier(label: label, icon: icon, action: action))
    }

    /// Sets a custom label and icon on the sidebar button without changing
    /// its behavior (it still advances to the next step when tapped).
    func airlockButtonLabel(_ label: String, icon: String? = nil) -> some View {
        modifier(AirlockButtonLabelModifier(label: label, icon: icon))
    }
}

// MARK: - Continue Modifiers

private struct AirlockEnableContinueModifier: ViewModifier {
    let enabled: Bool
    @Environment(\.airlockNavigator) private var navigator

    func body(content: Content) -> some View {
        content
            .onAppear {
                navigator?.setContinueEnabled(enabled)
            }
            .onChange(of: enabled) { _, newValue in
                navigator?.setContinueEnabled(newValue)
            }
    }
}

private struct AirlockDelayedContinueModifier: ViewModifier {
    let delay: Double
    @Environment(\.airlockNavigator) private var navigator

    func body(content: Content) -> some View {
        content
            .task(id: delay) {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                navigator?.setContinueEnabled(true)
            }
    }
}

// MARK: - Button Modifiers

private struct AirlockButtonActionModifier: ViewModifier {
    let label: String
    let icon: String
    let action: @MainActor () async -> Void
    @Environment(\.airlockNavigator) private var navigator

    func body(content: Content) -> some View {
        content
            .onAppear {
                navigator?.setButtonAction(label: label, icon: icon, action: action)
            }
    }
}

private struct AirlockButtonLabelModifier: ViewModifier {
    let label: String
    let icon: String?
    @Environment(\.airlockNavigator) private var navigator

    func body(content: Content) -> some View {
        content
            .onAppear {
                navigator?.setButtonLabel(label, icon: icon)
            }
    }
}
