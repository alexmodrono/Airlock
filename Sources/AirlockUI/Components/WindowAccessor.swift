// WindowAccessor.swift
// AirlockUI

import SwiftUI
import AppKit

/// Bundle identifiers for apps that should be allowed to appear above the onboarding overlay.
private let allowedOverlayApps: Set<String> = [
    "com.apple.systempreferences",      // System Settings (macOS 13+)
    "com.apple.SystemPreferences",      // System Preferences (older macOS)
    "com.apple.Accessibility-Settings"  // Accessibility Settings panel
]

/// A view that provides access to the underlying NSWindow for customization.
///
/// Creates a **separate** borderless overlay window and moves the host window's
/// content into it.  The overlay is created borderless from birth — no
/// style-mask transition ever occurs, so NSHostingView's KVO observers are
/// never disrupted.
///
/// When ``isImmersive`` is `true` (the default), the overlay covers the entire
/// screen above the menu bar — the original Airlock behavior.  When set to
/// `false`, the overlay shrinks to ``cardSize`` (plus shadow padding), drops
/// to a normal window level, and behaves like a regular app window so users
/// can Cmd-Tab, access the menu bar, and interact with other apps.
///
/// When the view is removed from the hierarchy, the content is moved back to
/// the original window and the overlay is closed.
///
/// Use this in custom intro views to ensure proper window configuration:
/// ```swift
/// MyCustomIntroView()
///     .background(WindowAccessor())
/// ```
public struct WindowAccessor: NSViewRepresentable {
    var isImmersive: Bool
    var cardSize: CGSize

    /// Extra padding around the card to ensure shadows render without clipping.
    private static let shadowPadding: CGFloat = 120

    public init(isImmersive: Bool = true, cardSize: CGSize = CGSize(width: 820, height: 580)) {
        self.isImmersive = isImmersive
        self.cardSize = cardSize
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowObservingView()
        view.onWindowAttached = { window in
            context.coordinator.configure(window: window)
        }
        view.onWindowDetached = {
            context.coordinator.restoreWindow()
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.update(isImmersive: isImmersive, cardSize: cardSize)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    public class Coordinator: NSObject {
        private var overlayWindow: AirlockOverlayWindow?
        private weak var hostWindow: NSWindow?
        private var hostContentView: NSView?
        private var observers: [NSObjectProtocol] = []
        private var isSystemSettingsActive = false
        private var pendingWork: DispatchWorkItem?

        /// Current immersive state as communicated by the SwiftUI side.
        private var currentlyImmersive = true
        /// Card dimensions used when demoting to non-immersive.
        private var cardSize = CGSize(width: 820, height: 580)

        /// Window level high enough to cover the menu bar but below screen saver.
        private static let overlayLevel = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1
        )

        override init() {
            super.init()
            setupAppActivationObservers()
        }

        deinit {
            pendingWork?.cancel()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            restoreWindowImmediately()
        }

        func configure(window: NSWindow) {
            // If we already have an overlay for this window, don't reconfigure.
            guard overlayWindow == nil else { return }
            hostWindow = window

            // Defer the content-view transfer so SwiftUI has time to finish
            // registering KVO observers on the NSHostingView.  Moving the
            // content view on the very first run-loop iteration after window
            // creation crashes because the observers aren't registered yet.
            pendingWork?.cancel()
            let work = DispatchWorkItem { [weak self, weak window] in
                guard let self, let window, self.hostWindow === window else { return }
                self.transferToOverlay(from: window)
            }
            pendingWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
        }

        /// Called from `updateNSView` whenever the SwiftUI parameters change.
        func update(isImmersive: Bool, cardSize: CGSize) {
            self.cardSize = cardSize

            let wasImmersive = currentlyImmersive
            currentlyImmersive = isImmersive

            guard let overlay = overlayWindow else { return }
            guard wasImmersive != isImmersive else { return }

            if isImmersive {
                promoteToImmersive(overlay)
            } else {
                demoteToWindowed(overlay)
            }
        }

        func restoreWindow() {
            pendingWork?.cancel()
            pendingWork = nil

            guard let overlay = overlayWindow else { return }
            let host = hostWindow
            let content = hostContentView

            overlayWindow = nil
            hostWindow = nil
            hostContentView = nil

            // Move the content view back synchronously so it's in the host
            // window BEFORE SwiftUI tears down the view hierarchy.
            if let host, let content {
                host.contentView = content
                host.makeKeyAndOrderFront(nil)
            }
            overlay.orderOut(nil)
        }

        // MARK: - Overlay Lifecycle

        private func transferToOverlay(from window: NSWindow) {
            guard overlayWindow == nil else { return }
            guard let screen = window.screen ?? NSScreen.main else { return }

            // Grab the content view.  At this point SwiftUI has completed
            // its initial layout and KVO registration, so removing the
            // content view from the host window is safe.
            guard let contentView = window.contentView else { return }
            hostContentView = contentView

            // Detach from the host and hide it.
            window.contentView = nil
            window.orderOut(nil)

            // Create a borderless overlay — born borderless, no transition.
            let overlay = AirlockOverlayWindow(screen: screen)
            overlay.contentView = contentView

            if currentlyImmersive {
                // Fullscreen immersive mode.
                if !isSystemSettingsActive {
                    overlay.level = Self.overlayLevel
                }
                overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            } else {
                // Card-sized windowed mode (intro was already skipped or disabled).
                let frame = windowedFrame(on: screen)
                overlay.setFrame(frame, display: false)
                overlay.level = .normal
                overlay.collectionBehavior = [.fullScreenAuxiliary]
                overlay.hasShadow = true
            }

            overlay.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)

            overlayWindow = overlay
        }

        /// Synchronous restore used from deinit.
        private func restoreWindowImmediately() {
            guard let overlay = overlayWindow,
                  let host = hostWindow,
                  let content = hostContentView else { return }

            overlayWindow = nil
            hostWindow = nil
            hostContentView = nil

            host.contentView = content
            host.makeKeyAndOrderFront(nil)
            overlay.orderOut(nil)
        }

        // MARK: - Immersive ↔ Windowed Transitions

        /// Transition from windowed card to fullscreen overlay.
        private func promoteToImmersive(_ overlay: AirlockOverlayWindow) {
            guard let screen = overlay.screen ?? NSScreen.main else { return }
            overlay.hasShadow = false
            overlay.level = Self.overlayLevel
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.4
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                overlay.animator().setFrame(screen.frame, display: true)
            }
        }

