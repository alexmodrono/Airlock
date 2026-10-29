import AppKit
import Combine

/// One native material per window, with an opaque accessibility fallback.
@MainActor
final class AirlockGlassSurface: NSView {
    let content = NSView()
    private let radius: CGFloat
    private let interactive: Bool
    private var material: NSView?
    private var observation: AnyCancellable?

    init(radius: CGFloat, interactive: Bool = false) {
        self.radius = radius
        self.interactive = interactive
        super.init(frame: .zero)
        rebuildMaterial()
        observation = NSWorkspace.shared.notificationCenter.publisher(
            for: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification
        ).sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.rebuildMaterial() }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            effectiveAppearance.performAsCurrentDrawingAppearance {
                material?.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
        }
    }

    override var mouseDownCanMoveWindow: Bool { true }

    private func rebuildMaterial() {
        content.removeFromSuperview()
        material?.removeFromSuperview()
        let surface: NSView
        if NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let opaque = NSView()
            opaque.wantsLayer = true
            opaque.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            opaque.layer?.cornerRadius = radius
            surface = opaque
            surface.addSubview(content)
        } else if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = radius
            // Swift 6.2/6.3 SDKs do not declare this macOS 27 enhancement.
            #if compiler(>=6.4)
            if #available(macOS 27.0, *) { glass.effectIsInteractive = interactive }
            #endif
            glass.contentView = content
            surface = glass
        } else {
            let visual = NSVisualEffectView()
            visual.material = .hudWindow
            visual.blendingMode = .behindWindow
            visual.state = .followsWindowActiveState
            visual.wantsLayer = true
            visual.layer?.cornerRadius = radius
            visual.layer?.masksToBounds = true
            visual.addSubview(content)
            surface = visual
        }
        material = surface
        addSubview(surface)
        surface.frame = bounds
        surface.autoresizingMask = [.width, .height]
        content.frame = surface.bounds
        content.autoresizingMask = [.width, .height]
    }
}
