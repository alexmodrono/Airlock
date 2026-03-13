// HelloAnimation.swift
// AirlockUI
//
// Lottie-based "hello" animation for the intro sequence.

import SwiftUI
import Combine
import Lottie
import AppKit

// MARK: - Module Bundle Helper

/// Helper to access the module bundle
private let airlockUIBundle: Bundle = .module

// MARK: - Animation Controller

/// Controller for managing the hello animation state
@MainActor
public final class HelloAnimationController: ObservableObject {
    @Published var shouldSkip: Bool = false

    public init() {}

    /// Signals the animation to skip/accelerate
    public func skip() {
        shouldSkip = true
    }
}

// MARK: - Lottie View

/// A SwiftUI view that displays a Lottie animation from a dotLottie file.
struct DotLottieAnimationView: NSViewRepresentable {
    let fileName: String
    let loopMode: LottieLoopMode
    let animationSpeed: CGFloat
    let colorScheme: ColorScheme
    var onComplete: (() -> Void)?
    @ObservedObject var controller: HelloAnimationController

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        context.coordinator.setupAnimation(in: containerView, colorScheme: colorScheme)
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Check if we should skip
        if controller.shouldSkip {
            context.coordinator.accelerateToEnd()
        }
        // Update color if color scheme changed
        context.coordinator.updateColor(for: colorScheme)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            fileName: fileName,
            loopMode: loopMode,
            animationSpeed: animationSpeed,
            onComplete: onComplete
        )
    }

    class Coordinator {
        let fileName: String
        let loopMode: LottieLoopMode
        let animationSpeed: CGFloat
        var onComplete: (() -> Void)?
        private var animationView: Lottie.LottieAnimationView?
        private var hasCalledComplete = false
        private var currentColorScheme: ColorScheme?

        init(fileName: String, loopMode: LottieLoopMode, animationSpeed: CGFloat, onComplete: (() -> Void)?) {
            self.fileName = fileName
            self.loopMode = loopMode
            self.animationSpeed = animationSpeed
            self.onComplete = onComplete
        }

        func setupAnimation(in containerView: NSView, colorScheme: ColorScheme) {
            self.currentColorScheme = colorScheme

            // Try to load dotLottie file
            guard let url = airlockUIBundle.url(forResource: fileName, withExtension: "lottie") else {
                print("Could not find \(fileName).lottie in bundle")
                return
            }

            DotLottieFile.loadedFrom(url: url) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self = self else { return }

                    switch result {
                    case .success(let dotLottie):
                        let lottieView = Lottie.LottieAnimationView(dotLottie: dotLottie)
                        self.configureAndAdd(lottieView, to: containerView, colorScheme: colorScheme)

                    case .failure(let error):
                        print("Failed to load dotLottie: \(error)")
                        // Try fallback to JSON
                        if let animation = LottieAnimation.named(self.fileName, bundle: airlockUIBundle) {
                            let lottieView = Lottie.LottieAnimationView(animation: animation)
                            self.configureAndAdd(lottieView, to: containerView, colorScheme: colorScheme)
                        }
                    }
                }
            }
        }

        private func configureAndAdd(_ lottieView: Lottie.LottieAnimationView, to containerView: NSView, colorScheme: ColorScheme) {
            lottieView.loopMode = loopMode
            lottieView.animationSpeed = animationSpeed
            lottieView.contentMode = .scaleAspectFit
            lottieView.translatesAutoresizingMaskIntoConstraints = false

            // Apply color based on color scheme
            applyColor(to: lottieView, colorScheme: colorScheme)

            // Remove any existing subviews
            containerView.subviews.forEach { $0.removeFromSuperview() }

            containerView.addSubview(lottieView)

            NSLayoutConstraint.activate([
                lottieView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
                lottieView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
                lottieView.topAnchor.constraint(equalTo: containerView.topAnchor),
                lottieView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
            ])

            self.animationView = lottieView

            // Play animation
            lottieView.play { [weak self] completed in
                self?.callComplete()
            }
        }

        private func applyColor(to lottieView: Lottie.LottieAnimationView, colorScheme: ColorScheme) {
            // White in dark mode, black in light mode
            let color: LottieColor = colorScheme == .dark
                ? LottieColor(r: 1, g: 1, b: 1, a: 1)  // White
                : LottieColor(r: 0, g: 0, b: 0, a: 1)  // Black

            let colorValueProvider = ColorValueProvider(color)

            // Apply to regular stroke/fill colors
            let colorKeypaths = [
                "**.Stroke 1.Color",
                "**.Stroke.Color",
                "**.Fill 1.Color",
                "**.Fill.Color",
                "**.Color"
            ]
            for keypath in colorKeypaths {
                lottieView.setValueProvider(colorValueProvider, keypath: AnimationKeypath(keypath: keypath))
            }

            // The hello animation uses a Gradient Stroke with 17 color stops
            // Create a gradient with the same number of stops matching the color scheme
            let gradientColors: [LottieColor] = Array(repeating: color, count: 17)
            let gradientValueProvider = GradientValueProvider(gradientColors)

            // Apply to gradient stroke colors
            let gradientKeypaths = [
                "**.Gradient Stroke 1.Colors",
                "**.Gradient Fill 1.Colors",
                "**.Colors"
            ]
            for keypath in gradientKeypaths {
                lottieView.setValueProvider(gradientValueProvider, keypath: AnimationKeypath(keypath: keypath))
            }
        }

        func updateColor(for colorScheme: ColorScheme) {
            guard let animationView = animationView, colorScheme != currentColorScheme else { return }
            currentColorScheme = colorScheme
            applyColor(to: animationView, colorScheme: colorScheme)
        }

        func accelerateToEnd() {
            guard let animationView = animationView, !hasCalledComplete else { return }

            // Accelerate animation speed significantly
            animationView.animationSpeed = 8.0

            // Also schedule completion in case acceleration doesn't trigger callback
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.callComplete()
            }
        }

        private func callComplete() {
            guard !hasCalledComplete else { return }
            hasCalledComplete = true
            onComplete?()
        }
    }
}

