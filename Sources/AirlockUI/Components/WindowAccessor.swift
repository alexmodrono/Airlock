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
            let originalClass: AnyClass
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
        func restoreWindow() {
            guard let window = managedWindow, let state = savedWindowState else { return }
            savedWindowState = nil
            managedWindow = nil

            // Restore the original class first, before any property changes.
            // This un-does the isa-swizzle so KVO observer deregistrations
            // (triggered by style mask / content view changes) match the
            // class under which they were originally registered.
            let currentClass: AnyClass = type(of: window)
            if currentClass !== state.originalClass {
                object_setClass(window, state.originalClass)
            }

            window.styleMask = state.styleMask
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
                    originalClass: type(of: window),
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

            // Defer the borderless transition until after the hosting window is
            // attached and AppKit's initial layout transaction has completed.
            // Swapping out NSThemeFrame during that transaction can crash when
            // AppKit later asks the deallocated frame for maskView.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask = [.borderless, .fullSizeContentView]

            // Borderless windows return false from canBecomeKey by default,
            // which prevents TextFields from accepting focus. Subclass the
            // window at runtime to override this.
            KeyableWindowInstaller.install(on: window)

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

// MARK: - Keyable Window

/// Makes a borderless NSWindow accept key status so TextFields can receive focus.
///
/// Borderless windows (`styleMask` without `.titled`) return `false` from
/// `canBecomeKey` by default. This helper replaces the window's class at runtime
/// with a subclass that overrides `canBecomeKey` to return `true`.
enum KeyableWindowInstaller {
    private static var installedClasses: [String: AnyClass] = [:]

    static func install(on window: NSWindow) {
        let originalClass: AnyClass = type(of: window)
        let className = NSStringFromClass(originalClass)
        let subclassName = "Airlock_Keyable_\(className)"

        if let existing = installedClasses[subclassName] {
            object_setClass(window, existing)
            return
        }

        guard let subclass = objc_allocateClassPair(originalClass, subclassName, 0) else {
            return
        }

        let trueBlock: @convention(block) (AnyObject) -> Bool = { _ in true }
        let trueIMP = imp_implementationWithBlock(trueBlock)

        if let method = class_getInstanceMethod(originalClass, #selector(getter: NSWindow.canBecomeKey)) {
            class_addMethod(subclass, #selector(getter: NSWindow.canBecomeKey), trueIMP, method_getTypeEncoding(method))
        }

        if let method = class_getInstanceMethod(originalClass, #selector(getter: NSWindow.canBecomeMain)) {
            class_addMethod(subclass, #selector(getter: NSWindow.canBecomeMain), trueIMP, method_getTypeEncoding(method))
        }

        objc_registerClassPair(subclass)
        installedClasses[subclassName] = subclass
        object_setClass(window, subclass)
    }
}
