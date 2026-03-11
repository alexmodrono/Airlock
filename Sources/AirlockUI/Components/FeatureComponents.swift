// FeatureComponents.swift
// AirlockUI
//
// Reusable components for showcasing features in onboarding flows.

import SwiftUI
import AVKit
import UniformTypeIdentifiers

// MARK: - Feature Preview Content

/// Content to display in a feature preview popover.
public struct FeaturePreview {
    /// The preview text to display
    public let text: String?

    /// URL to a video or GIF to display
    public let mediaURL: URL?

    /// Whether the media is a GIF (affects playback behavior)
    public let isGIF: Bool

    /// Size of the preview popover
    public let size: CGSize

    /// Creates a text-only preview.
    /// - Parameter text: The preview text
    public static func text(_ text: String) -> FeaturePreview {
        FeaturePreview(text: text, mediaURL: nil, isGIF: false, size: CGSize(width: 280, height: 0))
    }

    /// Creates a video preview.
    /// - Parameters:
    ///   - url: URL to the video file
    ///   - text: Optional caption text
    ///   - size: Size of the video preview (default: 320x180)
    public static func video(_ url: URL, text: String? = nil, size: CGSize = CGSize(width: 320, height: 180)) -> FeaturePreview {
        FeaturePreview(text: text, mediaURL: url, isGIF: false, size: size)
    }

    /// Creates a GIF preview.
    /// - Parameters:
    ///   - url: URL to the GIF file
    ///   - text: Optional caption text
    ///   - size: Size of the GIF preview (default: 320x180)
    public static func gif(_ url: URL, text: String? = nil, size: CGSize = CGSize(width: 320, height: 180)) -> FeaturePreview {
        FeaturePreview(text: text, mediaURL: url, isGIF: true, size: size)
    }

    /// Creates a preview with both media and text.
    /// - Parameters:
    ///   - text: The preview text
    ///   - mediaURL: URL to video or GIF
    ///   - isGIF: Whether the media is a GIF
    ///   - size: Size of the media preview
    public init(text: String?, mediaURL: URL?, isGIF: Bool, size: CGSize) {
        self.text = text
        self.mediaURL = mediaURL
        self.isGIF = isGIF
        self.size = size
    }
}

// MARK: - Feature Card

/// A card displaying a feature with icon, title, and description.
/// Use this to highlight key features or capabilities during onboarding.
/// Optionally shows a preview popover on hover with text, video, or GIF content.
public struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color
    let showChevron: Bool
    let preview: FeaturePreview?

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false
    @State private var showPreview = false
    @State private var hoverTask: Task<Void, Never>?

    /// Creates a feature card.
    /// - Parameters:
    ///   - icon: SF Symbol name for the icon
    ///   - title: Feature title
    ///   - description: Feature description
    ///   - accentColor: Color theme for the card (default: blue)
    ///   - showChevron: Whether to show a chevron indicator (default: true)
    ///   - preview: Optional preview content to show on hover
    public init(
        icon: String,
        title: String,
        description: String,
        accentColor: Color = .blue,
        showChevron: Bool = true,
        preview: FeaturePreview? = nil
    ) {
        self.icon = icon
        self.title = title
        self.description = description
        self.accentColor = accentColor
        self.showChevron = showChevron
        self.preview = preview
    }

    public var body: some View {
        HStack(spacing: 14) {
            // Icon with gradient background
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(
                        LinearGradient(
                            colors: [
                                accentColor.opacity(colorScheme == .dark ? 0.3 : 0.15),
                                accentColor.opacity(colorScheme == .dark ? 0.15 : 0.08)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(accentColor)
            }

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            // Chevron indicator (or preview indicator if preview exists)
            if showChevron || preview != nil {
                Image(systemName: preview != nil ? "eye.fill" : "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(preview != nil ? accentColor : Color.secondary)
                    .opacity(isHovering ? 1 : 0.5)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.05 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            accentColor.opacity(isHovering ? 0.3 : 0),
                            lineWidth: 1
                        )
                )
        )
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
            handleHover(hovering)
        }
        .popover(isPresented: $showPreview, arrowEdge: .trailing) {
            if let preview = preview {
                FeaturePreviewPopover(preview: preview, accentColor: accentColor)
            }
        }
    }

    private func handleHover(_ hovering: Bool) {
        hoverTask?.cancel()

        if hovering && preview != nil {
            // Delay before showing preview
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: 400_000_000) // 400ms delay
                if !Task.isCancelled {
                    await MainActor.run {
                        showPreview = true
                    }
                }
            }
        } else {
            showPreview = false
        }
    }
}