// MARK: - Hello Animation View

/// Displays the "hello" Lottie animation.
public struct HelloAnimationView: View {
    let onComplete: (() -> Void)?
    @ObservedObject var controller: HelloAnimationController
    @Environment(\.colorScheme) private var colorScheme

    @State private var opacity: Double = 1.0

    public init(
        controller: HelloAnimationController? = nil,
        duration: Double = 2.5,
        onComplete: (() -> Void)? = nil
    ) {
        // Duration is controlled by the Lottie file itself
        self.controller = controller ?? HelloAnimationController()
        self.onComplete = onComplete
    }

    public var body: some View {
        DotLottieAnimationView(
            fileName: "hello",
            loopMode: .playOnce,
            animationSpeed: 1.0,
            colorScheme: colorScheme,
            onComplete: {
                // Fade out after animation completes
                withAnimation(.easeOut(duration: 0.3)) {
                    opacity = 0
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    onComplete?()
                }
            },
            controller: controller
        )
        .opacity(opacity)
    }
}

// MARK: - Intro Animation View

/// A full-screen intro animation that shows "hello" and transitions to the main content.
public struct IntroAnimationView: View {
    @Binding var isComplete: Bool

    let animationDuration: Double

    @State private var showHello = true

    public init(isComplete: Binding<Bool>, animationDuration: Double = 3.0) {
        self._isComplete = isComplete
        self.animationDuration = animationDuration
    }

    public var body: some View {
        ZStack {
            if showHello {
                HelloAnimationView(duration: animationDuration) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showHello = false
                        isComplete = true
                    }
                }
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

#if DEBUG
struct HelloAnimation_Previews: PreviewProvider {
    static var previews: some View {
        HelloAnimationView()
            .frame(width: 400, height: 300)
            .background(Color.black)
    }
}
#endif
