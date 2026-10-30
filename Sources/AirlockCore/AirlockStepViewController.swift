import AppKit

/// Subclass for screens that configure the shared navigation controls.
@MainActor
open class AirlockStepViewController: NSViewController {
    public weak var navigator: AirlockNavigator?

    /// Called each time the user visits this screen, after navigator injection.
    open func prepareForPresentation() { navigator?.setContinueEnabled(true) }

    /// Cancel screen-owned work when the window closes or the screen changes.
    open func cancelPendingWork() {}
}
