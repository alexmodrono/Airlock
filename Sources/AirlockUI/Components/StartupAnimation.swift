// StartupAnimation.swift
// AirlockUI
//
// Reusable startup animation component with sound and glow effects.

import SwiftUI
import AppKit

// MARK: - Startup Animation View

/// A reusable startup animation that displays a Lottie animation with sound and glow effects.
///
/// Use this component to create a consistent startup experience across apps.
///
/// Example:
/// ```swift
/// StartupAnimationView(
///     glowColors: [.blue, .purple, .pink],
///     onComplete: {
///         // Transition to main content
///     }
/// )
/// ```
public struct StartupAnimationView: View {
    let glowColors: [Color]
    let glowDuration: Double
    let onComplete: (() -> Void)?

    @State private var glowPhase: CGFloat = 0
    @State private var glowOpacity: Double = 0
    @State private var animationOpacity: Double = 1

    @Environment(\.colorScheme) private var colorScheme

    /// Creates a startup animation view.
    /// - Parameters:
    ///   - glowColors: Colors for the rotating glow effect (default: rainbow)
    ///   - glowDuration: Duration of one full glow rotation in seconds (default: 4.0)
    ///   - onComplete: Callback when the animation finishes
    public init(
        glowColors: [Color]? = nil,
        glowDuration: Double = 4.0,
        onComplete: (() -> Void)? = nil
    ) {
        self.glowColors = glowColors ?? Self.defaultGlowColors
        self.glowDuration = glowDuration
        self.onComplete = onComplete
    }

    /// Default glow colors (rainbow effect)
    public static let defaultGlowColors: [Color] = [
        Color(red: 0.4, green: 0.6, blue: 1.0),   // Blue
        Color(red: 0.6, green: 0.4, blue: 1.0),   // Purple
        Color(red: 1.0, green: 0.4, blue: 0.6),   // Pink
        Color(red: 1.0, green: 0.6, blue: 0.4),   // Orange
        Color(red: 0.4, green: 1.0, blue: 0.6),   // Green
        Color(red: 0.4, green: 0.8, blue: 1.0),   // Cyan
        Color(red: 0.4, green: 0.6, blue: 1.0),   // Back to Blue
    ]

    public var body: some View {
        ZStack {
            // Animated glow
            AnimatedGlowEffect(phase: glowPhase, colors: glowColors)
                .blur(radius: 40)
                .opacity(glowOpacity)

            // Lottie animation
            HelloAnimationView {
                handleAnimationComplete()
            }
            .opacity(animationOpacity)
        }
        .onAppear {
            playStartupSound()
            startGlowAnimation()
        }
    }

    private func startGlowAnimation() {
        // Fade in glow
        withAnimation(.easeIn(duration: 0.5)) {
            glowOpacity = 0.6
        }
        // Continuous rotation
        withAnimation(.linear(duration: glowDuration).repeatForever(autoreverses: false)) {
            glowPhase = 1
        }
    }

    private func handleAnimationComplete() {
        // Fade out glow
        withAnimation(.easeOut(duration: 0.5)) {
            glowOpacity = 0
        }
        // Fade out animation
        withAnimation(.easeOut(duration: 0.3)) {
            animationOpacity = 0
        }
        // Call completion after fade
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            onComplete?()
        }
    }

    private func playStartupSound() {
        if let soundURL = Bundle.module.url(forResource: "startup", withExtension: "wav") {
            if let sound = NSSound(contentsOf: soundURL, byReference: true) {
                sound.play()
            }
        }
    }
}

// MARK: - Animated Glow Effect

/// A view that displays an animated angular gradient glow.
public struct AnimatedGlowEffect: View {
    let phase: CGFloat
    let colors: [Color]
    let cornerRadius: CGFloat

