// WelcomeCheck.swift
// AirlockChecks
//
// A configurable feature showcase screen that auto-advances to the next check.

import AppKit
import Combine
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
@MainActor
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
    private var autoAdvanceStarted = false
    private(set) var autoAdvanceTask: Task<Void, Never>?

    /// A feature to display in the welcome screen.
    public struct Feature: Identifiable {
        public let id = UUID()
        public let icon: String
        public let title: String
        public let description: String
        public let color: NSColor
        public let preview: String?

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
            color: NSColor = .blue,
            preview: String? = nil
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
        public let color: NSColor

        /// Creates a highlight feature.
        /// - Parameters:
        ///   - icon: SF Symbol name for the feature icon
        ///   - title: Short feature title
        ///   - color: Accent color for the highlight
        public init(icon: String, title: String, color: NSColor) {
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
        let seconds = autoAdvanceAfter.isFinite ? min(max(0, autoAdvanceAfter), 86_400) : 0
        self.autoAdvanceDuration = UInt64(seconds * 1_000_000_000)
    }

    public var detailView: NSViewController {
        NativeCheckViewController(check: self)
    }

    public func performAction() {
        status = .success
    }

    /// Starts the auto-advance countdown if configured. Idempotent.
    ///
    /// Called when the welcome screen appears so the countdown is tied to the
    /// view lifecycle rather than to a blocking `validate()` call.
    @MainActor
    public func beginAutoAdvanceIfNeeded() {
        guard autoAdvanceDuration > 0, !autoAdvanceStarted else { return }
        autoAdvanceStarted = true

        let duration = autoAdvanceDuration
        autoAdvanceTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: duration) } catch { return }
            guard let self, !Task.isCancelled else { return }
            if self.status != .success { self.status = .success }
            self.autoAdvanceTask = nil
        }
    }

    /// Stops the countdown while this screen is hidden. A later visit starts it again.
    public func cancel() {
        autoAdvanceTask?.cancel()
        autoAdvanceTask = nil
        if status != .success { autoAdvanceStarted = false }
    }

    deinit { autoAdvanceTask?.cancel() }

    @MainActor
    public func validate() async -> Bool {
        // Pure predicate: the welcome screen passes once it has been marked
        // complete, either by the auto-advance countdown or the Continue button.
        status == .success
    }

    // Internal accessors for the detail view
    var welcomeAppName: String { appName }
    var welcomeSubtitle: String { subtitle }
    var welcomeFeatures: [Feature] { features }
    var welcomeHighlightFeatures: [HighlightFeature] { highlightFeatures }
    var hasAutoAdvance: Bool { autoAdvanceDuration > 0 }
}
