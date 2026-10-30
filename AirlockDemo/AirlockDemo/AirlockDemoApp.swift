import AppKit
import Airlock

@main
enum AirlockDemoApp {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = DemoApplicationDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        withExtendedLifetime(delegate) { application.run() }
    }
}

@MainActor
final class DemoApplicationDelegate: NSObject, NSApplicationDelegate {
    private var onboarding: AirlockWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu()
        let app = NSMenuItem()
        app.submenu = NSMenu()
        app.submenu?.addItem(withTitle: "Quit Airlock Demo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(app)
        NSApp.mainMenu = menu
        let navigator = AirlockNavigator(appName: "Airlock") {
            AirlockStep(id: "welcome", title: "Welcome") { DemoWelcomeController() }.showsHeading(false)
            AirlockStep(id: "preferences", title: "Preferences") { DemoPreferencesController() }.showsHeading(false)
            AirlockStep(id: "ready", title: "Ready") { DemoReadyController() }.showsHeading(false)
        }
        let controller = AirlockWindowController(navigator: navigator)
        navigator.onComplete = { [weak self] in self?.onboarding?.close() }
        controller.onClose = { NSApp.terminate(nil) }
        onboarding = controller
        controller.present()
    }
}
