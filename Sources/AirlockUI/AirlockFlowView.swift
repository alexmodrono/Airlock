// AirlockFlowView.swift
// AirlockUI
//
// Main container view for declarative onboarding flows.

import SwiftUI
import AirlockCore

/// Configuration for the onboarding flow appearance and behavior.
public struct AirlockConfiguration {
    /// Custom intro animation view. If nil, uses the default Lottie animation.
    public var introView: AnyView?

    /// Whether to show the intro animation.
    public var showIntro: Bool

    /// Duration of the intro animation in seconds.
    public var introDuration: Double

    /// Custom intro sound URL. If nil, uses the default startup sound.
    public var introSoundURL: URL?

    /// Whether to play the intro sound.
    public var playIntroSound: Bool

    /// Whether users can skip the intro by pressing Escape.
    public var allowSkipIntro: Bool

    /// Card dimensions.
    public var cardWidth: CGFloat
    public var cardHeight: CGFloat

    /// Sidebar width.
    public var sidebarWidth: CGFloat

    /// Callback when the user dismisses the flow via X button (before completing).
    /// If nil, dismissing will call navigator.complete() as usual.
    public var onDismiss: (() -> Void)?

    /// Creates a configuration with default values.
    public init(
        introView: AnyView? = nil,
        showIntro: Bool = true,
        introDuration: Double = 2.5,
        introSoundURL: URL? = nil,
        playIntroSound: Bool = true,
        allowSkipIntro: Bool = true,
        cardWidth: CGFloat = 820,
        cardHeight: CGFloat = 580,
        sidebarWidth: CGFloat = 280,
        onDismiss: (() -> Void)? = nil
    ) {
        self.introView = introView
        self.showIntro = showIntro
        self.introDuration = introDuration
        self.introSoundURL = introSoundURL
        self.playIntroSound = playIntroSound
        self.allowSkipIntro = allowSkipIntro
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.sidebarWidth = sidebarWidth
        self.onDismiss = onDismiss
    }

    /// Default configuration.
    public static let `default` = AirlockConfiguration()
}

/// The main container view for an onboarding flow.
///
/// AirlockFlowView provides a two-column layout with:
/// - A sidebar showing progress through the steps
/// - A viewport displaying the current step's content
/// - Optional intro animation
/// - Smooth transitions between steps
///
/// Example:
/// ```swift
/// @StateObject private var navigator = AirlockNavigator(
///     appName: "MyApp",
///     steps: mySteps
/// )
///
/// AirlockFlowView(navigator: navigator)
///     .airlockConfiguration(.init(showIntro: true))
/// ```
public struct AirlockFlowView: View {
    @ObservedObject var navigator: AirlockNavigator
    @Environment(\.colorScheme) private var colorScheme

    @State private var overlayOpacity: Double = 0
    @State private var cardScale: Double = 0.95
    @State private var cardOpacity: Double = 0
    @State private var introComplete: Bool = false
    @State private var showSkipHint: Bool = false
    @State private var keyMonitor: Any?
    @State private var startupSound: NSSound?
    @FocusState private var isFocused: Bool
    @StateObject private var animationController = HelloAnimationController()

    private var configuration: AirlockConfiguration

    /// Creates a flow view with a navigator.
    /// - Parameters:
    ///   - navigator: The navigator managing the flow state
    ///   - configuration: Optional configuration for appearance and behavior
    public init(
        navigator: AirlockNavigator,
        configuration: AirlockConfiguration = .default
    ) {
        self.navigator = navigator
        self.configuration = configuration
    }

    public var body: some View {
        ZStack {
            // Fullscreen blurred and dimmed overlay
            VisualEffectBlur(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()
                .overlay(
                    Color.black.opacity(colorScheme == .dark ? 0.5 : 0.3)
                )
                .opacity(overlayOpacity)

            // Main content
            VStack {
                // Exit button in top-right corner (only show after intro)
                HStack {
                    Spacer()
                    ExitButton {
                        dismissWithAnimation()
                    }
                }
                .padding(.trailing, 40)
                .padding(.top, 40)
                .opacity(introComplete ? cardOpacity : 0)

                Spacer()

                // Card with intro animation or main content
                AirlockCardView(
                    navigator: navigator,
                    configuration: configuration,
                    introComplete: $introComplete,
                    animationController: animationController
                )
                .scaleEffect(cardScale)
                .opacity(cardOpacity)

                Spacer()

                // Skip hint at bottom (only during intro)
                if configuration.showIntro && !introComplete && showSkipHint && configuration.allowSkipIntro {
                    Text("Press Esc to skip")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.bottom, 20)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: showSkipHint)
            .animation(.easeInOut(duration: 0.2), value: introComplete)
        }
        .focusable()
        .focused($isFocused)
        .background(WindowAccessor())
        .onAppear {
            startAnimations()
            if configuration.playIntroSound {
                playStartupSound()
            }
            if configuration.allowSkipIntro {
                setupKeyMonitor()
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }

            if !configuration.showIntro {
                introComplete = true
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    if !introComplete {
                        showSkipHint = true
                    }
                }
            }
        }
        .onChange(of: introComplete) { _, complete in
            if complete {
                showSkipHint = false
                removeKeyMonitor()
            }
        }
        .onDisappear {
            startupSound?.stop()
            removeKeyMonitor()
        }
        .onKeyPress(.escape) {
            if !introComplete && configuration.showIntro && configuration.allowSkipIntro {
                skipIntroAnimation()
                return .handled
            }
            return .ignored
        }
    }

