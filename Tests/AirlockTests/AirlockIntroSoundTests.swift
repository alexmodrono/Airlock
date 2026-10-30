import AppKit
import AirlockCore
import Testing
@testable import AirlockUI

@Suite @MainActor
struct AirlockIntroSoundTests {
    @Test func soundDoesNotLoopOrReplayAfterFinishing() {
        let sound = IntroTestSound()
        let playback = AirlockStartupSound { sound }
        playback.playOnce()
        #expect(sound.playCount == 1)
        #expect(!sound.loops)
        sound.finishPlayback()
        playback.playOnce()
        #expect(sound.playCount == 1)
        #expect(!sound.isPlaying)
    }

    @Test func cancellingBeforeStartPreventsLatePlayback() {
        let sound = IntroTestSound()
        let playback = AirlockStartupSound { sound }
        playback.stop()
        playback.playOnce()
        #expect(sound.playCount == 0)
    }

    @Test func skippingTheVisualIntroKeepsSoundAliveUntilTheFlowCloses() throws {
        _ = NSApplication.shared
        let sound = IntroTestSound()
        let navigator = AirlockNavigator(appName: "Intro Test", steps: [
            AirlockStep(id: "ready", title: "Ready") { NSViewController() }
        ])
        let flow = AirlockFlowController(navigator: navigator, playsIntro: true, playsSound: true,
                                        startupSound: AirlockStartupSound { sound })
        _ = flow.view
        flow.viewDidAppear()
        #expect(sound.isPlaying)
        try skipIntro(in: flow.view)
        #expect(firstSubview(HelloAnimationView.self, in: flow.view) == nil)
        #expect(flow.children.count == 1)
        #expect(sound.isPlaying)
        #expect(sound.stopCount == 0)
        flow.viewDidAppear()
        flow.resume()
        #expect(sound.playCount == 1)
        flow.cancelPendingWork()
        #expect(!sound.isPlaying)
        #expect(sound.stopCount == 1)
        flow.resume()
        #expect(sound.playCount == 1)
    }

    @Test func closingDuringTheIntroStopsSoundWithoutCompletingTheVisualAgain() {
        let sound = IntroTestSound()
        var completions = 0
        let intro = HelloAnimationView(playsSound: true, startupSound: AirlockStartupSound { sound }) {
            completions += 1
        }
        intro.start()
        intro.cancel()
        intro.start()
        #expect(sound.playCount == 1)
        #expect(sound.stopCount == 1)
        #expect(!sound.isPlaying)
        #expect(completions == 0)
    }

    private func skipIntro(in view: NSView) throws {
        let intro = try #require(firstSubview(HelloAnimationView.self, in: view))
        let skip = try #require(intro.subviews.compactMap { $0 as? NSButton }.first)
        skip.performClick(nil)
    }

    private func firstSubview<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        for child in view.subviews {
            if let match = firstSubview(type, in: child) { return match }
        }
        return nil
    }
}

@MainActor
private final class IntroTestSound: AirlockSoundPlaying {
    var loops = true
    private(set) var playCount = 0
    private(set) var stopCount = 0
    private(set) var isPlaying = false

    func play() -> Bool {
        playCount += 1
        isPlaying = true
        return true
    }

    func stop() -> Bool {
        stopCount += 1
        isPlaying = false
        return true
    }

    func finishPlayback() { isPlaying = false }
}
