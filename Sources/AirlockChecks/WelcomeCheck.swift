// WelcomeCheck.swift
// AirlockChecks
//
// A configurable feature showcase screen that auto-advances to the next check.

import SwiftUI
import AirlockCore
import AirlockUI

/// A flight check that displays a feature showcase welcome screen.
///
/// This check displays your app's key features and automatically advances
/// to the next check after a configurable duration. It's typically used as
/// the first step in an onboarding flow to introduce users to your app
/// before they complete the required setup steps.
///
/// The welcome screen includes:
/// - An animated feature highlight carousel at the top
/// - A customizable title and subtitle
/// - Feature cards showing key capabilities
///
/// Example:
/// ```swift
/// WelcomeCheck(
///     appName: "MyApp",
///     subtitle: "Let's get you set up",
///     features: [
///         .init(icon: "star.fill", title: "Feature 1", description: "Description", color: .blue),
///         .init(icon: "heart.fill", title: "Feature 2", description: "Description", color: .pink)
///     ],
///     autoAdvanceAfter: 3.0  // Advances to next check after 3 seconds
/// )
/// ```
public final class WelcomeCheck: FlightCheck, ObservableObject {
    public let id = UUID()
    public let title: String
    public let description: String
    public let icon: String
    public let actionLabel: String

    @Published public var status: CheckStatus = .pending

    private let appName: String
    private let subtitle: String
    private let features: [Feature]
    private let highlightFeatures: [HighlightFeature]
    private let autoAdvanceDuration: UInt64

    /// A feature to display in the welcome screen.
    public struct Feature: Identifiable {
        public let id = UUID()
        public let icon: String
        public let title: String
        public let description: String
        public let color: Color
        public let preview: FeaturePreview?

        /// Creates a feature.
        /// - Parameters:
        ///   - icon: SF Symbol name for the feature icon
        ///   - title: Feature title
        ///   - description: Feature description
        ///   - color: Accent color for the feature card (default: blue)
        ///   - preview: Optional preview content (text, video, or GIF) shown on hover
        public init(
            icon: String,
            title: String,
            description: String,
            color: Color = .blue,
            preview: FeaturePreview? = nil
        ) {
            self.icon = icon
            self.title = title
            self.description = description
            self.color = color
            self.preview = preview
        }
    }

    /// A feature to highlight in the animated carousel.
    public struct HighlightFeature: Identifiable {
        public let id = UUID()
        public let icon: String
        public let title: String
        public let color: Color

        /// Creates a highlight feature.
        /// - Parameters:
        ///   - icon: SF Symbol name for the feature icon
        ///   - title: Short feature title
        ///   - color: Accent color for the highlight
        public init(icon: String, title: String, color: Color) {
            self.icon = icon
            self.title = title
            self.color = color
        }
    }

    /// Creates a welcome check (feature showcase screen).
    ///
    /// The welcome screen automatically advances to the next check after
    /// the specified duration, allowing users to view your app's features
    /// before proceeding with the setup process.
    ///
    /// - Parameters:
    ///   - appName: The name of the app to display in the welcome message
    ///   - subtitle: Subtitle text below the welcome message (default: "Let's get you set up")
    ///   - features: Array of features to display as cards in the detail view
    ///   - highlightFeatures: Features to cycle through in the animated highlight carousel.
    ///                        If nil, uses the features array.
    ///   - autoAdvanceAfter: Duration in seconds before automatically advancing to the next check.
    ///                       Set to 0 to require user action. (default: 3.0)
    ///   - title: Check title shown in the sidebar (default: "Welcome")
    ///   - description: Check description (default: "Get started with [appName]")
    ///   - icon: SF Symbol name for the sidebar icon (default: "hand.wave.fill")
    ///   - actionLabel: Label for the action button if auto-advance is disabled (default: "Continue")
    public init(
        appName: String,
        subtitle: String = "Let's get you set up",
        features: [Feature] = [],
        highlightFeatures: [HighlightFeature]? = nil,
        autoAdvanceAfter: Double = 3.0,
        title: String = "Welcome",
        description: String? = nil,
        icon: String = "hand.wave.fill",
        actionLabel: String = "Continue"
    ) {
        self.appName = appName
        self.subtitle = subtitle
        self.features = features
        self.highlightFeatures = highlightFeatures ?? features.map {
            HighlightFeature(icon: $0.icon, title: $0.title, color: $0.color)
        }
        self.title = title
        self.description = description ?? "Get started with \(appName)"
        self.icon = icon
        self.actionLabel = actionLabel
        self.autoAdvanceDuration = UInt64(max(0, autoAdvanceAfter) * 1_000_000_000)
    }

    public var detailView: AnyView {
        AnyView(WelcomeCheckDetailView(check: self))
    }

    public func performAction() {
        Task { @MainActor in
            status = .success
        }
    }

    @MainActor
    public func validate() async -> Bool {
        // If auto-advance is enabled, wait but allow early exit via Continue button
        if autoAdvanceDuration > 0 {
            let checkInterval: UInt64 = 100_000_000 // Check every 100ms
            var elapsed: UInt64 = 0

            while elapsed < autoAdvanceDuration {
                // Check if user clicked Continue (which sets status to .success)
                if status == .success {
                    return true
                }
                try? await Task.sleep(nanoseconds: checkInterval)
                elapsed += checkInterval
            }
            status = .success
            return true
        }
        // If auto-advance is disabled (0), require user action
        status = .active
        return false
    }

    // Internal accessors for the detail view
    var welcomeAppName: String { appName }
    var welcomeSubtitle: String { subtitle }
    var welcomeFeatures: [Feature] { features }
    var welcomeHighlightFeatures: [HighlightFeature] { highlightFeatures }
    var hasAutoAdvance: Bool { autoAdvanceDuration > 0 }
}

// MARK: - Detail View

struct WelcomeCheckDetailView: View {
    @ObservedObject var check: WelcomeCheck

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
                .frame(height: 24)

            // Animated feature highlight at top
            if !check.welcomeHighlightFeatures.isEmpty {
                AnimatedFeatureHighlight(
                    features: check.welcomeHighlightFeatures.map {
                        AnimatedFeatureHighlight.Feature(icon: $0.icon, title: $0.title, color: $0.color)
                    }
                )
            }

            // Title
            VStack(spacing: 8) {
                Text("Welcome to \(check.welcomeAppName)")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(check.welcomeSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            // Feature cards
            if !check.welcomeFeatures.isEmpty {
                VStack(spacing: 10) {
                    ForEach(check.welcomeFeatures) { feature in
                        FeatureCard(
                            icon: feature.icon,
                            title: feature.title,
                            description: feature.description,
                            accentColor: feature.color,
                            preview: feature.preview
                        )
                    }
                }
                .padding(.horizontal, 24)
            }

            // Continue button
            if check.status != .success {
                Button {
                    check.performAction()
                } label: {
                    HStack(spacing: 8) {
                        Text(check.actionLabel)
                        Image(systemName: "arrow.right")
                    }
                    .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 8)
            }

            Spacer()
                .frame(height: 24)
        }
    }
}
