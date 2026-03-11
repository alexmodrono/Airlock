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
    @Environment(\.colorScheme) private var colorScheme

    @State private var overlayOpacity: Double = 0
    @State private var cardScale: Double = 0.95
    @State private var cardOpacity: Double = 0
    @State private var introComplete: Bool = false
    @State private var showIntroAnimation: Bool = true
    @State private var startupSound: NSSound?
    @State private var showSkipHint: Bool = false
    @State private var keyMonitor: Any?
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
            playStartupSound()
            setupKeyMonitor()

            // Request focus after a brief delay to ensure view is ready
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isFocused = true
            }

            if !showIntro {
                introComplete = true
            } else {
                // Show skip hint after a brief delay
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
                manager.startValidation()
            }
        }
        .onDisappear {
            manager.stopValidation()
            startupSound?.stop()
            removeKeyMonitor()
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
                    DispatchQueue.main.async {
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
        withAnimation(.easeOut(duration: 0.25)) {
            overlayOpacity = 0
            cardOpacity = 0
            cardScale = 0.95
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            manager.complete()
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

        // Fade out the sound
        fadeOutSound()

        // Accelerate the animation
        animationController.skip()
    }

    private func fadeOutSound() {
        guard let sound = startupSound, sound.isPlaying else { return }

        // Fade out over 300ms
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

// MARK: - Airlock Card With Intro

/// A card that shows the intro animation first, then transitions to the main content.
struct AirlockCardWithIntro: View {
    @ObservedObject var manager: AirlockManager
    let showIntro: Bool
    @Binding var introComplete: Bool
    @ObservedObject var animationController: HelloAnimationController

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
                    HelloAnimationView(controller: animationController) {
                        // Fade out glow
                        withAnimation(.easeOut(duration: 0.5)) {
                            glowOpacity = 0
                        }
                        withAnimation(.easeInOut(duration: 0.4)) {
                            introComplete = true
                        }
                        // Fade in content after intro
                        withAnimation(.easeIn(duration: 0.3).delay(0.1)) {
                            contentOpacity = 1
                        }
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
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 10)
            .shadow(color: .black.opacity(0.15), radius: 60, x: 0, y: 20)
        }
        .onAppear {
            if !showIntro {
                contentOpacity = 1
            } else {
                // Start glow animation
                withAnimation(.easeIn(duration: 0.5)) {
                    glowOpacity = 0.6
                }
                // Continuous rotation animation
                withAnimation(.linear(duration: 4).repeatForever(autoreverses: false)) {
                    glowPhase = 1
                }
            }
        }
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
            Image(systemName: "xmark")
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
                VStack(spacing: 8) {
                    ForEach(Array(manager.checks.enumerated()), id: \.element.id) { index, check in
                        let canNavigate = check.status == .success || index == manager.focusedIndex
                        CheckRowView(
                            check: check,
                            isFocused: index == manager.focusedIndex
                        )
                        .opacity(canNavigate ? 1.0 : 0.6)
                        .onTapGesture {
                            // Only allow navigating to completed checks (going back)
                            // or staying on the current check
                            if canNavigate {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    manager.focusCheck(at: index)
                                }
                            }
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
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            content()
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
            .clipShape(RoundedRectangle(cornerRadius: 14))
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
            HStack(spacing: 8) {
                Image(systemName: buttonIcon)
                    .font(.system(size: 16, weight: .medium))
                Text(buttonText)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isComplete ? Color.accentColor : Color.secondary.opacity(0.2))
            )
            .foregroundColor(isComplete ? .white : .secondary)
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
