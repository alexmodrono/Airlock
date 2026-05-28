// AirlockFlowView.swift
// AirlockUI
//
// Main container view for declarative onboarding flows.

import SwiftUI
import AirlockCore

/// Shared layout constants for the onboarding window.
enum AirlockLayout {
    /// Margin around the card where the rainbow halo shows.
    static let haloMargin: CGFloat = 80
}

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

    /// When `true`, all other apps are hidden once as the intro animation
    /// starts, to draw the user's attention to onboarding. It's a one-time
    /// gesture — the apps reappear the moment the user switches back to them,
    /// so it isn't obtrusive. Only takes effect when `showIntro` is `true`.
    public var hidesOtherAppsDuringIntro: Bool

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
        hidesOtherAppsDuringIntro: Bool = true
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
        self.hidesOtherAppsDuringIntro = hidesOtherAppsDuringIntro
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
/// AirlockFlowView(
///     navigator: navigator,
///     configuration: AirlockConfiguration(showIntro: true)
/// )
/// ```
public struct AirlockFlowView: View {
    @ObservedObject var navigator: AirlockNavigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var cardScale: Double = 0.95
    @State private var cardOpacity: Double = 0
    @State private var introComplete: Bool = false
    @State private var didHideOtherApps: Bool = false
    @State private var savedPresentationOptions: NSApplication.PresentationOptions?
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

    /// The total window size: the card plus a margin for the shadow and the
    /// subtle intro rim glow.
    private var windowSize: CGSize {
        CGSize(
            width: configuration.cardWidth + AirlockLayout.haloMargin * 2,
            height: configuration.cardHeight + AirlockLayout.haloMargin * 2
        )
    }

    /// Whether the Escape-hint pill should be visible.
    private var shouldShowEscHint: Bool {
        if introComplete { return true }
        return configuration.showIntro && configuration.allowSkipIntro && showSkipHint
    }

    /// The Escape-hint pill's current text.
    private var escHintText: String {
        introComplete
            ? "Press the esc key to close the onboarding"
            : "Press the esc key to skip"
    }

    public var body: some View {
        ZStack {
            // Centered card with the intro animation or the main content.
            // The window itself is transparent — no fullscreen blur, no rainbow
            // background; the rainbow only appears as a rim glow during the intro.
            VStack(spacing: 12) {
                AirlockCardView(
                    navigator: navigator,
                    configuration: configuration,
                    introComplete: $introComplete,
                    animationController: animationController
                )
                .scaleEffect(cardScale)
                .opacity(cardOpacity)

                // A single keyboard-hint pill below the card. The same pill is
                // reused throughout: only its text changes (skip during the
                // intro, close afterwards), crossfading between the two.
                if shouldShowEscHint {
                    AirlockHintPill(text: escHintText)
                        .transition(skipHintTransition)
                }
            }
            .animation(skipHintAnimation, value: showSkipHint)
            .animation(introStateAnimation, value: introComplete)
        }
        .frame(width: windowSize.width, height: windowSize.height)
        .background(WindowAccessor())
        .onAppear {
            handleAppear()
        }
        .onChange(of: introComplete) { _, complete in
            if complete {
                showSkipHint = false
                // The intro is over: bring the Dock back and remap Esc to close.
                restoreDock()
                installEscapeMonitor { dismissWithAnimation() }
            }
        }
        .onDisappear {
            handleDisappear()
        }
    }

    // MARK: - Private Methods

    /// Installs a local key monitor that runs `action` when Escape is pressed,
    /// replacing any previous monitor. Used to map Escape to "skip" during the
    /// intro and to "close" afterwards.
    private func installEscapeMonitor(_ action: @escaping @MainActor () -> Void) {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event } // Escape
            Task { @MainActor in action() }
            return nil
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
            // No intro: the onChange(introComplete) handler installs the
            // Escape-to-close monitor.
            introComplete = true
            return
        }

        if configuration.hidesOtherAppsDuringIntro {
            focusForIntro()
        }

        if configuration.playIntroSound {
            playStartupSound()
        }

        if configuration.allowSkipIntro {
            installEscapeMonitor { skipIntroAnimation() }
            scheduleSkipHint()
        }
    }

    /// One-time attention grab: bring this app forward, hide the other apps,
    /// and hide the Dock. Other apps return as soon as the user switches to
    /// them; the Dock is restored when the intro ends (see ``restoreDock()``).
    private func focusForIntro() {
        guard !didHideOtherApps else { return }
        didHideOtherApps = true
        NSApp.activate(ignoringOtherApps: true)
        NSApp.hideOtherApplications(nil)
        hideDock()
    }

    private func hideDock() {
        guard savedPresentationOptions == nil else { return }
        let current = NSApp.presentationOptions
        savedPresentationOptions = current
        var updated = current
        updated.remove(.autoHideDock)
        updated.insert(.hideDock)
        NSApp.presentationOptions = updated
    }

    /// Restores the Dock to whatever it was before the intro hid it.
    private func restoreDock() {
        guard let saved = savedPresentationOptions else { return }
        NSApp.presentationOptions = saved
        savedPresentationOptions = nil
    }

    private func handleDisappear() {
        dismissTask?.cancel()
        skipHintTask?.cancel()
        soundFadeTask?.cancel()
        startupSound?.stop()
        startupSound = nil
        removeKeyMonitor()
        restoreDock()
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

    var body: some View {
        ZStack {
            // Subtle rainbow rim glow, only while the intro is playing.
            if configuration.showIntro && !introComplete {
                AirlockIntroGlow(
                    cardWidth: configuration.cardWidth,
                    cardHeight: configuration.cardHeight
                )
                .transition(.opacity)
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
                        HelloAnimationView(
                            controller: animationController,
                            duration: configuration.introDuration
                        ) {
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
            }
        }
    }

    private func completeIntro() {
        withAnimation(introCompletionAnimation) {
            introComplete = true
        }
        withAnimation(contentAnimation) {
            contentOpacity = 1
        }
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

