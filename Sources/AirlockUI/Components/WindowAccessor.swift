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
/// When the view is removed from the hierarchy, the content is moved back to
/// the original window and the overlay is closed.
///
/// Use this in custom intro views to ensure proper window configuration:
/// ```swift
/// MyCustomIntroView()
///     .background(WindowAccessor())
/// ```
public struct WindowAccessor: NSViewRepresentable {
    public init() {}

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

    public func updateNSView(_ nsView: NSView, context: Context) {}

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

            if !isSystemSettingsActive {
                overlay.level = Self.overlayLevel
            }
            overlay.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
