// AirlockView.swift
// AirlockUI

import SwiftUI
import AirlockCore

/// The main two-column onboarding view.
///
/// Displays a fullscreen overlay with a centered card containing
/// flight checks on the left and a context-sensitive detail view on the right.
/// Optionally shows an intro "hello" animation before the main content.
/// Press Escape during the intro to skip the animation smoothly.
public struct AirlockView: View {
    @ObservedObject var manager: AirlockManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    @State private var overlayOpacity: Double = 0
    @State private var cardScale: Double = 0.95
    @State private var cardOpacity: Double = 0
    @State private var introComplete: Bool = false
    @State private var startupSound: NSSound?
    @State private var showSkipHint: Bool = false
    @State private var keyMonitor: Any?
    @State private var dismissTask: Task<Void, Never>?
    @State private var focusTask: Task<Void, Never>?
    @State private var skipHintTask: Task<Void, Never>?
    @State private var soundFadeTask: Task<Void, Never>?
    @FocusState private var isFocused: Bool
    @StateObject private var animationController = HelloAnimationController()

    private let showIntro: Bool
    private let introDuration: Double

    /// Creates an AirlockView.
    /// - Parameters:
    ///   - manager: The AirlockManager controlling the onboarding flow
    ///   - showIntroAnimation: Whether to show the "hello" intro animation (default: true)
    ///   - introDuration: Duration of the intro animation in seconds (default: 2.5)
    public init(
        manager: AirlockManager,
        showIntroAnimation: Bool = true,
        introDuration: Double = 2.5
    ) {
        self.manager = manager
        self.showIntro = showIntroAnimation
        self.introDuration = introDuration
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
                AirlockCardWithIntro(
                    manager: manager,
                    showIntro: showIntro,
                    introDuration: introDuration,
                    introComplete: $introComplete,
                    animationController: animationController
                )
                .scaleEffect(cardScale)
                .opacity(cardOpacity)

                Spacer()

                // Skip hint at bottom (only during intro)
                if showIntro && !introComplete && showSkipHint {
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
        .focusable()
        .focused($isFocused)
        .background(WindowAccessor())
        .onAppear {
            handleAppear()
        }
        .onChange(of: introComplete) { _, complete in
            if complete {
                showSkipHint = false
                removeKeyMonitor()
                manager.startValidation()
            }
        }
        .onDisappear {
            handleDisappear()
        }
        .onKeyPress(.escape) {
            if !introComplete && showIntro {
                skipIntroAnimation()
                return .handled
            }
            return .ignored
        }
    }

    private func setupKeyMonitor() {
        // Use NSEvent local monitor as a fallback for key detection during animations
        // This ensures Escape key works even when SwiftUI focus system is unreliable
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [self] event in
            if event.keyCode == 53 { // 53 is the key code for Escape
                if !introComplete && showIntro {
                    Task { @MainActor in
                        skipIntroAnimation()
                    }
                    return nil // Consume the event
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
            manager.complete()
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
        // Play bundled startup sound
        if let soundURL = Bundle.module.url(forResource: "startup", withExtension: "wav") {
            if let sound = NSSound(contentsOf: soundURL, byReference: true) {
                sound.play()
                startupSound = sound
            }
        }
    }

    private func skipIntroAnimation() {
        // Hide the skip hint immediately
        showSkipHint = false
        skipHintTask?.cancel()

        // Fade out the sound
        fadeOutSound()

        // Accelerate the animation
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
        scheduleFocus()

        guard showIntro else {
            introComplete = true
            return
        }

        playStartupSound()
        setupKeyMonitor()
        scheduleSkipHint()
    }

    private func handleDisappear() {
        dismissTask?.cancel()
        focusTask?.cancel()
        skipHintTask?.cancel()
        soundFadeTask?.cancel()
        manager.stopValidation()
        startupSound?.stop()
        startupSound = nil
        removeKeyMonitor()
    }

    private func scheduleFocus() {
        focusTask?.cancel()
        focusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            isFocused = true
        }
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

// MARK: - Airlock Card With Intro

/// A card that shows the intro animation first, then transitions to the main content.
struct AirlockCardWithIntro: View {
    @ObservedObject var manager: AirlockManager
    let showIntro: Bool
    let introDuration: Double
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
            if showIntro && !introComplete {
                AnimatedGlowEffect(phase: glowPhase, colors: StartupAnimationView.defaultGlowColors)
                    .frame(width: 860, height: 620)
                    .blur(radius: 40)
                    .opacity(glowOpacity)
            }

            // Card content
            ZStack {
                // Solid backing to prevent seeing through to darkened background
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.black : Color.white)

                // Card background with native material
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)

                // Subtle accent overlay for depth
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

                // Content: either intro animation or main content
                if showIntro && !introComplete {
                    // Intro animation centered in card
                    HelloAnimationView(controller: animationController, duration: introDuration) {
                        completeIntro()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                } else {
                    // Main content
                    HStack(spacing: 0) {
                        // Left column: Flight checks sidebar
                        SidebarView(manager: manager)
                            .frame(width: 280)

                        // Divider
                        Rectangle()
                            .fill(Color.primary.opacity(0.1))
                            .frame(width: 1)

                        // Right column: Detail viewport with fixed size
                        ViewportView(manager: manager)
                            .frame(width: 540, height: 580)
                            .clipped()
                    }
                    .opacity(contentOpacity)
                    .transition(.opacity)
                }
            }
            .frame(width: 820, height: 580)
            .clipShape(.rect(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 10)
            .shadow(color: .black.opacity(0.15), radius: 60, x: 0, y: 20)
        }
        .onAppear {
            if !showIntro {
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

// MARK: - Visual Effect Blur

struct VisualEffectBlur: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// MARK: - Exit Button

struct ExitButton: View {
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label("Exit setup", systemImage: "xmark")
                .labelStyle(.iconOnly)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(isHovering ? 1.0 : 0.6))
                .frame(width: 28, height: 28)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isHovering ? 0.25 : 0.15))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .help("Exit setup")
        .accessibilityHint("Closes the setup flow")
    }
}


// MARK: - Sidebar View

struct SidebarView: View {
    @ObservedObject var manager: AirlockManager
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            // Header with app icon and name
            HeaderView(
                appName: manager.appName,
                appIconName: manager.appIconName
            )
            .padding(.horizontal, 24)
            .padding(.top, 28)

            // Divider
            Rectangle()
                .fill(Color.primary.opacity(0.1))
                .frame(height: 1)
                .padding(.vertical, 16)
                .padding(.horizontal, 24)

            // Flight checks list
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(manager.checks.indices, id: \.self) { index in
                        let check = manager.checks[index]
                        let isFocused = index == manager.focusedIndex
                        let canNavigate = check.status == .success

                        if canNavigate {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    manager.focusCheck(at: index)
                                }
                            } label: {
                                CheckRowView(
                                    check: check,
                                    isFocused: isFocused
                                )
                                .opacity(1)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("Opens this completed check")
                        } else {
                            CheckRowView(
                                check: check,
                                isFocused: isFocused
                            )
                            .opacity(isFocused ? 1.0 : 0.6)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }

            Spacer()

            // Launch button
            LaunchButton(
                isComplete: manager.isComplete,
                action: { manager.complete() }
            )
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(
            // Slightly different tint for sidebar
            Rectangle()
                .fill(Color.primary.opacity(colorScheme == .dark ? 0.03 : 0.02))
        )
    }
}

// MARK: - Viewport View

struct ViewportView: View {
    @ObservedObject var manager: AirlockManager

