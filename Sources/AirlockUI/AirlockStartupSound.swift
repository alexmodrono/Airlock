import AppKit

@MainActor
protocol AirlockSoundPlaying: AnyObject {
    var loops: Bool { get set }
    var volume: Float { get set }
    func play() -> Bool
    func stop() -> Bool
}

extension NSSound: AirlockSoundPlaying {}

/// Retained by the flow so removing its intro view cannot truncate the audio.
@MainActor
final class AirlockStartupSound {
    private let makeSound: () -> (any AirlockSoundPlaying)?
    private var sound: (any AirlockSoundPlaying)?
    private var hasPlayed = false
    private var fadeTask: Task<Void, Never>?
    private let waitForFadeStep: @MainActor () async -> Void

    init(waitForFadeStep: @escaping @MainActor () async -> Void = {
        try? await Task.sleep(for: .milliseconds(20))
    }, makeSound: @escaping () -> (any AirlockSoundPlaying)? = {
        guard let url = Bundle.module.url(forResource: "startup", withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }) {
        self.makeSound = makeSound
        self.waitForFadeStep = waitForFadeStep
    }

    deinit { fadeTask?.cancel() }

    func playOnce() {
        guard !hasPlayed else { return }
        hasPlayed = true
        sound = makeSound()
        sound?.loops = false
        _ = sound?.play()
    }

    /// Advance the visual intro immediately while fading its remaining audio over 300 ms.
    func fadeOut() {
        guard fadeTask == nil, let sound else { return }
        hasPlayed = true
        let initialVolume = sound.volume
        let waitForStep = waitForFadeStep
        // Keep playback alive through the bounded fade even if a standalone intro is removed.
        fadeTask = Task { [self] in
            for step in 1...15 {
                await waitForStep()
                guard !Task.isCancelled, let sound = self.sound else { return }
                sound.volume = initialVolume * Float(15 - step) / 15
            }
            stop()
        }
    }

    func stop() {
        // Closing a flow consumes playback even if the intro had not started yet.
        hasPlayed = true
        fadeTask?.cancel()
        fadeTask = nil
        _ = sound?.stop()
        sound = nil
    }
}
