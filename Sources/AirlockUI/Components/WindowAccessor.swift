// WindowAccessor.swift
// AirlockUI

import SwiftUI
import AppKit

/// Configures the host window so the Airlock onboarding presents as a clean,
/// borderless-looking card that floats above other windows.
///
/// This adjusts properties on the *existing* window only — it never creates a
/// second window or moves the host's content view, which is what made the old
/// implementation crash-prone. The original window properties are captured when
/// the accessor attaches and restored when it detaches, so the window returns
/// to normal for whatever the app shows after onboarding.
///
/// The card's rounded corners and rainbow come from the SwiftUI content; the
/// window is made transparent so those render cleanly with no opaque rectangle
/// or square border behind them.
///
/// ```swift
/// MyOnboardingRoot()
///     .background(WindowAccessor())
/// ```
public struct WindowAccessor: NSViewRepresentable {
    /// Whether the onboarding window should float above other apps' windows.
    var floats: Bool

    public init(floats: Bool = true) {
        self.floats = floats
    }

    public func makeNSView(context: Context) -> NSView {
        let view = WindowObservingView()
        view.onWindowAttached = { [floats] window in
            context.coordinator.configure(window: window, floats: floats)
        }
        view.onWindowDetached = {
            context.coordinator.restore()
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.updateFloating(floats)
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject {
        private weak var window: NSWindow?
        private var original: WindowState?
        private var floats = true
        private var resizeObserver: NSObjectProtocol?

        deinit {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
        }

        /// The window properties we mutate, captured so we can put them back.
        private struct WindowState {
            let isOpaque: Bool
            let backgroundColor: NSColor
            let hasShadow: Bool
            let level: NSWindow.Level
            let isMovableByWindowBackground: Bool
            let closeHidden: Bool
            let miniaturizeHidden: Bool
            let zoomHidden: Bool
        }

        func configure(window: NSWindow, floats: Bool) {
            guard self.window !== window else {
                updateFloating(floats)
                return
            }
            self.window = window
            self.floats = floats

            original = WindowState(
                isOpaque: window.isOpaque,
                backgroundColor: window.backgroundColor,
                hasShadow: window.hasShadow,
                level: window.level,
                isMovableByWindowBackground: window.isMovableByWindowBackground,
                closeHidden: window.standardWindowButton(.closeButton)?.isHidden ?? false,
                miniaturizeHidden: window.standardWindowButton(.miniaturizeButton)?.isHidden ?? false,
                zoomHidden: window.standardWindowButton(.zoomButton)?.isHidden ?? false
            )

            apply(to: window, floats: floats)
        }

        private func apply(to window: NSWindow, floats: Bool) {
            // Transparent window: the rounded card drawn in SwiftUI shows with
            // clean corners, no opaque rectangle, no square border. The card
            // draws its own shadow, so disable the window's to avoid doubling.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.isMovableByWindowBackground = true
            window.level = floats ? .floating : .normal

            // Hide the traffic-light buttons for an uninterrupted card look.
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

            // Center on screen. The window may still be sizing itself to its
            // content, so re-center on the next resize so it lands dead-center
            // regardless of when the final size is applied.
            centerExactly(window)
            if resizeObserver == nil {
                resizeObserver = NotificationCenter.default.addObserver(
                    forName: NSWindow.didResizeNotification,
                    object: window,
                    queue: .main
                ) { [weak self, weak window] _ in
                    guard let window else { return }
                    self?.centerExactly(window)
                }
            }
        }

        /// Places the window at the exact geometric center of its screen.
        ///
        /// `NSWindow.center()` intentionally sits slightly *above* center, so we
        /// compute the midpoint ourselves.
        private func centerExactly(_ window: NSWindow) {
            guard let screen = window.screen ?? NSScreen.main else {
                window.center()
                return
            }
            let screenFrame = screen.frame
            let size = window.frame.size
            let origin = NSPoint(
                x: screenFrame.midX - size.width / 2,
                y: screenFrame.midY - size.height / 2
            )
            window.setFrameOrigin(origin)
        }

        func updateFloating(_ floats: Bool) {
            self.floats = floats
            window?.level = floats ? .floating : .normal
        }

        func restore() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }

            guard let window, let original else { return }
            window.isOpaque = original.isOpaque
            window.backgroundColor = original.backgroundColor
            window.hasShadow = original.hasShadow
            window.level = original.level
            window.isMovableByWindowBackground = original.isMovableByWindowBackground
            window.standardWindowButton(.closeButton)?.isHidden = original.closeHidden
            window.standardWindowButton(.miniaturizeButton)?.isHidden = original.miniaturizeHidden
            window.standardWindowButton(.zoomButton)?.isHidden = original.zoomHidden

            self.window = nil
            self.original = nil
        }
    }
}

// MARK: - Window Observing View

/// A custom NSView that reports when it's attached to / detached from a window.
private final class WindowObservingView: NSView {
    var onWindowAttached: ((NSWindow) -> Void)?
    var onWindowDetached: (() -> Void)?
    private var attached = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            guard !attached else { return }
            attached = true
            onWindowAttached?(window)
        } else if attached {
            attached = false
            onWindowDetached?()
        }
    }
}