    var body: some View {
        ZStack {
            // Fixed-size container prevents layout shifts
            if let check = manager.focusedCheck {
                ScrollViewWithOverlayIndicator {
                    check.detailView
                        .frame(minHeight: 540)
                        .frame(maxWidth: .infinity)
                }
                .transition(.opacity)
                .id(check.id)
            } else {
                AllClearView()
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: manager.focusedIndex)
    }
}

// MARK: - Custom Scroll View with Overlay Indicator

struct ScrollViewWithOverlayIndicator<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
        }
        .background(
            ScrollViewConfigurator()
        )
    }
}

// MARK: - Scroll View Configurator

/// Configures the underlying NSScrollView to use overlay-style scrollers
private struct ScrollViewConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            context.coordinator.configureScrollView(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        private var startObserver: NSObjectProtocol?
        private var endObserver: NSObjectProtocol?
        private var hideTask: DispatchWorkItem?
        private weak var configuredScrollView: NSScrollView?

        func configureScrollView(from view: NSView) {
            // Find the scroll view
            var current: NSView? = view
            while let v = current {
                if let scrollView = v as? NSScrollView {
                    // Avoid reconfiguring the same scroll view
                    guard scrollView !== configuredScrollView else { return }
                    configuredScrollView = scrollView

                    // Use overlay style
                    scrollView.scrollerStyle = .overlay
                    scrollView.hasHorizontalScroller = false

                    // Configure scroller appearance
                    if let scroller = scrollView.verticalScroller {
                        scroller.controlSize = .mini
                        scroller.alphaValue = 0
                    }

                    // Remove old observers
                    if let obs = startObserver {
                        NotificationCenter.default.removeObserver(obs)
                    }
                    if let obs = endObserver {
                        NotificationCenter.default.removeObserver(obs)
                    }

                    // Show scroller on scroll start
                    startObserver = NotificationCenter.default.addObserver(
                        forName: NSScrollView.willStartLiveScrollNotification,
                        object: scrollView,
                        queue: .main
                    ) { [weak self] _ in
                        self?.hideTask?.cancel()
                        NSAnimationContext.runAnimationGroup { ctx in
                            ctx.duration = 0.15
                            scrollView.verticalScroller?.animator().alphaValue = 1
                        }
                    }

                    // Hide scroller after scroll ends
                    endObserver = NotificationCenter.default.addObserver(
                        forName: NSScrollView.didEndLiveScrollNotification,
                        object: scrollView,
                        queue: .main
                    ) { [weak self] _ in
                        self?.scheduleHide(scrollView: scrollView)
                    }

                    return
                }
                current = v.superview
            }
        }

        private func scheduleHide(scrollView: NSScrollView) {
            hideTask?.cancel()
            let task = DispatchWorkItem { [weak scrollView] in
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = 0.3
                    scrollView?.verticalScroller?.animator().alphaValue = 0
                }
            }
            hideTask = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: task)
        }

        deinit {
            if let obs = startObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            if let obs = endObserver {
                NotificationCenter.default.removeObserver(obs)
            }
            hideTask?.cancel()
        }
    }
}

