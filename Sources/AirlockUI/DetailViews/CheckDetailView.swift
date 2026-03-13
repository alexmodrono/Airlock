// CheckDetailView.swift
// AirlockUI

import SwiftUI
import AirlockCore

/// A reusable detail view template for flight checks.
///
/// Displays an icon, title, description, and optional custom content
/// with a consistent layout and styling.
public struct CheckDetailView<Content: View>: View {
    let icon: String
    let title: String
    let description: String
    let status: CheckStatus
    let content: Content

    @Environment(\.colorScheme) private var colorScheme

    public init(
        icon: String,
        title: String,
        description: String,
        status: CheckStatus,
        @ViewBuilder content: () -> Content = { EmptyView() }
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.status = status
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 20) {
            Spacer()
                .frame(height: 20)

            // Icon with status-based styling
            ZStack {
                Circle()
                    .fill(iconBackgroundColor.opacity(colorScheme == .dark ? 0.2 : 0.12))
                    .frame(width: 100, height: 100)

                Image(systemName: icon)
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(iconColor)
            }

            // Title
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)

            // Description
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)

            // Status message
            StatusMessage(status: status)
                .padding(.top, 4)

            // Custom content with fixed width
            VStack {
                content
            }
            .frame(maxWidth: 420)

            Spacer()
                .frame(minHeight: 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
    }

    private var iconColor: Color {
        switch status {
        case .pending, .checking:
            return .blue
        case .active:
            return .orange
        case .success:
            return .green
        case .failed:
            return .red
        }
    }

    private var iconBackgroundColor: Color {
        iconColor
    }
}

// MARK: - Status Message

struct StatusMessage: View {
    let status: CheckStatus

    var body: some View {
        Group {
            switch status {
            case .pending:
                Label("Waiting...", systemImage: "clock")
                    .foregroundStyle(.secondary)

            case .checking:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking...")
                        .foregroundStyle(.secondary)
                }

            case .active:
                Label("Action Required", systemImage: "exclamationmark.circle")
                    .foregroundStyle(.orange)

            case .success:
                Label("Complete", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)

            case .failed(let error):
                VStack(spacing: 4) {
                    Label("Failed", systemImage: "xmark.circle.fill")
                        .foregroundStyle(.red)
                    if let message = error.errorDescription {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .font(.system(size: 13, weight: .medium))
    }
}

// MARK: - Instruction Step View

/// A numbered instruction step for detail views.
public struct InstructionStep: View {
    let number: Int
    let text: String

    public init(_ number: Int, _ text: String) {
        self.number = number
        self.text = text
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor))

            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
    }
}