    /// Creates an animated glow effect.
    /// - Parameters:
    ///   - phase: Animation phase from 0 to 1 (controls rotation)
    ///   - colors: Colors for the gradient
    ///   - cornerRadius: Corner radius of the glow shape (default: 30)
    public init(phase: CGFloat, colors: [Color], cornerRadius: CGFloat = 30) {
        self.phase = phase
        self.colors = colors
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        AngularGradient(
            gradient: Gradient(colors: colors),
            center: .center,
            angle: .degrees(phase * 360)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

// MARK: - Startup Card View

/// A card view with startup animation, sound, and glow effects.
///
/// This provides a complete startup experience in a card format,
/// perfect for splash screens or intro sequences.
///
/// Example:
/// ```swift
/// StartupCardView(
///     width: 600,
///     height: 400,
///     onComplete: {
///         // Show main content
///     }
/// )
/// ```
public struct StartupCardView: View {
    let width: CGFloat
    let height: CGFloat
    let glowColors: [Color]
    let glowDuration: Double
    let onComplete: (() -> Void)?

    @State private var glowPhase: CGFloat = 0
    @State private var glowOpacity: Double = 0
    @State private var cardScale: CGFloat = 0.95
    @State private var cardOpacity: Double = 0
    @State private var animationComplete = false

    @Environment(\.colorScheme) private var colorScheme

    /// Creates a startup card view.
    /// - Parameters:
    ///   - width: Card width (default: 820)
    ///   - height: Card height (default: 580)
    ///   - glowColors: Colors for the glow effect
    ///   - glowDuration: Duration of glow rotation (default: 4.0)
    ///   - onComplete: Callback when startup finishes
    public init(
        width: CGFloat = 820,
        height: CGFloat = 580,
        glowColors: [Color]? = nil,
        glowDuration: Double = 4.0,
        onComplete: (() -> Void)? = nil
    ) {
        self.width = width
        self.height = height
        self.glowColors = glowColors ?? StartupAnimationView.defaultGlowColors
        self.glowDuration = glowDuration
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            // Animated glow behind card
            if !animationComplete {
                AnimatedGlowEffect(phase: glowPhase, colors: glowColors)
                    .frame(width: width + 40, height: height + 40)
                    .blur(radius: 40)
                    .opacity(glowOpacity)
            }

            // Card
            ZStack {
                // Solid backing
                RoundedRectangle(cornerRadius: 20)
                    .fill(colorScheme == .dark ? Color.black : Color.white)

                // Material
                RoundedRectangle(cornerRadius: 20)
                    .fill(.ultraThinMaterial)

                // Gradient overlay
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

                // Animation content
                if !animationComplete {
                    HelloAnimationView {
                        handleAnimationComplete()
                    }
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.3), radius: 30, x: 0, y: 10)
            .shadow(color: .black.opacity(0.15), radius: 60, x: 0, y: 20)
            .scaleEffect(cardScale)
            .opacity(cardOpacity)
        }
        .onAppear {
            playStartupSound()
            startAnimations()
        }
    }

    private func startAnimations() {
        // Card entrance
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(0.1)) {
            cardScale = 1.0
            cardOpacity = 1
        }

        // Glow fade in
        withAnimation(.easeIn(duration: 0.5).delay(0.2)) {
            glowOpacity = 0.6
        }

        // Glow rotation
        withAnimation(.linear(duration: glowDuration).repeatForever(autoreverses: false)) {
            glowPhase = 1
        }
    }

    private func handleAnimationComplete() {
        // Fade out glow
        withAnimation(.easeOut(duration: 0.5)) {
            glowOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            animationComplete = true
            onComplete?()
        }
    }

    private func playStartupSound() {
        if let soundURL = Bundle.module.url(forResource: "startup", withExtension: "wav") {
            if let sound = NSSound(contentsOf: soundURL, byReference: true) {
                sound.play()
            }
        }
    }
}

// MARK: - Fullscreen Startup View

/// A fullscreen startup view with blurred background, card, animation, sound, and glow.
///
/// This provides the complete Airlock startup experience as a standalone component.
///
/// Example:
/// ```swift
/// FullscreenStartupView(
///     onComplete: {
///         // Dismiss and show main app
///     }
/// )
/// ```
public struct FullscreenStartupView: View {
    let cardWidth: CGFloat
    let cardHeight: CGFloat
    let glowColors: [Color]
    let onComplete: (() -> Void)?

    @State private var overlayOpacity: Double = 0
    @State private var showCard = true

    @Environment(\.colorScheme) private var colorScheme

    /// Creates a fullscreen startup view.
    /// - Parameters:
    ///   - cardWidth: Width of the startup card (default: 820)
    ///   - cardHeight: Height of the startup card (default: 580)
    ///   - glowColors: Colors for the glow effect
    ///   - onComplete: Callback when startup finishes
    public init(
        cardWidth: CGFloat = 820,
        cardHeight: CGFloat = 580,
        glowColors: [Color]? = nil,
        onComplete: (() -> Void)? = nil
    ) {
        self.cardWidth = cardWidth
        self.cardHeight = cardHeight
        self.glowColors = glowColors ?? StartupAnimationView.defaultGlowColors
        self.onComplete = onComplete
    }

    public var body: some View {
        ZStack {
            // Blurred background overlay
            VisualEffectBlur(material: .fullScreenUI, blendingMode: .behindWindow)
                .ignoresSafeArea()
                .overlay(
                    Color.black.opacity(colorScheme == .dark ? 0.5 : 0.3)
                )
                .opacity(overlayOpacity)

            // Startup card
            if showCard {
                StartupCardView(
                    width: cardWidth,
                    height: cardHeight,
                    glowColors: glowColors
                ) {
                    handleComplete()
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
                overlayOpacity = 1
            }
        }
    }

    private func handleComplete() {
        withAnimation(.easeOut(duration: 0.3)) {
            overlayOpacity = 0
            showCard = false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            onComplete?()
        }
    }
}

// MARK: - Preview

#if DEBUG
struct StartupAnimation_Previews: PreviewProvider {
    static var previews: some View {
        StartupCardView()
            .frame(width: 900, height: 700)
            .background(Color.black.opacity(0.5))
    }
}
#endif
