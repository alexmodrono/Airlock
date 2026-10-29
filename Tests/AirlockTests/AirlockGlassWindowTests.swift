import AppKit
import Testing
@testable import AirlockUI
import AirlockCore

@Suite(.serialized) @MainActor
struct AirlockGlassWindowTests {
    private func controller(step: GlassWindowTestStep = GlassWindowTestStep(),
                            playsIntro: Bool = false) -> AirlockWindowController {
        _ = NSApplication.shared
        let navigator = AirlockNavigator(appName: "Glass Window Test", steps: [
            AirlockStep(id: "site", title: "Site") { step },
            AirlockStep(id: "signin", title: "Sign In") { GlassWindowTestStep() },
            AirlockStep(id: "courses", title: "Courses") { GlassWindowTestStep() }
        ])
        return AirlockWindowController(navigator: navigator, playsIntro: playsIntro,
                                      playsSound: false, autosavesFrame: false)
    }

    @Test func untitledWindowStillAcceptsKeyboardInput() throws {
        let controller = controller()
        let window = try #require(controller.window)
        defer { controller.close() }
        #expect(!window.styleMask.contains(.titled))
        #expect(window.styleMask.contains(.resizable))
        #expect(window.standardWindowButton(.closeButton) == nil)
        #expect(window.standardWindowButton(.miniaturizeButton) == nil)
        #expect(window.standardWindowButton(.zoomButton) == nil)
        #expect(window.canBecomeKey)
        #expect(window.canBecomeMain)
        #expect(window.level == .normal)
        #expect(!window.isOpaque)
    }

    @Test func attachedNavigationTracksAResizeWithoutDuplicatingWindows() throws {
        let controller = controller()
        defer { controller.close() }
        controller.present()
        let window = try #require(controller.window)
        let child = try #require(window.childWindows?.first { $0.contentViewController is AirlockNavigationController })
        #expect(window.childWindows?.count == 2)
        #expect(child.parent === window)
        #expect(child.level == .normal)
        #expect(child.isVisible)
        let screen = try #require(window.screen)
        let frame = NSRect(x: screen.visibleFrame.midX - 300, y: screen.visibleFrame.midY - 210,
                           width: 600, height: 420)
        window.setFrame(frame, display: false)
        controller.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
        let expected = AirlockWindowController.navigationFrame(above: window.frame,
                                                               width: child.frame.width,
                                                               screen: screen.visibleFrame)
        let pixel = 1 / screen.backingScaleFactor
        #expect(abs(child.frame.minX - expected.minX) <= pixel)
        #expect(abs(child.frame.minY - expected.minY) <= pixel)
        #expect(child.frame.size == expected.size)
        #expect(child.frame.minY > window.frame.maxY)
        controller.present()
        #expect(window.childWindows?.count == 2)
    }

    @Test func closeDetachesNavigationAndCancelsStepWork() throws {
        let step = GlassWindowTestStep()
        let controller = controller(step: step)
        var closes = 0
        controller.onClose = { closes += 1 }
        controller.present()
        let window = try #require(controller.window)
        window.contentViewController?.viewDidAppear()
        let child = try #require(window.childWindows?.first { $0.contentViewController is AirlockNavigationController })
        controller.close()
        #expect(closes == 1)
        #expect(step.cancellations == 1)
        #expect(child.parent == nil)
        #expect(!child.isVisible)
        #expect(window.childWindows?.isEmpty != false)
        #expect(!window.isVisible)
    }

    @Test func commandWClosesBothWindows() throws {
        let controller = controller()
        controller.present()
        let window = try #require(controller.window)
        let child = try #require(window.childWindows?.first { $0.contentViewController is AirlockNavigationController })
        defer { if window.isVisible { controller.close() } }
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "w",
            charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13
        ))
        #expect(window.performKeyEquivalent(with: event))
        #expect(!window.isVisible)
        #expect(!child.isVisible)
        #expect(child.parent == nil)
    }

    @Test func reopeningAfterClosingTheIntroRestoresTheStepAndNavigation() throws {
        let step = GlassWindowTestStep()
        let controller = controller(step: step, playsIntro: true)
        defer { controller.close() }
        controller.present()
        let window = try #require(controller.window)
        window.contentViewController?.viewDidAppear()
        controller.close()
        controller.present()
        let child = try #require(window.childWindows?.first { $0.contentViewController is AirlockNavigationController })
        let navigation = try #require(child.contentViewController as? AirlockNavigationController)
        #expect(navigation.navigationEnabled)
        #expect(window.contentViewController?.children.first is GlassWindowTestStep)
        #expect(controller.navigator.canContinue)
        #expect(step.preparations == 1)
        #expect(child.isVisible)
    }

    @Test(arguments: [
        NSRect(x: 0, y: 25, width: 1440, height: 850),
        NSRect(x: -1280, y: -400, width: 1280, height: 600),
        NSRect(x: 200, y: 100, width: 640, height: 480),
        NSRect(x: -500, y: 900, width: 520, height: 400)
    ])
    func combinedWindowsFitShortAndOffsetDisplays(screen: NSRect) {
        let oversized = NSRect(x: screen.maxX - 100, y: screen.maxY - 100, width: 720, height: 560)
        let content = AirlockWindowController.contentFrame(oversized, in: screen)
        let navigation = AirlockWindowController.navigationFrame(above: content, width: 700, screen: screen)
        #expect(screen.contains(content))
        #expect(screen.contains(navigation))
        #expect(navigation.minY >= content.maxY + 12)
        #expect(navigation.width > 0)
        #expect(content.width > 0 && content.height > 0)
    }

    @Test func navigationCannotEscapeTheVisibleScreenAtTheTopEdge() {
        let screen = NSRect(x: -1280, y: -400, width: 1280, height: 600)
        let main = NSRect(x: -1000, y: -220, width: 720, height: 420)
        let navigation = AirlockWindowController.navigationFrame(above: main, width: 600, screen: screen)
        #expect(screen.contains(navigation))
    }
}

@MainActor
private final class GlassWindowTestStep: AirlockStepViewController {
    private(set) var cancellations = 0
    private(set) var preparations = 0

    override func loadView() { view = NSView() }
    override func prepareForPresentation() {
        preparations += 1
        super.prepareForPresentation()
    }
    override func cancelPendingWork() { cancellations += 1 }
}
