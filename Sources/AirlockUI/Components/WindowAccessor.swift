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
/// Instead of mutating the host window's style mask (which crashes SwiftUI's
/// KVO observers), this view creates a **new** borderless overlay window and
/// reparents the host window's content view into it.  The overlay window is
/// born borderless — no style-mask transition ever happens, so there is no
/// frame-view reconstruction and no crash.
///
/// When the view is removed from the hierarchy the overlay window is closed
/// and the original window is restored.
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
        private var configurationCount = 0
        private var pendingConfigurationWorkItem: DispatchWorkItem?

        /// Window level high enough to cover the menu bar but below screen saver.
        private static let overlayLevel = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1
        )

        override init() {
            super.init()
            setupAppActivationObservers()
        }

        deinit {
            pendingConfigurationWorkItem?.cancel()
            observers.forEach { NotificationCenter.default.removeObserver($0) }
            restoreWindow()
        }

        func configure(window: NSWindow) {
            hostWindow = window
            configurationCount += 1
            let isFirst = configurationCount == 1

            pendingConfigurationWorkItem?.cancel()
            let work = DispatchWorkItem { [weak self, weak window] in
                guard let self, let window else { return }
                self.applyOverlay(to: window, isFirstConfiguration: isFirst)
            }
            pendingConfigurationWorkItem = work
            DispatchQueue.main.async(execute: work)
        }

        func restoreWindow() {
            guard let overlay = overlayWindow else { return }
            let host = hostWindow
            let contentView = hostContentView

            overlayWindow = nil
            hostWindow = nil
            hostContentView = nil

            DispatchQueue.main.async {
                // Move the content view back to the host window.
                if let host, let contentView {
                    host.contentView = contentView
                    host.makeKeyAndOrderFront(nil)
                }

                overlay.orderOut(nil)
            }
        }

        // MARK: - Overlay Setup

        private func applyOverlay(to window: NSWindow, isFirstConfiguration: Bool) {
            guard hostWindow === window else { return }
            guard overlayWindow == nil else { return }

            guard let screen = window.screen ?? NSScreen.main else { return }

            // Steal the content view from the host window.  The content view
            // is an NSHostingView managed by SwiftUI.  Moving it between
            // windows of the SAME style doesn't trigger the KVO crash; the
            // crash only happens when the frame-view class changes (titled ↔
            // borderless).  Here the host is titled and stays titled — we just
            // set its content view to nil.  The hosting view is then placed
            // into a window that was BORN borderless, so there is no
            // frame-view reconstruction.
            let contentView = window.contentView
            hostContentView = contentView
            window.contentView = nil

            // Hide the (now-empty) host window so it doesn't flash behind
            // the overlay.
            window.orderOut(nil)

            // Create a new borderless overlay window.  Because it is
            // borderless from creation, no style-mask transition ever occurs.
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
/// style-mask transition (which would crash NSHostingView's KVO observers).
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

    // Borderless windows return false by default — override so
    // TextFields and other controls can receive focus.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Window Observing View

/// A custom NSView that observes when it's attached to a window and notifies via callback.
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