        /// Transition from fullscreen overlay to a normal card-sized window.
        private func demoteToWindowed(_ overlay: AirlockOverlayWindow) {
            guard let screen = overlay.screen ?? NSScreen.main else { return }
            let target = windowedFrame(on: screen)

            // Drop level first so the desktop becomes visible behind the card.
            overlay.level = .normal
            overlay.collectionBehavior = [.fullScreenAuxiliary]

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.5
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                overlay.animator().setFrame(target, display: true)
            } completionHandler: {
                overlay.hasShadow = true
            }
        }

        /// Computes the centered card frame including shadow padding.
        private func windowedFrame(on screen: NSScreen) -> NSRect {
            let padding = WindowAccessor.shadowPadding
            let w = cardSize.width + padding * 2
            let h = cardSize.height + padding * 2
            let x = screen.frame.midX - w / 2
            let y = screen.frame.midY - h / 2
            return NSRect(x: x, y: y, width: w, height: h)
        }

        // MARK: - System Settings Passthrough

        private func setupAppActivationObservers() {
            let activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleAppActivation(notification)
            }
            observers.append(activationObserver)

            let ourAppObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.restoreWindowLevel()
            }
            observers.append(ourAppObserver)
        }

        private func handleAppActivation(_ notification: Notification) {
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleID = app.bundleIdentifier else { return }

            if allowedOverlayApps.contains(bundleID) {
                isSystemSettingsActive = true
                overlayWindow?.level = .normal
            } else {
                isSystemSettingsActive = false
            }
        }

        private func restoreWindowLevel() {
            guard let overlay = overlayWindow else { return }

            // Only re-elevate if we are still in immersive mode.
            guard currentlyImmersive else { return }

            isSystemSettingsActive = false
            overlay.level = Self.overlayLevel

            if let screen = overlay.screen ?? NSScreen.main, overlay.frame != screen.frame {
                overlay.setFrame(screen.frame, display: true, animate: false)
            }
            overlay.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Overlay Window

/// A borderless, transparent, key-capable NSWindow used as the Airlock overlay.
///
/// Created borderless from the start so there is never a titled → borderless
/// style-mask transition.
final class AirlockOverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Window Observing View

/// A custom NSView that observes when it's attached to/detached from a window.
private class WindowObservingView: NSView {
    var onWindowAttached: ((NSWindow) -> Void)?
    var onWindowDetached: (() -> Void)?
    private var hasNotified = false
    private var retryCount = 0
    private let maxRetries = 10

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            tryConfigureWindow()
        } else if hasNotified {
            hasNotified = false
            onWindowDetached?()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        tryConfigureWindow()
    }

    private func tryConfigureWindow() {
        if let window = self.window, !hasNotified {
            hasNotified = true
            onWindowAttached?(window)
        } else if self.window == nil && !hasNotified && retryCount < maxRetries {
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.tryConfigureWindow()
            }
        }
    }
}