// MARK: - Header View

struct HeaderView: View {
    let appName: String
    let appIconName: String?

    var body: some View {
        VStack(spacing: 12) {
            // App icon
            Group {
                if let iconName = appIconName {
                    Image(iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "app.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(.rect(cornerRadius: 14))
            .shadow(color: .black.opacity(0.2), radius: 8, y: 4)

            // Welcome text
            VStack(spacing: 4) {
                Text("Welcome to")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(appName)
                    .font(.title2)
                    .fontWeight(.semibold)
            }

            // Subtitle
            Text("Pre-Flight Check")
                .font(.caption)
                .textCase(.uppercase)
                .tracking(1.5)
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Launch Button

struct LaunchButton: View {
    let isComplete: Bool
    let action: () -> Void

    @State private var isHovering = false

    private var buttonText: String {
        isComplete ? "Get Started" : "Continue"
    }

    private var buttonIcon: String {
        isComplete ? "arrow.right.circle.fill" : "arrow.forward"
    }

    var body: some View {
        Button(action: action) {
            Label(buttonText, systemImage: buttonIcon)
                .font(.system(size: 14, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isComplete ? Color.accentColor : Color.secondary.opacity(0.2))
            )
            .foregroundStyle(isComplete ? .white : .secondary)
            .scaleEffect(isHovering && isComplete ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isComplete)
        }
        .buttonStyle(.plain)
        .disabled(!isComplete)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

// MARK: - All Clear View

struct AllClearView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)

            Text("All Systems Go")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Your pre-flight check is complete.\nClick Get Started to begin.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
