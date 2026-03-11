// AirlockContentComponents.swift
// AirlockUI
//
// Reusable components for building step content views.

import SwiftUI
import AirlockCore

// MARK: - Step Content Container

/// A standardized container for step content.
///
/// Provides consistent padding, spacing, and optional continue button.
///
/// Example:
/// ```swift
/// AirlockStepContent {
///     Text("Welcome!")
///     FeatureGrid(features: myFeatures)
/// } continueButton: {
///     AirlockInlineContinueButton()
/// }
/// ```
public struct AirlockStepContent<Content: View, ContinueButton: View>: View {
    private let content: Content
    private let continueButton: ContinueButton?

    public init(
        @ViewBuilder content: () -> Content,
        @ViewBuilder continueButton: () -> ContinueButton
    ) {
        self.content = content()
        self.continueButton = continueButton()
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 24)

            content

            if let button = continueButton {
                button
                    .padding(.top, 8)
            }

            Spacer()
                .frame(height: 24)
        }
        .padding(.horizontal, 24)
    }
}

public extension AirlockStepContent where ContinueButton == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
        self.continueButton = nil
    }
}

// MARK: - Inline Continue Button

/// A continue button that can be placed inline within step content.
///
/// This button uses the navigator from the environment to enable
/// the global continue button.
public struct AirlockInlineContinueButton: View {
    @Environment(\.airlockNavigator) private var navigator
    @Environment(\.airlockCanContinue) private var canContinue

    private let label: String
    private let icon: String

    public init(label: String = "Continue", icon: String = "arrow.right") {
        self.label = label
        self.icon = icon
    }

    public var body: some View {
        Button {
            navigator?.goToNext()
        } label: {
            HStack(spacing: 8) {
                Text(label)
                Image(systemName: icon)
            }
            .frame(minWidth: 140)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!canContinue)
    }
}

// MARK: - Step Header

/// A header view for step content.
///
/// Displays an icon, title, and optional subtitle.
public struct AirlockStepHeader: View {
    let icon: String
    let title: String
    let subtitle: String?
    let iconColor: Color

    @Environment(\.colorScheme) private var colorScheme

    public init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        iconColor: Color = .accentColor
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.iconColor = iconColor
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Icon with glow effect
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [iconColor.opacity(0.3), Color.clear],
                            center: .center,
                            startRadius: 20,
                            endRadius: 60
                        )
                    )
                    .frame(width: 100, height: 100)
                    .blur(radius: 10)

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [iconColor.opacity(0.25), iconColor.opacity(0.15)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)

                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [iconColor.opacity(0.5), iconColor.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 72, height: 72)

                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [iconColor, iconColor.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Title and subtitle
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 24, weight: .bold, design: .rounded))

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }
}

// MARK: - Step Status Badge

/// A badge showing the current step status.
public struct AirlockStatusBadge: View {
    @Environment(\.airlockStepStatus) private var status

    let pendingText: String
    let currentText: String
    let completedText: String

    public init(
        pendingText: String = "Pending",
        currentText: String = "In Progress",
        completedText: String = "Completed"
    ) {
        self.pendingText = pendingText
        self.currentText = currentText
        self.completedText = completedText
    }

    private var text: String {
        switch status {
        case .pending: return pendingText
        case .current: return currentText
        case .completed: return completedText
        }
    }

    private var color: Color {
        switch status {
        case .pending: return .gray
        case .current: return .blue
        case .completed: return .green
        }
    }

    private var icon: String {
        switch status {
        case .pending: return "circle"
        case .current: return "circle.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)

            Text(text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(status == .completed ? .primary : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}

// MARK: - Info Card

/// A card for displaying information with an icon.
/// Supports markdown in the description (e.g., **bold**, *italic*).
public struct AirlockInfoCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    public init(
        icon: String,
        title: String,
        description: String,
        color: Color = .blue
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.color = color
    }

    /// Parses markdown string into AttributedString, falling back to plain text on failure
    private var attributedDescription: AttributedString {
        (try? AttributedString(markdown: description)) ?? AttributedString(description)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(color)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
            }

            Text(attributedDescription)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(colorScheme == .dark ? 0.08 : 0.05))
        )
    }
}

// MARK: - Capability Chips

/// A horizontal row of capability/feature chips.
public struct AirlockCapabilityChips: View {
    let capabilities: [(icon: String, label: String, color: Color)]

    public init(_ capabilities: [(icon: String, label: String, color: Color)]) {
        self.capabilities = capabilities
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(capabilities.chunked(into: 2).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 12) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cap in
                        AirlockCapabilityChip(icon: cap.icon, label: cap.label, color: cap.color)
                    }
                }
            }
        }
    }
}

/// A single capability chip.
public struct AirlockCapabilityChip: View {
    let icon: String
    let label: String
    let color: Color

    @Environment(\.colorScheme) private var colorScheme

    public init(icon: String, label: String, color: Color) {
        self.icon = icon
        self.label = label
        self.color = color
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)

            Text(label)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(color.opacity(colorScheme == .dark ? 0.15 : 0.08))
        )
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Progress Steps

/// A list of progress steps with completion indicators.
public struct AirlockProgressSteps: View {
    let steps: [(text: String, isDone: Bool)]

    public init(_ steps: [(text: String, isDone: Bool)]) {
        self.steps = steps
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(step.isDone ? Color.green : Color.primary.opacity(0.1))
                            .frame(width: 20, height: 20)

                        if step.isDone {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        } else {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(step.text)
                        .font(.system(size: 12))
                        .foregroundStyle(step.isDone ? Color.secondary : Color.primary.opacity(0.7))
                }
            }
        }
    }
}

// MARK: - Array Extension

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
