// CheckRowView.swift
// AirlockUI

import SwiftUI
import AirlockCore

/// A single row in the flight check sidebar.
///
/// Displays the check's icon, title, and status indicator with
/// appropriate styling based on the check's current state.
struct CheckRowView: View {
    @ObservedObject var check: AnyFlightCheck
    let isFocused: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            StatusIndicator(status: check.status)

            // Icon
            Image(systemName: check.icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            // Title
            Text(check.title)
                .font(.system(size: 13, weight: isFocused ? .semibold : .regular))
                .foregroundStyle(textColor)

            Spacer()

            // Action button (only for active checks)
            if check.status == .active && !check.actionLabel.isEmpty {
                ActionChip(
                    label: check.actionLabel,
                    action: check.performAction
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(borderColor, lineWidth: isFocused ? 1 : 0)
        )
        .contentShape(Rectangle())
    }

    // MARK: - Computed Properties

    private var iconColor: Color {
        switch check.status {
        case .pending:
            return .secondary.opacity(0.5)
        case .checking:
            return .blue
        case .active:
            return .orange
        case .success:
            return .green
        case .failed:
            return .red
        }
    }

    private var textColor: Color {
        switch check.status {
        case .pending:
            return .secondary
        case .success:
            return .primary.opacity(0.7)
        default:
            return .primary
        }
    }

    private var backgroundColor: Color {
        if isFocused {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.15 : 0.08)
        }
        return Color.clear
    }

    private var borderColor: Color {
        if isFocused {
            return Color.accentColor.opacity(colorScheme == .dark ? 0.4 : 0.25)
        }
        return Color.clear
    }
}

// MARK: - Status Indicator

struct StatusIndicator: View {
    let status: CheckStatus

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            switch status {
            case .pending:
                Circle()
                    .fill(Color.secondary.opacity(colorScheme == .dark ? 0.4 : 0.25))
                    .frame(width: 10, height: 10)

            case .checking:
                Circle()
                    .fill(Color.blue.opacity(0.3))
                    .frame(width: 14, height: 14)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .opacity(isPulsing ? 0.3 : 0.8)

                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)

            case .active:
                Circle()
                    .fill(Color.orange.opacity(0.3))
                    .frame(width: 12, height: 12)

                Circle()
                    .fill(Color.orange)
                    .frame(width: 6, height: 6)

            case .success:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.green)

            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
        .frame(width: 18, height: 18)
        .onAppear {
            updatePulseAnimation(for: status)
        }
        .onChange(of: status) { _, newStatus in
            updatePulseAnimation(for: newStatus)
        }
        .onChange(of: reduceMotion) { _, _ in
            updatePulseAnimation(for: status)
        }
    }

    private func updatePulseAnimation(for status: CheckStatus) {
        guard !reduceMotion else {
            isPulsing = false
            return
        }

        if case .checking = status {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        } else {
            isPulsing = false
        }
    }
}

// MARK: - Action Chip

struct ActionChip: View {
    let label: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color.accentColor.opacity(isHovering ? 1.0 : 0.85))
                )
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
