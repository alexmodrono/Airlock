import AppKit
import Combine
import CoreImage
import QuartzCore

/// The original SwiftUI rainbow rim, rendered behind the solid content window.
/// The separate window that hosts this view ignores every mouse event.
@MainActor
final class AirlockGlowView: NSView {
    static let margin: CGFloat = 80
    private let halo = CALayer()
    private let gradient = CAGradientLayer()
    private let colorField = CALayer()
    private let shape = CAShapeLayer()
    private var observation: AnyCancellable?
    private var introIsPlaying = false
    private let reduceMotion: () -> Bool

    override convenience init(frame: NSRect) {
        self.init(frame: frame, reduceMotion: { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion })
    }

    init(frame: NSRect, reduceMotion: @escaping () -> Bool) {
        self.reduceMotion = reduceMotion
        super.init(frame: frame)
        wantsLayer = true
        halo.opacity = 0
        colorField.mask = shape
        if let blur = CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 30]) {
            halo.filters = [blur]
        }
        gradient.type = .conic
        gradient.startPoint = CGPoint(x: 0.5, y: 0.5)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        // Keep the palette from StartupAnimationView.defaultGlowColors.
        gradient.colors = [
            NSColor(srgbRed: 0.4, green: 0.6, blue: 1, alpha: 1).cgColor,
            NSColor(srgbRed: 0.6, green: 0.4, blue: 1, alpha: 1).cgColor,
            NSColor(srgbRed: 1, green: 0.4, blue: 0.6, alpha: 1).cgColor,
            NSColor(srgbRed: 1, green: 0.6, blue: 0.4, alpha: 1).cgColor,
            NSColor(srgbRed: 0.4, green: 1, blue: 0.6, alpha: 1).cgColor,
            NSColor(srgbRed: 0.4, green: 0.8, blue: 1, alpha: 1).cgColor,
            NSColor(srgbRed: 0.4, green: 0.6, blue: 1, alpha: 1).cgColor
        ]
        colorField.addSublayer(gradient)
        halo.addSublayer(colorField)
        layer?.addSublayer(halo)
        observation = NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        ).sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateMotion()
                if !self.introIsPlaying, self.reduceMotion() {
                    self.setOpacity(0, animated: false)
                }
            }
        }
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.frame = bounds
        colorField.frame = bounds
        shape.frame = bounds
        let card = bounds.insetBy(dx: Self.margin - 17, dy: Self.margin - 17)
        shape.path = CGPath(roundedRect: card, cornerWidth: 32, cornerHeight: 32, transform: nil)
        // Rotate the color field under a stationary rounded mask, not the card.
        let side = hypot(bounds.width, bounds.height)
        gradient.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        gradient.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func setIntroPlaying(_ playing: Bool, animated: Bool = true) {
        guard playing != introIsPlaying || !animated else { return }
        introIsPlaying = playing
        updateMotion()
        setOpacity(playing ? 0.5 : 0, animated: !playing && animated && !reduceMotion())
    }

    private func setOpacity(_ opacity: Float, animated: Bool) {
        let previous = halo.presentation()?.opacity ?? halo.opacity
        halo.removeAnimation(forKey: "introFade")
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        halo.opacity = opacity
        CATransaction.commit()
        guard animated, previous != opacity else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = previous
        fade.toValue = opacity
        fade.duration = 0.5
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        halo.add(fade, forKey: "introFade")
    }

    private func updateMotion() {
        // Freeze at the current angle when the intro ends or Reduce Motion turns on.
        if let rotation = gradient.presentation()?.value(forKeyPath: "transform.rotation.z") as? CGFloat {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            gradient.setValue(rotation, forKeyPath: "transform.rotation.z")
            CATransaction.commit()
        }
        gradient.removeAnimation(forKey: "introRotation")
        guard introIsPlaying, !reduceMotion() else { return }
        let rotation = CABasicAnimation(keyPath: "transform.rotation.z")
        let start = (gradient.value(forKeyPath: "transform.rotation.z") as? CGFloat) ?? 0
        rotation.fromValue = start
        rotation.toValue = start + .pi * 2
        rotation.duration = 9
        rotation.timingFunction = CAMediaTimingFunction(name: .linear)
        rotation.repeatCount = .infinity
        gradient.add(rotation, forKey: "introRotation")
    }
}