    // MARK: - Private Methods

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                if !introComplete && configuration.showIntro {
                    DispatchQueue.main.async {
                        skipIntroAnimation()
                    }
                    return nil
                }
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func dismissWithAnimation() {
        withAnimation(.easeOut(duration: 0.25)) {
            overlayOpacity = 0
            cardOpacity = 0
            cardScale = 0.95
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            // If onDismiss is provided, call it instead of completing normally
            if let onDismiss = configuration.onDismiss {
                onDismiss()
            } else {
                navigator.complete()
            }
        }
    }

    private func startAnimations() {
        withAnimation(.easeOut(duration: 0.4)) {
            overlayOpacity = 1
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
            cardScale = 1.0
            cardOpacity = 1
        }
    }

    private func playStartupSound() {
        let soundURL: URL?
        if let customURL = configuration.introSoundURL {
            soundURL = customURL
        } else {
            soundURL = Bundle.module.url(forResource: "startup", withExtension: "wav")
        }

        if let url = soundURL, let sound = NSSound(contentsOf: url, byReference: true) {
            sound.play()
            startupSound = sound
        }
    }

    private func skipIntroAnimation() {
        showSkipHint = false
        fadeOutSound()
        animationController.skip()
    }

    private func fadeOutSound() {
        guard let sound = startupSound, sound.isPlaying else { return }

        let fadeSteps = 10
        let fadeDuration = 0.3
        let stepDuration = fadeDuration / Double(fadeSteps)
        let volumeStep = sound.volume / Float(fadeSteps)

        for step in 0..<fadeSteps {
            DispatchQueue.main.asyncAfter(deadline: .now() + stepDuration * Double(step)) {
                sound.volume = max(0, sound.volume - volumeStep)
                if step == fadeSteps - 1 {
                    sound.stop()
                }
            }
        }
    }
}

// MARK: - Card View

private struct AirlockCardView: View {
    @ObservedObject var navigator: AirlockNavigator
    let configuration: AirlockConfiguration
    @Binding var introComplete: Bool
    @ObservedObject var animationController: HelloAnimationController

    @Environment(\.colorScheme) private var colorScheme
    @State private var contentOpacity: Double = 0
    @State private var glowPhase: CGFloat = 0
    @State private var glowOpacity: Double = 0

    var body: some View {
        ZStack {
            // Animated glow behind the card (only during intro)
            if configuration.showIntro && !introComplete {
                AnimatedGlowEffect(phase: glowPhase, colors: StartupAnimationView.defaultGlowColors)
                    .frame(width: configuration.cardWidth + 40, height: configuration.cardHeight + 40)
                    .blur(radius: 40)
                    .opacity(glowOpacity)
            }

            // Card content
            ZStack {
                // Solid backing
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.black : Color.white)

                // Card background with native material
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)

                // Subtle accent overlay
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(colorScheme == .dark ? 0.08 : 0.03),
                                Color.clear
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                // Border
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        Color.primary.opacity(colorScheme == .dark ? 0.2 : 0.1),
                        lineWidth: 0.5
                    )

                // Content
                if configuration.showIntro && !introComplete {
                    // Intro animation
                    if let customIntro = configuration.introView {
                        customIntro
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .transition(.opacity)
                            .onAppear {
                                // Auto-complete intro after duration
                                DispatchQueue.main.asyncAfter(deadline: .now() + configuration.introDuration) {
                                    if !introComplete {
                                        withAnimation(.easeOut(duration: 0.5)) {
                                            glowOpacity = 0
                                        }
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            introComplete = true
                                        }
                                        withAnimation(.easeIn(duration: 0.3).delay(0.1)) {
                                            contentOpacity = 1
                                        }
                                    }
                                }
                            }
                    } else {
                        HelloAnimationView(controller: animationController) {
                            withAnimation(.easeOut(duration: 0.5)) {
                                glowOpacity = 0
                            }
                            withAnimation(.easeInOut(duration: 0.4)) {
                                introComplete = true
                            }
                            withAnimation(.easeIn(duration: 0.3).delay(0.1)) {
                                contentOpacity = 1
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                    }
                } else {
                    // Main content
                    HStack(spacing: 0) {
                        // Left column: Sidebar
                        AirlockSidebarView(navigator: navigator)
                            .frame(width: configuration.sidebarWidth)

                        // Divider
                        Rectangle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(width: 1)

                        // Right column: Viewport
                        AirlockViewportView(navigator: navigator)
                            .frame(
                                width: configuration.cardWidth - configuration.sidebarWidth - 1,
                                height: configuration.cardHeight
                            )
                            .clipped()
                    }
                    .opacity(contentOpacity)
                    .transition(.opacity)
                }
            }
            .frame(width: configuration.cardWidth, height: configuration.cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 10)
            .shadow(color: .black.opacity(0.15), radius: 60, x: 0, y: 20)
        }
        .onAppear {
            if !configuration.showIntro {
                contentOpacity = 1
            } else {
                withAnimation(.easeIn(duration: 0.5)) {
                    glowOpacity = 0.6
                }
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    glowPhase = 1
                }
            }
        }
    }
}