// MARK: - Feature Preview Popover

struct FeaturePreviewPopover: View {
    let preview: FeaturePreview
    let accentColor: Color

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Media content
            if let mediaURL = preview.mediaURL {
                if preview.isGIF {
                    GIFView(url: mediaURL)
                        .frame(width: preview.size.width, height: preview.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VideoPreviewView(url: mediaURL)
                        .frame(width: preview.size.width, height: preview.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }

            // Text content
            if let text = preview.text {
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: preview.mediaURL != nil ? preview.size.width : 280)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(white: 0.15) : Color.white)
                .shadow(color: .black.opacity(0.15), radius: 12, x: 0, y: 4)
        )
    }
}

// MARK: - Video Preview View

struct VideoPreviewView: View {
    let url: URL

    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player = player {
                VideoPlayer(player: player)
                    .disabled(true) // Prevent interaction, just preview
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .overlay(
                        ProgressView()
                            .scaleEffect(0.8)
                    )
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    private func setupPlayer() {
        let avPlayer = AVPlayer(url: url)
        avPlayer.isMuted = true
        avPlayer.play()

        // Loop the video
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: avPlayer.currentItem,
            queue: .main
        ) { _ in
            avPlayer.seek(to: .zero)
            avPlayer.play()
        }

        player = avPlayer
    }
}

// MARK: - GIF View

struct GIFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> NSImageView {
        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.animates = true
        imageView.canDrawSubviewsIntoLayer = true
        return imageView
    }

    func updateNSView(_ nsView: NSImageView, context: Context) {
        loadGIF(into: nsView)
    }

    private func loadGIF(into imageView: NSImageView) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let image = NSImage(contentsOf: url) {
                DispatchQueue.main.async {
                    imageView.image = image
                }
            }
        }
    }
}

// MARK: - Feature Row

/// A simple row for displaying a feature with an icon and text.
public struct FeatureRow: View {
    let icon: String
    let text: String
    let iconColor: Color

    /// Creates a feature row.
    /// - Parameters:
    ///   - icon: SF Symbol name for the icon
    ///   - text: Description text
    ///   - iconColor: Color for the icon (default: blue)
    public init(icon: String, text: String, iconColor: Color = .blue) {
        self.icon = icon
        self.text = text
        self.iconColor = iconColor
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 24)

            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

// MARK: - Feature Grid

/// A grid layout for displaying multiple feature cards.
public struct FeatureGrid: View {
    let features: [Feature]
    let columns: Int

    /// A feature to display in the grid.
    public struct Feature: Identifiable {
        public let id = UUID()
        public let icon: String
        public let title: String
        public let description: String
        public let color: Color
        public let preview: FeaturePreview?

        /// Creates a feature.
        /// - Parameters:
        ///   - icon: SF Symbol name
        ///   - title: Feature title
        ///   - description: Feature description
        ///   - color: Accent color (default: blue)
        ///   - preview: Optional preview content for hover popover
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

    /// Creates a feature grid.
    /// - Parameters:
    ///   - features: Array of features to display
    ///   - columns: Number of columns (default: 2)
    public init(features: [Feature], columns: Int = 2) {
        self.features = features
        self.columns = columns
    }

    public var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible()), count: columns),
            spacing: 12
        ) {
            ForEach(features) { feature in
                FeatureCard(
                    icon: feature.icon,
                    title: feature.title,
                    description: feature.description,
                    accentColor: feature.color,
                    showChevron: false,
                    preview: feature.preview
                )
            }
        }
    }
}

// MARK: - Animated Feature Highlight

/// An animated view that cycles through features with icons and titles.
/// Great for drawing attention to key features at the top of a welcome screen.
public struct AnimatedFeatureHighlight: View {
    let features: [Feature]
    let cycleInterval: TimeInterval

    @State private var currentIndex = 0
    @State private var timer: Timer?

    /// A feature to highlight.
    public struct Feature: Identifiable {
        public let id = UUID()
        public let icon: String
        public let title: String
        public let color: Color

        public init(icon: String, title: String, color: Color) {
            self.icon = icon
            self.title = title
            self.color = color
        }
    }

