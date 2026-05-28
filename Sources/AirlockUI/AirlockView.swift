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

    @State private var cardScale: Double = 0.95
    @State private var cardOpacity: Double = 0
    @State private var introComplete: Bool = false
    @State private var didHideOtherApps: Bool = false
    @State private var savedPresentationOptions: NSApplication.PresentationOptions?
    @State private var startupSound: NSSound?
    @State private var showSkipHint: Bool = false
    @State private var keyMonitor: Any?
    @State private var dismissTask: Task<Void, Never>?
    @State private var skipHintTask: Task<Void, Never>?
    @State private var soundFadeTask: Task<Void, Never>?
    @StateObject private var animationController = HelloAnimationController()

    private let showIntro: Bool
    private let introDuration: Double
    private let hidesOtherAppsDuringIntro: Bool

    /// The total window size: the fixed card plus a margin for the shadow and
    /// the subtle intro rim glow.
    private var windowSize: CGSize {
        CGSize(
            width: 820 + AirlockLayout.haloMargin * 2,
            height: 580 + AirlockLayout.haloMargin * 2
        )
    }

    /// Creates an AirlockView.
    /// - Parameters:
    ///   - manager: The AirlockManager controlling the onboarding flow
    ///   - showIntroAnimation: Whether to show the "hello" intro animation (default: true)
    ///   - introDuration: Duration of the intro animation in seconds (default: 2.5)
    ///   - hidesOtherAppsDuringIntro: Hide other apps once as the intro starts,
    ///     to grab attention. They return as soon as the user switches back, so
    ///     it isn't obtrusive. Only applies when `showIntroAnimation` is true.
    public init(
        manager: AirlockManager,
        showIntroAnimation: Bool = true,
        introDuration: Double = 2.5,
        hidesOtherAppsDuringIntro: Bool = true
    ) {
        self.manager = manager
        self.showIntro = showIntroAnimation
        self.introDuration = introDuration
        self.hidesOtherAppsDuringIntro = hidesOtherAppsDuringIntro
    }

    public var body: some View {
        ZStack {
            // Centered card with the intro animation or the main content.
            // The window itself is transparent — no fullscreen blur, no rainbow
            // background; the rainbow only appears as a rim glow during the intro.
            VStack(spacing: 12) {
                AirlockCardWithIntro(
                    manager: manager,
                    showIntro: showIntro,
                    introDuration: introDuration,
                    introComplete: $introComplete,
                    animationController: animationController
                )
                .scaleEffect(cardScale)
                .opacity(cardOpacity)

                // Keyboard hint pill below the card. During the intro it offers
                // to skip; once onboarding is showing it offers to close. Same
                // style for both so it reads consistently.
                Group {
                    if !introComplete {
                        if showIntro && showSkipHint {
                            AirlockHintPill(text: "Press the esc key to skip")
                                .transition(skipHintTransition)
                        }
                    } else {
                        AirlockHintPill(text: "Press the esc key to close the onboarding")
                            .transition(.opacity)
                    }
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
                manager.startValidation()
            }
        }
        .onDisappear {
            handleDisappear()
        }
    }

    /// Installs a local key monitor that runs `action` when Escape is pressed,
    /// replacing any previous monitor. Maps Escape to "skip" during the intro
    /// and to "close" afterwards.
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
            manager.complete()
        }
    }

    private func startAnimations() {
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

        guard showIntro else {
            // No intro: the onChange(introComplete) handler installs the
            // Escape-to-close monitor.
            introComplete = true
            return
        }

        if hidesOtherAppsDuringIntro {
            focusForIntro()
        }

        playStartupSound()
        installEscapeMonitor { skipIntroAnimation() }
        scheduleSkipHint()
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
        manager.stopValidation()
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

    var body: some View {
        ZStack {
            // Subtle rainbow rim glow, only while the intro is playing.
            if showIntro && !introComplete {
                AirlockIntroGlow(cardWidth: 820, cardHeight: 580)
                    .transition(.opacity)
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

// MARK: - Hint Pill

/// A small, subtle frosted pill used for the keyboard hints shown beneath the
/// card (e.g. "Press Esc to skip" during the intro, and the close hint after).
/// Shared so both hints look identical.
struct AirlockHintPill: View {
    let text: String

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.08), lineWidth: 0.5)
            )
            .accessibilityLabel(text)
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
