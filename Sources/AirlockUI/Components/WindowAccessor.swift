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
/// Configures the window to be fullscreen with a transparent background,
/// allowing the Airlock overlay to cover the entire screen.
/// System Settings is allowed to appear above the overlay so users can grant permissions.
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
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        // Configuration is handled by the WindowObservingView
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public class Coordinator: NSObject {
        private weak var managedWindow: NSWindow?
        private var observers: [NSObjectProtocol] = []
        private var isSystemSettingsActive = false
        private var configurationCount = 0
        private var frameObservation: NSKeyValueObservation?
        private var lastFrameCorrectionTime: Date = .distantPast

        /// Window level high enough to cover the menu bar but below screen saver.
        /// .mainMenu (level 24) is just above the menu bar.
        private static let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)

        override init() {
            super.init()
            setupAppActivationObservers()
        }

        deinit {
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            frameObservation?.invalidate()
        }

        func configure(window: NSWindow) {
            managedWindow = window
            configurationCount += 1
            let isFirstConfiguration = configurationCount == 1

            // Make window borderless and transparent
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask = [.borderless, .fullSizeContentView]

            // Remove standard window controls
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true

            // Disable shadow on the window itself (we'll draw our own)
            window.hasShadow = false

            // Float above other windows including menu bar (but will lower for System Settings)
            if !isSystemSettingsActive {
                window.level = Self.overlayLevel
            }
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

            // Set fullscreen frame
            updateWindowFrame(window)

            // Make key and bring to front on first configuration
            if isFirstConfiguration {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)

                // Observe frame changes to fight against SwiftUI's window resizing
                setupFrameObserver(for: window)

                // Re-apply frame multiple times during initialization to fight SwiftUI layout
                for delay in [0.02, 0.05, 0.1, 0.2] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                        self?.updateWindowFrame(window)
                    }
                }
            }
        }

        private func setupFrameObserver(for window: NSWindow) {
            // Observe window frame changes and snap back to fullscreen.
            // This fights against SwiftUI's .windowResizability(.contentSize).
            // We use a debounce to avoid infinite loops.
            frameObservation = window.observe(\.frame, options: [.new]) { [weak self] window, _ in
                guard let self = self else { return }
                guard let screen = window.screen ?? NSScreen.main else { return }

                // Only correct if frame doesn't match screen
                guard window.frame != screen.frame else { return }

                // Debounce: don't correct more than once per 10ms to avoid loops
                let now = Date()
                guard now.timeIntervalSince(self.lastFrameCorrectionTime) > 0.01 else { return }

                self.lastFrameCorrectionTime = now
                self.updateWindowFrame(window)
            }
        }

        private func updateWindowFrame(_ window: NSWindow) {
            guard let screen = window.screen ?? NSScreen.main else { return }
            guard window.frame != screen.frame else { return }
            window.setFrame(screen.frame, display: true, animate: false)
        }

        private func setupAppActivationObservers() {
            // Observe when any app becomes active
            let activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                self?.handleAppActivation(notification)
            }
            observers.append(activationObserver)

            // Observe when our app becomes active again
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
                  let bundleID = app.bundleIdentifier else {
                return
            }

            if allowedOverlayApps.contains(bundleID) {
                isSystemSettingsActive = true
                lowerWindowLevel()
            } else {
                isSystemSettingsActive = false
            }
        }

        private func lowerWindowLevel() {
            guard let window = managedWindow else { return }
            window.level = .normal
        }

        private func restoreWindowLevel() {
            guard let window = managedWindow else { return }
            isSystemSettingsActive = false
            window.level = Self.overlayLevel
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Window Observing View

/// A custom NSView that observes when it's attached to a window and notifies via callback.
/// This is more reliable than using DispatchQueue.main.async.
private class WindowObservingView: NSView {
    var onWindowAttached: ((NSWindow) -> Void)?
    private var hasNotified = false
    private var retryCount = 0
    private let maxRetries = 10

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        tryConfigureWindow()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        // Also try when moving to superview as window might be available then
        tryConfigureWindow()
    }

    private func tryConfigureWindow() {
        if let window = self.window, !hasNotified {
            hasNotified = true
            onWindowAttached?(window)
        } else if self.window == nil && !hasNotified && retryCount < maxRetries {
            // Window not ready yet, retry after a short delay
            retryCount += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.tryConfigureWindow()
            }
        }
    }
}
