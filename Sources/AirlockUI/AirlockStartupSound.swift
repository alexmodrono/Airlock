import AppKit

@MainActor
protocol AirlockSoundPlaying: AnyObject {
    var loops: Bool { get set }
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

    init(makeSound: @escaping () -> (any AirlockSoundPlaying)? = {
        guard let url = Bundle.module.url(forResource: "startup", withExtension: "wav") else { return nil }
        return NSSound(contentsOf: url, byReference: true)
    }) {
        self.makeSound = makeSound
    }

    func playOnce() {
        guard !hasPlayed else { return }
        hasPlayed = true
        sound = makeSound()
        sound?.loops = false
        _ = sound?.play()
    }

    func stop() {
        // Closing a flow consumes playback even if the intro had not started yet.
        hasPlayed = true
        _ = sound?.stop()
        sound = nil
    }
}
