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

    /// When `true`, the fullscreen immersive overlay is only shown during the
    /// intro animation.  After the intro completes the window shrinks to card
    /// size and behaves like a normal app window — users can Cmd-Tab, access the
    /// menu bar, and use other apps alongside the onboarding flow.
    ///
    /// Defaults to `false` to preserve the original fullscreen behavior.
    public var immersiveIntroOnly: Bool

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
        onDismiss: (() -> Void)? = nil,
        immersiveIntroOnly: Bool = false
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
        self.immersiveIntroOnly = immersiveIntroOnly
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var overlayOpacity: Double = 0
    @State private var cardScale: Double = 0.95
    @State private var cardOpacity: Double = 0
    @State private var introComplete: Bool = false
    @State private var showSkipHint: Bool = false
    @State private var keyMonitor: Any?
    @State private var startupSound: NSSound?
    @State private var dismissTask: Task<Void, Never>?
    @State private var skipHintTask: Task<Void, Never>?
    @State private var soundFadeTask: Task<Void, Never>?
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

    /// Whether the overlay should currently be in immersive (fullscreen) mode.
    private var isImmersive: Bool {
        !(configuration.immersiveIntroOnly && introComplete)
    }

    public var body: some View {
        ZStack {
            // Fullscreen blurred and dimmed overlay (hidden once demoted)
            if isImmersive {
                VisualEffectBlur(material: .fullScreenUI, blendingMode: .behindWindow)
                    .ignoresSafeArea()
                    .overlay(
                        Color.black.opacity(colorScheme == .dark ? 0.5 : 0.3)
                    )
                    .opacity(overlayOpacity)
                    .transition(.opacity)
            }

            // Main content
            VStack {
                // Exit button in top-right corner (only show after intro, immersive only)
                if isImmersive {
                    HStack {
                        Spacer()
                        ExitButton {
                            dismissWithAnimation()
                        }
                    }
                    .padding(.trailing, 40)
                    .padding(.top, 40)
                    .opacity(introComplete ? cardOpacity : 0)
                }

                Spacer()

                // Card with intro animation or main content
                AirlockCardView(
                    navigator: navigator,
                    configuration: configuration,
                    introComplete: $introComplete,
                    animationController: animationController
                )
                .overlay(alignment: .topTrailing) {
                    // Close button pinned to the card in windowed mode
                    if !isImmersive && introComplete {
                        ExitButton {
                            dismissWithAnimation()
                        }
                        .padding(.trailing, 12)
                        .padding(.top, 12)
                        .transition(.opacity)
                    }
                }
                .scaleEffect(cardScale)
                .opacity(cardOpacity)

                Spacer()

                // Skip hint at bottom (only during intro)
                if configuration.showIntro && !introComplete && showSkipHint && configuration.allowSkipIntro {
                    Text("Press Esc to skip")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.bottom, 20)
                        .transition(skipHintTransition)
                }
            }
            .animation(skipHintAnimation, value: showSkipHint)
            .animation(introStateAnimation, value: introComplete)
        }
        .background(
            WindowAccessor(
                isImmersive: isImmersive,
                cardSize: CGSize(
                    width: configuration.cardWidth,
                    height: configuration.cardHeight
                )
            )
        )
        .onAppear {
            handleAppear()
        }
        .onChange(of: introComplete) { _, complete in
            if complete {
                showSkipHint = false
                removeKeyMonitor()
            }
        }
        .onDisappear {
            handleDisappear()
        }
    }

    // MARK: - Private Methods

    private func setupKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Escape
                if !introComplete && configuration.showIntro {
                    Task { @MainActor in
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
        dismissTask?.cancel()
        withAnimation(dismissAnimation) {
            overlayOpacity = 0
            cardOpacity = 0
            cardScale = 0.95
        }
        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: dismissalDelayNanoseconds)
            guard !Task.isCancelled else { return }

            // If onDismiss is provided, call it instead of completing normally
            if let onDismiss = configuration.onDismiss {
                onDismiss()
            } else {
                navigator.complete()
            }
        }
    }

    private func startAnimations() {
        withAnimation(overlayAnimation) {
            overlayOpacity = 1
        }
        withAnimation(cardAnimation) {
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
        skipHintTask?.cancel()
        fadeOutSound()
        animationController.skip()
    }

    private func fadeOutSound() {
        guard let sound = startupSound, sound.isPlaying else { return }
        soundFadeTask?.cancel()
        let originalVolume = sound.volume

        soundFadeTask = Task { @MainActor in
            let fadeSteps = 10

            for step in 1...fadeSteps {
                try? await Task.sleep(nanoseconds: 30_000_000)
                guard !Task.isCancelled else { return }

                let remaining = Float(fadeSteps - step) / Float(fadeSteps)
                sound.volume = max(0, originalVolume * remaining)
            }

            sound.stop()
            startupSound = nil
        }
    }

    private func handleAppear() {
        startAnimations()

        guard configuration.showIntro else {
            introComplete = true
            return
        }

        if configuration.playIntroSound {
            playStartupSound()
        }

        if configuration.allowSkipIntro {
            setupKeyMonitor()
            scheduleSkipHint()
        }
    }

    private func handleDisappear() {
        dismissTask?.cancel()
        skipHintTask?.cancel()
        soundFadeTask?.cancel()
        startupSound?.stop()
        startupSound = nil
        removeKeyMonitor()
    }

    private func scheduleSkipHint() {
        skipHintTask?.cancel()
        skipHintTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, !introComplete else { return }
            showSkipHint = true
        }
    }

    private var skipHintTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom))
    }

    private var skipHintAnimation: Animation {
        .easeInOut(duration: reduceMotion ? 0.15 : 0.3)
    }

    private var introStateAnimation: Animation {
        .easeInOut(duration: reduceMotion ? 0.15 : 0.2)
    }

    private var overlayAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0.12 : 0.4)
    }

    private var cardAnimation: Animation {
        if reduceMotion {
            return .easeOut(duration: 0.12)
        }

        return .spring(response: 0.5, dampingFraction: 0.8).delay(0.1)
    }

    private var dismissAnimation: Animation {
        .easeOut(duration: dismissalDuration)
    }

    private var dismissalDuration: Double {
        reduceMotion ? 0.12 : 0.25
    }

    private var dismissalDelayNanoseconds: UInt64 {
        UInt64(dismissalDuration * 1_000_000_000)
    }
}

