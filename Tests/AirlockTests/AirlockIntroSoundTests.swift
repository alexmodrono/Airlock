import AppKit
import AirlockCore
import Testing
@testable import AirlockUI

@Suite @MainActor
struct AirlockIntroSoundTests {
    @Test func soundDoesNotLoopOrReplayAfterFinishing() {
        let sound = IntroTestSound()
        let playback = AirlockStartupSound(makeSound: { sound })
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
        let playback = AirlockStartupSound(makeSound: { sound })
        playback.stop()
        playback.playOnce()
        #expect(sound.playCount == 0)
    }

    @Test func skippingTheIntroFadesSoundWhileAdvancingImmediately() async throws {
        _ = NSApplication.shared
        let sound = IntroTestSound()
        let clock = IntroFadeClock()
        defer { clock.resume() }
        let playback = AirlockStartupSound(waitForFadeStep: { await clock.wait() }, makeSound: { sound })
        let navigator = AirlockNavigator(appName: "Intro Test", steps: [
            AirlockStep(id: "ready", title: "Ready") { NSViewController() }
        ])
        let flow = AirlockFlowController(navigator: navigator, playsIntro: true, playsSound: true,
                                        startupSound: playback)
        defer { flow.cancelPendingWork() }
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
        for step in 1...15 {
            try await waitUntil { clock.pending != nil }
            // Duplicate fade requests cannot restart or extend the fade.
            playback.fadeOut()
            clock.resume()
            try await waitUntil { sound.volumes.count == step }
            #expect(sound.volume == Float(15 - step) / 15)
            if step < 15 { #expect(sound.isPlaying) }
        }
        #expect(sound.volumes.first! > 0)
        #expect(sound.volumes.last == 0)
        #expect(!sound.isPlaying)
        #expect(sound.stopCount == 1)
        flow.resume()
        #expect(sound.playCount == 1)
    }

    @Test func closingDuringTheIntroStopsSoundWithoutCompletingTheVisualAgain() {
        let sound = IntroTestSound()
        var completions = 0
        let intro = HelloAnimationView(playsSound: true, startupSound: AirlockStartupSound(makeSound: { sound })) {
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

    @Test func closingDuringFadeStopsOnceAndCancelsVolumeUpdates() async throws {
        let sound = IntroTestSound()
        let clock = IntroFadeClock()
        let playback = AirlockStartupSound(waitForFadeStep: { await clock.wait() }, makeSound: { sound })
        defer { playback.stop(); clock.resume() }
        playback.playOnce()
        playback.fadeOut()
        try await waitUntil { clock.pending != nil }
        playback.stop()
        clock.resume()
        try await waitUntil { clock.resumedCount == 1 }
        playback.playOnce()
        #expect(sound.stopCount == 1)
        #expect(sound.playCount == 1)
        #expect(sound.volumes.isEmpty)
        #expect(!sound.isPlaying)
    }

    @Test func fadeFinishesAfterItsOwnerReleasesPlayback() async throws {
        let sound = IntroTestSound()
        sound.volume = 0.5
        var playback: AirlockStartupSound? = AirlockStartupSound(
            waitForFadeStep: { await Task.yield() }, makeSound: { sound })
        weak var retainedPlayback = playback
        playback?.playOnce()
        playback?.fadeOut()
        playback = nil
        try await waitUntil { sound.stopCount == 1 && retainedPlayback == nil }
        #expect(sound.volumes[1] > 0 && sound.volumes[1] < 0.5)
        #expect(sound.volume == 0)
        #expect(!sound.isPlaying)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition(), ContinuousClock.now < deadline { await Task.yield() }
        try #require(condition())
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
    var volume: Float = 1 { didSet { volumes.append(volume) } }
    private(set) var volumes: [Float] = []
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

@MainActor
private final class IntroFadeClock {
    var pending: CheckedContinuation<Void, Never>?
    private(set) var resumedCount = 0

    func wait() async {
        await withCheckedContinuation { pending = $0 }
        resumedCount += 1
    }

    func resume() {
        let continuation = pending
        pending = nil
        continuation?.resume()
    }
}
