// AirlockStep.swift
// AirlockCore
//
// Generic step definition for declarative onboarding flows.

import SwiftUI

/// A step in an onboarding flow.
///
/// Steps define individual screens in the onboarding sequence. Each step has
/// a title, icon, and content view. Steps can control when the user can proceed
/// by enabling or disabling the continue button.
///
/// Example:
/// ```swift
/// AirlockStep(
///     id: "welcome",
///     title: "Welcome",
///     icon: "hand.wave.fill"
/// ) {
///     WelcomeContentView()
/// }
/// ```
public struct AirlockStep<Content: View>: Identifiable {
    public let id: String
    public let title: String
    public let icon: String
    public let subtitle: String?
    public let content: Content

    /// Whether this step allows going back to the previous step.
    public var allowsGoingBack: Bool = true

    /// Optional validation that must pass before continuing.
    /// If nil, the step doesn't require validation.
    public var validation: (() async -> Bool)?

    /// Creates an onboarding step.
    /// - Parameters:
    ///   - id: Unique identifier for the step
    ///   - title: Title shown in the sidebar
    ///   - icon: SF Symbol name for the sidebar icon
    ///   - subtitle: Optional subtitle shown below the title
    ///   - content: The view builder for the step's content
    public init(
        id: String,
        title: String,
        icon: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.content = content()
    }

    /// Sets whether this step allows going back.
    public func allowsGoingBack(_ allowed: Bool) -> AirlockStep {
        var copy = self
        copy.allowsGoingBack = allowed
        return copy
    }

    /// Adds validation that must pass before continuing.
    public func validation(_ validate: @escaping () async -> Bool) -> AirlockStep {
        var copy = self
        copy.validation = validate
        return copy
    }
}

// MARK: - Type-Erased Step

/// Type-erased wrapper for AirlockStep to allow heterogeneous arrays.
public struct AnyAirlockStep: Identifiable {
    public let id: String
    public let title: String
    public let icon: String
    public let subtitle: String?
    public let allowsGoingBack: Bool
    private let _content: AnyView
    private let _validation: (() async -> Bool)?

    public var content: AnyView { _content }

    /// Whether this step has validation configured.
    public var hasValidation: Bool { _validation != nil }

    public init<Content: View>(_ step: AirlockStep<Content>) {
        self.id = step.id
        self.title = step.title
        self.icon = step.icon
        self.subtitle = step.subtitle
        self.allowsGoingBack = step.allowsGoingBack
        self._content = AnyView(step.content)
        self._validation = step.validation
    }

    /// Internal initializer for creating steps from other sources (e.g., FlightCheck adapter).
    internal init(
        id: String,
        title: String,
        icon: String,
        subtitle: String?,
        allowsGoingBack: Bool,
        content: AnyView,
        validation: (() async -> Bool)?
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.subtitle = subtitle
        self.allowsGoingBack = allowsGoingBack
        self._content = content
        self._validation = validation
    }

    /// Runs validation if present. Returns true if no validation or validation passes.
    public func validate() async -> Bool {
        if let validation = _validation {
            return await validation()
        }
        return true
    }
}

// MARK: - Step Builder

/// Result builder for creating arrays of steps declaratively.
@resultBuilder
public struct AirlockStepBuilder {
    public static func buildBlock(_ components: AnyAirlockStep...) -> [AnyAirlockStep] {
        components
    }

    public static func buildExpression<Content: View>(_ expression: AirlockStep<Content>) -> AnyAirlockStep {
        AnyAirlockStep(expression)
    }

    public static func buildOptional(_ component: [AnyAirlockStep]?) -> [AnyAirlockStep] {
        component ?? []
    }

    public static func buildEither(first component: [AnyAirlockStep]) -> [AnyAirlockStep] {
        component
    }

    public static func buildEither(second component: [AnyAirlockStep]) -> [AnyAirlockStep] {
        component
    }

    public static func buildArray(_ components: [[AnyAirlockStep]]) -> [AnyAirlockStep] {
        components.flatMap { $0 }
    }
}
