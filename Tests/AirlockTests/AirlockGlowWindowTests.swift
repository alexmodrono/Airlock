import AppKit
import Testing
@testable import AirlockUI
import AirlockCore

@Suite(.serialized) @MainActor
struct AirlockGlowWindowTests {
    private func controller() -> AirlockWindowController {
        _ = NSApplication.shared
        let navigator = AirlockNavigator(appName: "Glow Test", steps: [
            AirlockStep(id: "test", title: "Test") { NSViewController() }
        ])
        return AirlockWindowController(navigator: navigator, playsIntro: false,
                                      playsSound: false, autosavesFrame: false)
    }

    @Test(arguments: [NSRect(x: 0, y: 0, width: 1440, height: 900),
                      NSRect(x: -1920, y: -300, width: 1920, height: 1080),
                      NSRect(x: 200, y: 900, width: 1440, height: 900)])
    func contentUsesTheExactScreenMidpoint(screen: NSRect) {
        let visible = NSRect(x: screen.minX, y: screen.minY + 50,
                             width: screen.width, height: screen.height - 75)
        let centered = AirlockWindowController.centeredContentFrame(
            size: NSSize(width: 560, height: 500), screen: screen, visibleScreen: visible)
        #expect(centered.midX == screen.midX)
        #expect(centered.midY == screen.midY)
        #expect(centered.size == NSSize(width: 560, height: 500))
    }

    @Test func centeringOnAShortDisplayKeepsNavigationVisible() {
        let screen = NSRect(x: -600, y: 400, width: 600, height: 500)
        let visible = screen.insetBy(dx: 0, dy: 20)
        let centered = AirlockWindowController.centeredContentFrame(
            size: NSSize(width: 560, height: 500), screen: screen, visibleScreen: visible)
        let navigation = AirlockWindowController.navigationFrame(above: centered, width: 480, screen: visible)
        #expect(visible.contains(centered))
        #expect(visible.contains(navigation))
        #expect(navigation.minY >= centered.maxY + 12)
    }

    @Test func completedIntroFadesOutAndCannotRestoreAPersistentGlow() throws {
        let glow = AirlockGlowView(frame: .zero, reduceMotion: { false })
        let halo = try #require(glow.layer?.sublayers?.first)
        #expect(halo.opacity == 0)
        glow.setIntroPlaying(true)
        #expect(halo.opacity == 0.5)
        glow.setIntroPlaying(false)
        #expect(halo.opacity == 0)
        let fade = try #require(halo.animation(forKey: "introFade") as? CABasicAnimation)
        #expect(fade.duration == 0.5)
        #expect((fade.toValue as? Float) == 0)
        glow.setIntroPlaying(false)
        #expect(halo.opacity == 0)
        #expect(halo.animation(forKey: "introFade") != nil)
        glow.setIntroPlaying(false, animated: false)
        #expect(halo.animationKeys()?.isEmpty != false)
    }

    @Test func reducedMotionRemovesTheGlowImmediately() throws {
        let glow = AirlockGlowView(frame: .zero, reduceMotion: { true })
        let halo = try #require(glow.layer?.sublayers?.first)
        glow.setIntroPlaying(true)
        #expect(halo.opacity == 0.5)
        glow.setIntroPlaying(false)
        #expect(halo.opacity == 0)
        #expect(halo.animationKeys()?.isEmpty != false)
    }

    @Test func glowFollowsTheMainWindowWithoutCapturingInput() throws {
        let controller = controller()
        defer { controller.close() }
        controller.present()
        let main = try #require(controller.window)
        let glow = try #require(main.childWindows?.first { $0.contentView is AirlockGlowView })
        #expect(glow.ignoresMouseEvents)
        #expect(!glow.canBecomeKey)
        #expect(!glow.canBecomeMain)
        #expect(glow.level == .normal)
        #expect(!glow.hasShadow)
        #expect(glow.parent === main)
        #expect(glow.frame == main.frame.insetBy(dx: -AirlockGlowView.margin, dy: -AirlockGlowView.margin))
        main.setFrame(main.frame.offsetBy(dx: 40, dy: -30), display: false)
        controller.windowDidMove(Notification(name: NSWindow.didMoveNotification, object: main))
        #expect(glow.frame == main.frame.insetBy(dx: -AirlockGlowView.margin, dy: -AirlockGlowView.margin))
        controller.close()
        #expect(!glow.isVisible)
        #expect(glow.parent == nil)
    }

    @Test func reopeningCentersButPresentingAVisibleWindowDoesNotUndoADrag() throws {
        let controller = controller()
        defer { controller.close() }
        controller.present()
        let window = try #require(controller.window)
        let screen = try #require(window.screen)
        let expected = AirlockWindowController.centeredContentFrame(size: window.frame.size,
                                                                   screen: screen.frame,
                                                                   visibleScreen: screen.visibleFrame)
        let pixel = 1 / screen.backingScaleFactor
        #expect(abs(window.frame.midX - expected.midX) <= pixel)
        #expect(abs(window.frame.midY - expected.midY) <= pixel)
        window.setFrameOrigin(NSPoint(x: window.frame.minX + 35, y: window.frame.minY - 30))
        let moved = window.frame
        controller.present()
        #expect(window.frame == moved)
        controller.close()
        controller.present()
        #expect(abs(window.frame.midX - expected.midX) <= pixel)
        #expect(abs(window.frame.midY - expected.midY) <= pixel)
        #expect(window.childWindows?.count == 2)
    }
}