// MARK: - Card View

private struct AirlockCardView: View {
    @ObservedObject var navigator: AirlockNavigator
    let configuration: AirlockConfiguration
    @Binding var introComplete: Bool
    @ObservedObject var animationController: HelloAnimationController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
                            .task(id: configuration.introDuration) {
                                try? await Task.sleep(
                                    nanoseconds: UInt64(configuration.introDuration * 1_000_000_000)
                                )
                                guard !Task.isCancelled, !introComplete else { return }
                                completeIntro()
                            }
                    } else {
                        HelloAnimationView(controller: animationController) {
                            completeIntro()
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
            .clipShape(.rect(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 10)
            .shadow(color: .black.opacity(0.15), radius: 60, x: 0, y: 20)
        }
        .onAppear {
            if !configuration.showIntro {
                contentOpacity = 1
            } else {
                withAnimation(glowAnimation) {
                    glowOpacity = reduceMotion ? 0.25 : 0.6
                }
                if !reduceMotion {
                    withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                        glowPhase = 1
                    }
                }
            }
        }
    }

    private func completeIntro() {
        withAnimation(glowFadeAnimation) {
            glowOpacity = 0
        }
        withAnimation(introCompletionAnimation) {
            introComplete = true
        }
        withAnimation(contentAnimation) {
            contentOpacity = 1
        }
    }

    private var glowAnimation: Animation {
        .easeIn(duration: reduceMotion ? 0.2 : 0.5)
    }

    private var glowFadeAnimation: Animation {
        .easeOut(duration: reduceMotion ? 0.2 : 0.5)
    }

    private var introCompletionAnimation: Animation {
        .easeInOut(duration: reduceMotion ? 0.2 : 0.4)
    }

    private var contentAnimation: Animation {
        if reduceMotion {
            return .easeIn(duration: 0.2)
        }

        return .easeIn(duration: 0.3).delay(0.1)
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
                LazyVStack(spacing: 8) {
                    ForEach(navigator.steps.indices, id: \.self) { index in
                        let step = navigator.steps[index]
                        let status = navigator.status(at: index)
                        let isCurrent = index == navigator.currentIndex
                        let canNavigate = status == .completed

                        if canNavigate {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    navigator.goTo(index: index)
                                }
                            } label: {
                                AirlockStepRowView(
                                    title: step.title,
                                    icon: step.icon,
                                    status: status,
                                    isCurrent: isCurrent
                                )
                                .opacity(1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this completed step")
                        } else {
                            AirlockStepRowView(
                                title: step.title,
                                icon: step.icon,
                                status: status,
                                isCurrent: isCurrent
                            )
                            .opacity(isCurrent ? 1.0 : 0.6)
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
        if let custom = navigator.buttonLabel {
            return custom
        }
        if navigator.isLastStep && navigator.canContinue {
            return "Get Started"
        }
        return "Continue"
    }

    private var buttonIcon: String {
        if let custom = navigator.buttonIcon {
            return custom
        }
        if navigator.isLastStep && navigator.canContinue {
            return "arrow.right.circle.fill"
        }
        return "arrow.forward"
    }

    private var isBusy: Bool {
        navigator.isValidating || navigator.isRunningAction
    }

    public init(navigator: AirlockNavigator) {
        self.navigator = navigator
    }

    public var body: some View {
        Button {
            navigator.goToNext()
        } label: {
            HStack(spacing: 8) {
                if isBusy {
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
            .foregroundStyle(navigator.canContinue ? .white : .secondary)
            .scaleEffect(isHovering && navigator.canContinue ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: navigator.canContinue)
        }
        .buttonStyle(.plain)
        .disabled(!navigator.canContinue || isBusy)
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