// MARK: - Sidebar View

private struct AirlockSidebarView: View {
    @ObservedObject var navigator: AirlockNavigator
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header with app icon and name
            HeaderView(
                appName: navigator.appName,
                appIconName: navigator.appIconName
            )
            .padding(.horizontal, 24)
            .padding(.top, 28)

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
                .padding(.vertical, 16)
                .padding(.horizontal, 24)

            // Steps list
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Array(navigator.steps.enumerated()), id: \.element.id) { index, step in
                        let status = navigator.status(at: index)
                        let isCurrent = index == navigator.currentIndex
                        let canNavigate = status == .completed

                        AirlockStepRowView(
                            title: step.title,
                            icon: step.icon,
                            status: status,
                            isCurrent: isCurrent
                        )
                        .opacity(canNavigate || isCurrent ? 1.0 : 0.6)
                        .onTapGesture {
                            if canNavigate {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    navigator.goTo(index: index)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            // Continue button
            AirlockContinueButton(navigator: navigator)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
        .background(
            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.03 : 0.02))
        )
    }
}

// MARK: - Step Row View

private struct AirlockStepRowView: View {
    let title: String
    let icon: String
    let status: AirlockStepStatus
    let isCurrent: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovering = false

    private var statusColor: Color {
        switch status {
        case .pending: return .secondary
        case .current: return .accentColor
        case .completed: return .green
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.15))
                    .frame(width: 32, height: 32)

                if status == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                        .foregroundStyle(statusColor)
                }
            }

            // Title
            Text(title)
                .font(.system(size: 13, weight: isCurrent ? .semibold : .regular))
                .foregroundStyle(isCurrent ? .primary : .secondary)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isCurrent ? Color.accentColor.opacity(0.1) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isCurrent ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

// MARK: - Viewport View

private struct AirlockViewportView: View {
    @ObservedObject var navigator: AirlockNavigator

    var body: some View {
        ZStack {
            if let step = navigator.currentStep {
                ScrollViewWithOverlayIndicator {
                    step.content
                        .frame(minHeight: 540)
                        .frame(maxWidth: .infinity)
                        .environment(\.airlockNavigator, navigator)
                        .environment(\.airlockStepStatus, navigator.status(for: step.id))
                        .environment(\.airlockCanContinue, navigator.canContinue)
                        .environment(\.airlockStepIndex, navigator.currentIndex)
                        .environment(\.airlockStepCount, navigator.steps.count)
                        .environment(\.airlockIsLastStep, navigator.isLastStep)
                        .environment(\.airlockCanGoBack, navigator.canGoBack)
                }
                .transition(.opacity)
                .id(step.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: navigator.currentIndex)
    }
}

// MARK: - Continue Button

/// The continue button for advancing through the onboarding flow.
public struct AirlockContinueButton: View {
    @ObservedObject var navigator: AirlockNavigator

    @State private var isHovering = false

    private var buttonText: String {
        if navigator.isLastStep && navigator.canContinue {
            return "Get Started"
        }
        return "Continue"
    }

    private var buttonIcon: String {
        if navigator.isLastStep && navigator.canContinue {
            return "arrow.right.circle.fill"
        }
        return "arrow.forward"
    }

    public init(navigator: AirlockNavigator) {
        self.navigator = navigator
    }

    public var body: some View {
        Button {
            navigator.goToNext()
        } label: {
            HStack(spacing: 8) {
                if navigator.isValidating {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: buttonIcon)
                        .font(.system(size: 16, weight: .medium))
                }
                Text(buttonText)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(navigator.canContinue ? Color.accentColor : Color.secondary.opacity(0.2))
            )
            .foregroundColor(navigator.canContinue ? .white : .secondary)
            .scaleEffect(isHovering && navigator.canContinue ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: navigator.canContinue)
        }
        .buttonStyle(.plain)
        .disabled(!navigator.canContinue || navigator.isValidating)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - View Modifier

public extension View {
    /// Configures the onboarding flow appearance.
    func airlockConfiguration(_ configuration: AirlockConfiguration) -> some View {
        environment(\.airlockConfigurationKey, configuration)
    }
}

private struct AirlockConfigurationKey: EnvironmentKey {
    static let defaultValue = AirlockConfiguration.default
}

extension EnvironmentValues {
    var airlockConfigurationKey: AirlockConfiguration {
        get { self[AirlockConfigurationKey.self] }
        set { self[AirlockConfigurationKey.self] = newValue }
    }
}
