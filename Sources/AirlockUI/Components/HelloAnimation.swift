import AppKit
@preconcurrency import Lottie

/// The original hello animation and startup sound, contained in a regular window.
@MainActor
public final class HelloAnimationView: NSView {
    private let playsSound: Bool
    private let onComplete: @MainActor () -> Void
    private var animation: LottieAnimationView?
    private let startupSound: AirlockStartupSound
    private var timeout: Task<Void, Never>?
    private var hasFinished = false
    private var hasStarted = false
    private let skip = NSButton(title: "Skip", target: nil, action: nil)

    public convenience init(playsSound: Bool = true, onComplete: @escaping @MainActor () -> Void) {
        self.init(playsSound: playsSound, startupSound: AirlockStartupSound(), onComplete: onComplete)
    }

    init(playsSound: Bool, startupSound: AirlockStartupSound, onComplete: @escaping @MainActor () -> Void) {
        self.playsSound = playsSound
        self.startupSound = startupSound
        self.onComplete = onComplete
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityLabel("Welcome")
        skip.target = self
        skip.action = #selector(skipIntro)
        skip.bezelStyle = .rounded
        skip.keyEquivalent = "\u{1b}"
        addSubview(skip)
        skip.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            skip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -28),
            skip.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -24)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { timeout?.cancel() }

    public func start() {
        guard !hasStarted else { return }
        hasStarted = true
        if playsSound { startupSound.playOnce() }
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(10)) } catch { return }
            self?.finish()
        }
        guard let url = Bundle.module.url(forResource: "hello", withExtension: "lottie") else {
            finish()
            return
        }
        DotLottieFile.loadedFrom(url: url) { [weak self] result in
            DispatchQueue.main.async {
                guard let self, !self.hasFinished else { return }
                switch result {
                case .success(let file): self.show(file)
                case .failure: self.finish()
                }
            }
        }
    }

    public func cancel() {
        hasFinished = true
        timeout?.cancel()
        animation?.stop()
        startupSound.stop()
    }

    public override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColor()
    }

    private func show(_ file: DotLottieFile) {
        let animation = LottieAnimationView(dotLottie: file)
        animation.contentMode = .scaleAspectFit
        animation.loopMode = .playOnce
        // The animation scales inside the window; its source dimensions must
        // not expand a compact onboarding window through Auto Layout.
        animation.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        animation.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        animation.setContentHuggingPriority(.defaultLow, for: .horizontal)
        animation.setContentHuggingPriority(.defaultLow, for: .vertical)
        self.animation = animation
        addSubview(animation, positioned: .below, relativeTo: skip)
        animation.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            animation.centerXAnchor.constraint(equalTo: centerXAnchor),
            animation.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -12),
            animation.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.84),
            animation.heightAnchor.constraint(equalTo: heightAnchor, multiplier: 0.84)
        ])
        updateColor()
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animation.currentProgress = 1
            skip.title = "Continue"
            skip.keyEquivalent = "\r"
        } else {
            animation.play { [weak self] _ in
                Task { @MainActor [weak self] in self?.finish() }
            }
        }
    }

    private func updateColor() {
        guard let animation else { return }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color = isDark ? LottieColor(r: 1, g: 1, b: 1, a: 1) : LottieColor(r: 0, g: 0, b: 0, a: 1)
        for path in ["**.Stroke 1.Color", "**.Stroke.Color", "**.Fill 1.Color", "**.Fill.Color", "**.Color"] {
            animation.setValueProvider(ColorValueProvider(color), keypath: AnimationKeypath(keypath: path))
        }
        let gradient = GradientValueProvider(Array(repeating: color, count: 17))
        for path in ["**.Gradient Stroke 1.Colors", "**.Gradient Fill 1.Colors", "**.Colors"] {
            animation.setValueProvider(gradient, keypath: AnimationKeypath(keypath: path))
        }
    }

    @objc private func skipIntro() { finish() }

    private func finish() {
        guard !hasFinished else { return }
        hasFinished = true
        timeout?.cancel()
        animation?.stop()
        onComplete()
    }
}
