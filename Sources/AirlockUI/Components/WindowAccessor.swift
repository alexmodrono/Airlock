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
/// When the view is removed from the hierarchy, the window is automatically
/// restored to its original state (style mask, level, shadow, etc.).
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
        private var pendingConfigurationWorkItem: DispatchWorkItem?
        private var savedWindowState: SavedWindowState?

        /// Snapshot of the window properties before Airlock modifies them.
        private struct SavedWindowState {
            let styleMask: NSWindow.StyleMask
            let isOpaque: Bool
            let backgroundColor: NSColor
            let titlebarAppearsTransparent: Bool
            let titleVisibility: NSWindow.TitleVisibility
            let hasShadow: Bool
            let level: NSWindow.Level
            let collectionBehavior: NSWindow.CollectionBehavior
            let frame: NSRect
            let closeButtonHidden: Bool
            let miniaturizeButtonHidden: Bool
            let zoomButtonHidden: Bool
        }

        /// Window level high enough to cover the menu bar but below screen saver.
        /// .mainMenu (level 24) is just above the menu bar.
        private static let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)

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
            managedWindow = window
            configurationCount += 1
            let isFirstConfiguration = configurationCount == 1

            scheduleOverlayConfiguration(for: window, isFirstConfiguration: isFirstConfiguration)
        }

        /// Restore the managed window to its pre-Airlock state.
        ///
        /// The actual work is dispatched to the next run loop iteration because
        /// this is typically called from `viewDidMoveToWindow(nil)` inside a
        /// SwiftUI view-update transaction.  Changing the style mask (borderless
        /// → titled) synchronously during that transaction causes AppKit to swap
        /// its internal frame view mid-layout, leaving the window in a broken
        /// state.
        func restoreWindow() {
            guard let window = managedWindow, let state = savedWindowState else { return }
            savedWindowState = nil
            managedWindow = nil

            DispatchQueue.main.async {
                // Restore the style mask by toggling individual flags rather
                // than replacing the whole mask.  This avoids the
                // titled↔borderless transition that reconstructs the frame
                // view and crashes NSHostingView's KVO observers.
                Self.reconcileStyleMask(to: state.styleMask, on: window)

                window.titlebarAppearsTransparent = state.titlebarAppearsTransparent
                window.titleVisibility = state.titleVisibility
                window.isOpaque = state.isOpaque
                window.backgroundColor = state.backgroundColor
                window.hasShadow = state.hasShadow
                window.level = state.level
                window.collectionBehavior = state.collectionBehavior

                window.standardWindowButton(.closeButton)?.isHidden = state.closeButtonHidden
                window.standardWindowButton(.miniaturizeButton)?.isHidden = state.miniaturizeButtonHidden
                window.standardWindowButton(.zoomButton)?.isHidden = state.zoomButtonHidden

                window.setFrame(state.frame, display: true, animate: false)
                window.makeKeyAndOrderFront(nil)
            }
        }

        private func scheduleOverlayConfiguration(for window: NSWindow, isFirstConfiguration: Bool) {
            pendingConfigurationWorkItem?.cancel()

            let workItem = DispatchWorkItem { [weak self, weak window] in
                guard let self, let window else { return }
                self.applyOverlayConfiguration(to: window, isFirstConfiguration: isFirstConfiguration)
            }

            pendingConfigurationWorkItem = workItem
            DispatchQueue.main.async(execute: workItem)
        }

        private func applyOverlayConfiguration(to window: NSWindow, isFirstConfiguration: Bool) {
            guard managedWindow === window else { return }

            // Save the original window state before any modifications.
            if savedWindowState == nil {
                savedWindowState = SavedWindowState(
                    styleMask: window.styleMask,
                    isOpaque: window.isOpaque,
                    backgroundColor: window.backgroundColor,
                    titlebarAppearsTransparent: window.titlebarAppearsTransparent,
                    titleVisibility: window.titleVisibility,
                    hasShadow: window.hasShadow,
                    level: window.level,
                    collectionBehavior: window.collectionBehavior,
                    frame: window.frame,
                    closeButtonHidden: window.standardWindowButton(.closeButton)?.isHidden ?? false,
                    miniaturizeButtonHidden: window.standardWindowButton(.miniaturizeButton)?.isHidden ?? false,
                    zoomButtonHidden: window.standardWindowButton(.zoomButton)?.isHidden ?? false
                )
            }

            // Make the window visually borderless WITHOUT switching the style
            // mask to .borderless.  Changing from .titled to .borderless (or
            // back) causes AppKit to reconstruct the window's internal frame
            // view.  If an NSHostingView is the content view, the
            // reconstruction triggers viewWillMove(toWindow: nil) which tries
            // to remove KVO observers that SwiftUI hasn't fully registered yet,
            // resulting in a crash.  Keeping .titled and using visual
            // properties achieves the same look without the frame-view swap.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden

            // Ensure content extends behind the (now-invisible) title bar.
            if !window.styleMask.contains(.fullSizeContentView) {
                window.styleMask.insert(.fullSizeContentView)
            }

            // Titled windows already return true from canBecomeKey/canBecomeMain,
            // so there is no need for the isa-swizzle that borderless windows
            // required.

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
            updateWindowFrame(window)

            if isFirstConfiguration {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        }

        /// Reconcile the window's style mask to a target value by toggling
        /// individual flags (insert / remove) rather than assigning a whole new
        /// mask.  This avoids the `.titled` ↔ `.borderless` transition that
        /// causes AppKit to reconstruct the frame view and crash
        /// NSHostingView's KVO observers.
        private static func reconcileStyleMask(to target: NSWindow.StyleMask, on window: NSWindow) {
            let current = window.styleMask
            guard current != target else { return }

            // Flags we can safely toggle without a frame-view class change.
            let safeFlags: [NSWindow.StyleMask] = [
                .fullSizeContentView, .closable, .miniaturizable, .resizable,
                .unifiedTitleAndToolbar, .fullScreen, .utilityWindow,
                .nonactivatingPanel, .hudWindow
            ]

            for flag in safeFlags {
                if target.contains(flag) && !current.contains(flag) {
                    window.styleMask.insert(flag)
                } else if !target.contains(flag) && current.contains(flag) {
                    window.styleMask.remove(flag)
                }
            }
            // Deliberately skip .titled / .borderless — toggling those
            // reconstructs the frame view and crashes NSHostingView.
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
            updateWindowFrame(window)
            window.makeKeyAndOrderFront(nil)
        }
    }
}

// MARK: - Window Observing View

/// A custom NSView that observes when it's attached to a window and notifies via callback.
/// This is more reliable than using DispatchQueue.main.async.
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
            // View is being removed from the window — restore original state.
            hasNotified = false
            onWindowDetached?()
        }
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

