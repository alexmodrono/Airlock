import AppKit
import AirlockCore

@MainActor
private final class AirlockWindow: NSWindow {
    var selectStep: ((Int) -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func performClose(_ sender: Any?) { close() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, event.charactersIgnoringModifiers == "w" {
            if attachedSheet == nil { performClose(nil) }
            return true
        }
        if modifiers == [.command, .option], let key = event.charactersIgnoringModifiers,
           let number = Int(key), (1...9).contains(number) {
            selectStep?(number - 1)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        var frame = super.constrainFrameRect(frameRect, to: screen)
        if let screen {
            frame.origin.y = min(frame.origin.y, screen.visibleFrame.maxY - 72 - frame.height)
        }
        return frame
    }
}

/// Solid setup content with an attached glass navigation window. Both stay at normal
/// window level and never hide, move, or terminate another application.
@MainActor
public final class AirlockWindowController: NSWindowController, NSWindowDelegate {
    public let navigator: AirlockNavigator
    private let flow: AirlockFlowController
    private let navigation: AirlockNavigationController
    private let navigationWindow: NSPanel
    private let glowWindow: NSWindow
    private let glow = AirlockGlowView(frame: .zero)
    private var introIsPlaying: Bool
    private var isPositioning = false
    private var wasClosed = false
    public var onClose: (@MainActor () -> Void)?

    public init(navigator: AirlockNavigator, playsIntro: Bool = true, playsSound: Bool = true, autosavesFrame: Bool = true) {
        self.navigator = navigator
        introIsPlaying = playsIntro
        glowWindow = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        flow = AirlockFlowController(navigator: navigator, playsIntro: playsIntro, playsSound: playsSound)
        navigation = AirlockNavigationController(navigator: navigator, navigationEnabled: !playsIntro)
        navigationWindow = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                   backing: .buffered, defer: false)
        let window = AirlockWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
                                   styleMask: [.borderless, .resizable], backing: .buffered, defer: false)
        window.title = "Set Up \(navigator.appName)"
        window.minSize = NSSize(width: 500, height: 480)
        window.isMovableByWindowBackground = true
        window.contentViewController = flow
        window.setContentSize(NSSize(width: 560, height: 500))
        window.isReleasedWhenClosed = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        if autosavesFrame { window.setFrameAutosaveName("Airlock.\(navigator.appName).compact") }
        glowWindow.title = "Airlock glow"
        glowWindow.contentView = glow
        glowWindow.isReleasedWhenClosed = false
        glowWindow.isOpaque = false
        glowWindow.backgroundColor = .clear
        glowWindow.hasShadow = false
        glowWindow.ignoresMouseEvents = true
        glowWindow.isExcludedFromWindowsMenu = true
        glowWindow.setAccessibilityElement(false)
        glowWindow.level = .normal
        navigationWindow.title = "\(navigator.appName) setup steps"
        navigationWindow.contentViewController = navigation
        navigationWindow.isReleasedWhenClosed = false
        navigationWindow.isOpaque = false
        navigationWindow.backgroundColor = .clear
        navigationWindow.hasShadow = true
        navigationWindow.hidesOnDeactivate = false
        navigationWindow.becomesKeyOnlyIfNeeded = true
        navigationWindow.isMovable = false
        navigationWindow.level = .normal
        super.init(window: window)
        window.delegate = self
        flow.onIntroFinished = { [weak self] in
            self?.navigation.navigationEnabled = true
            self?.introIsPlaying = false
            self?.glow.setIntroPlaying(false)
        }
        window.selectStep = { [weak self] index in
            guard let self, self.navigation.navigationEnabled else { return }
            self.navigator.goTo(index: index)
        }
        navigation.onSelection = { [weak window] in
            NSApp.activate()
            window?.makeKeyAndOrderFront(nil)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public func present() {
        guard let window else { return }
        if !window.isVisible, let screen = window.screen ?? NSScreen.main {
            window.setFrame(Self.centeredContentFrame(size: window.frame.size, screen: screen.frame,
                                                       visibleScreen: screen.visibleFrame), display: false)
        }
        showWindow(nil)
        if glowWindow.parent == nil { window.addChildWindow(glowWindow, ordered: .below) }
        glow.setIntroPlaying(introIsPlaying)
        if wasClosed { flow.resume(); wasClosed = false }
        if navigationWindow.parent == nil { window.addChildWindow(navigationWindow, ordered: .above) }
        positionNavigation()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    public func windowDidMove(_ notification: Notification) { positionNavigation() }
    public func windowDidResize(_ notification: Notification) { positionNavigation() }
    public func windowDidChangeScreen(_ notification: Notification) { positionNavigation() }

    private func positionNavigation() {
        guard let window, !isPositioning else { return }
        isPositioning = true
        defer { isPositioning = false }
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let frame = Self.contentFrame(window.frame, in: screen)
        if frame != window.frame { window.setFrame(frame, display: true) }
        glowWindow.setFrame(window.frame.insetBy(dx: -AirlockGlowView.margin, dy: -AirlockGlowView.margin), display: true)
        navigationWindow.setFrame(Self.navigationFrame(above: window.frame, width: navigation.preferredWidth,
                                                       screen: screen), display: true)
    }

    /// NSWindow.center() is intentionally above center; use the screen midpoint.
    /// Clamp only when a small screen cannot fit the content and navigation there.
    static func centeredContentFrame(size: NSSize, screen: NSRect, visibleScreen: NSRect) -> NSRect {
        let centered = NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                              width: size.width, height: size.height)
        return contentFrame(centered, in: visibleScreen)
    }

    static func contentFrame(_ frame: NSRect, in screen: NSRect) -> NSRect {
        let width = min(frame.width, max(0, screen.width - 24))
        let height = min(frame.height, max(0, screen.height - 84))
        let x = max(screen.minX + 12, min(frame.minX, screen.maxX - width - 12))
        let y = max(screen.minY + 12, min(frame.minY, screen.maxY - height - 72))
        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func navigationFrame(above frame: NSRect, width: CGFloat, screen: NSRect) -> NSRect {
        let width = min(width, max(0, screen.width - 24))
        let x = max(screen.minX + 12, min(frame.midX - width / 2, screen.maxX - width - 12))
        let y = max(screen.minY + 12, min(frame.maxY + 12, screen.maxY - 60))
        return NSRect(x: x, y: y, width: width, height: 48)
    }

    public func windowWillClose(_ notification: Notification) {
        wasClosed = true
        navigator.cancelPendingAction()
        flow.cancelPendingWork()
        window?.removeChildWindow(navigationWindow)
        navigationWindow.orderOut(nil)
        window?.removeChildWindow(glowWindow)
        glowWindow.orderOut(nil)
        glow.setIntroPlaying(false, animated: false)
        onClose?()
    }
}