    /// Creates an animated feature highlight.
    /// - Parameters:
    ///   - features: Array of features to cycle through
    ///   - cycleInterval: Time between transitions in seconds (default: 2.5)
    public init(features: [Feature], cycleInterval: TimeInterval = 2.5) {
        self.features = features
        self.cycleInterval = cycleInterval
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Animated icon
            ZStack {
                // Outer glow
                Circle()
                    .fill(currentFeature.color.opacity(0.08))
                    .frame(width: 100, height: 100)

                // Inner circle
                Circle()
                    .fill(currentFeature.color.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: currentFeature.icon)
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(currentFeature.color)
            }
            .animation(.easeInOut(duration: 0.5), value: currentIndex)

            // Title
            Text(currentFeature.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)
                .animation(.easeInOut(duration: 0.3), value: currentIndex)

            // Progress dots
            HStack(spacing: 6) {
                ForEach(0..<features.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentIndex ? currentFeature.color : Color.primary.opacity(0.2))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.3), value: currentIndex)
                }
            }
        }
        .onAppear {
            startCycling()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private var currentFeature: Feature {
        features.isEmpty ? Feature(icon: "star", title: "", color: .blue) : features[currentIndex]
    }

    private func startCycling() {
        guard features.count > 1 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: cycleInterval, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.5)) {
                currentIndex = (currentIndex + 1) % features.count
            }
        }
    }
}

// MARK: - Setup Stage

/// A row indicating a setup stage with completion status.
public struct SetupStage: View {
    let name: String
    let isComplete: Bool

    /// Creates a setup stage row.
    /// - Parameters:
    ///   - name: Name of the stage
    ///   - isComplete: Whether the stage is complete
    public init(name: String, isComplete: Bool) {
        self.name = name
        self.isComplete = isComplete
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(isComplete ? .green : .secondary.opacity(0.5))

            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(isComplete ? .primary : .secondary)

            Spacer()
        }
    }
}

// MARK: - Progress Bar

/// A customizable progress bar with gradient fill.
public struct ProgressBarView: View {
    let progress: Double
    let label: String?
    let showPercentage: Bool
    let gradientColors: [Color]

    @Environment(\.colorScheme) private var colorScheme

    /// Creates a progress bar.
    /// - Parameters:
    ///   - progress: Progress value from 0.0 to 1.0
    ///   - label: Optional label text (default: nil)
    ///   - showPercentage: Whether to show percentage (default: true)
    ///   - gradientColors: Colors for the gradient fill (default: blue to cyan)
    public init(
        progress: Double,
        label: String? = nil,
        showPercentage: Bool = true,
        gradientColors: [Color] = [.blue, .cyan]
    ) {
        self.progress = min(max(progress, 0), 1)
        self.label = label
        self.showPercentage = showPercentage
        self.gradientColors = gradientColors
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if label != nil || showPercentage {
                HStack {
                    if let label = label {
                        Text(label)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if showPercentage {
                        Text("\(Int(progress * 100))%")
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.1))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.3), value: progress)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Info Banner

/// An informational banner with an icon and message.
public struct InfoBanner: View {
    let message: String
    let icon: String
    let style: Style

    @Environment(\.colorScheme) private var colorScheme

    /// Banner style options.
    public enum Style {
        case info
        case success
        case warning
        case error

        var color: Color {
            switch self {
            case .info: return .blue
            case .success: return .green
            case .warning: return .orange
            case .error: return .red
            }
        }

        var defaultIcon: String {
            switch self {
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "xmark.circle.fill"
            }
        }
    }

    /// Creates an info banner.
    /// - Parameters:
    ///   - message: The message to display
    ///   - icon: SF Symbol name (default: based on style)
    ///   - style: Banner style (default: info)
    public init(message: String, icon: String? = nil, style: Style = .info) {
        self.message = message
        self.icon = icon ?? style.defaultIcon
        self.style = style
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(style.color)

            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(style.color.opacity(colorScheme == .dark ? 0.15 : 0.08))
        )
    }
}

// MARK: - Preview

#if DEBUG
struct FeatureComponents_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            FeatureCard(
                icon: "checkmark.shield.fill",
                title: "Secure",
                description: "Your data is protected",
                accentColor: .green,
                preview: .text("All your data is encrypted end-to-end and never leaves your device.")
            )

            FeatureCard(
                icon: "sparkles",
                title: "AI Powered",
                description: "Smart suggestions",
                accentColor: .purple
            )

            FeatureRow(icon: "star.fill", text: "Premium feature")

            SetupStage(name: "Configuration", isComplete: true)
            SetupStage(name: "Verification", isComplete: false)

            ProgressBarView(progress: 0.6, label: "Loading...")

            InfoBanner(message: "Click Grant to open System Settings", style: .info)
        }
        .padding()
        .frame(width: 400)
    }
}
#endif
