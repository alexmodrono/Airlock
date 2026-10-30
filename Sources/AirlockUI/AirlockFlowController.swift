import AppKit
import Combine
import AirlockCore

@MainActor
public final class AirlockFlowController: NSViewController {
    private let navigator: AirlockNavigator
    private let playsIntro: Bool
    private let playsSound: Bool
    private let startupSound: AirlockStartupSound
    private let content = NSView()
    private let heading = NSTextField(labelWithString: "")
    private let primary = NSButton(title: "Continue", target: nil, action: nil)
    private let back = NSButton(title: "Back", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private var controllers: [String: NSViewController] = [:]
    private var displayed: NSViewController?
    private var intro: HelloAnimationView?
    private var subscriptions = Set<AnyCancellable>()
    private var hasStarted = false
    private var isPresented = false
    private(set) var refreshTask: Task<Void, Never>?
    var onIntroFinished: (() -> Void)?

    public convenience init(navigator: AirlockNavigator, playsIntro: Bool = true, playsSound: Bool = true) {
        self.init(navigator: navigator, playsIntro: playsIntro, playsSound: playsSound,
                  startupSound: AirlockStartupSound())
    }

    init(navigator: AirlockNavigator, playsIntro: Bool, playsSound: Bool, startupSound: AirlockStartupSound) {
        self.navigator = navigator
        self.playsIntro = playsIntro
        self.playsSound = playsSound
        self.startupSound = startupSound
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        let surface = AirlockContentSurface()
        view = surface
        pin(content, in: surface)
        navigator.objectWillChange.sink { [weak self] in
            self?.refreshTask?.cancel()
            self?.refreshTask = Task { @MainActor [weak self] in
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }.store(in: &subscriptions)
    }

    public override func viewDidAppear() {
        super.viewDidAppear()
        isPresented = true
        guard !hasStarted else { return }
        hasStarted = true
        if playsIntro {
            let hello = HelloAnimationView(playsSound: playsSound, startupSound: startupSound) { [weak self] in
                guard let self else { return }
                self.intro?.removeFromSuperview()
                self.intro = nil
                self.refresh()
                self.onIntroFinished?()
            }
            intro = hello
            pin(hello, in: content)
            hello.start()
        } else {
            refresh()
        }
    }

    public func cancelPendingWork() {
        isPresented = false
        refreshTask?.cancel()
        refreshTask = nil
        intro?.cancel()
        startupSound.stop()
        intro?.removeFromSuperview()
        intro = nil
        onIntroFinished?()
        (displayed as? AirlockStepViewController)?.cancelPendingWork()
        (displayed as? AirlockStepViewController)?.navigator = nil
    }

    func resume() {
        isPresented = true
        guard hasStarted else { return }
        let previous = displayed
        refresh()
        if let previous, previous === displayed {
            (displayed as? AirlockStepViewController)?.navigator = navigator
            (displayed as? AirlockStepViewController)?.prepareForPresentation()
        }
    }

    private func refresh() {
        guard isPresented, isViewLoaded, intro == nil, let step = navigator.currentStep else { return }
        if displayed !== controllers[step.id] || displayed == nil {
            (displayed as? AirlockStepViewController)?.cancelPendingWork()
            (displayed as? AirlockStepViewController)?.navigator = nil
            displayed?.view.removeFromSuperview()
            displayed?.removeFromParent()
            content.subviews.forEach { $0.removeFromSuperview() }
            let controller = controllers[step.id] ?? step.makeViewController()
            controllers[step.id] = controller
            if let native = controller as? AirlockStepViewController { native.navigator = navigator }
            addChild(controller)
            displayed = controller
            heading.stringValue = step.title
            heading.font = .systemFont(ofSize: 26, weight: .semibold)
            content.addSubview(heading)
            content.addSubview(controller.view)
            content.addSubview(primary)
            content.addSubview(back)
            content.addSubview(progress)
            for child in content.subviews { child.translatesAutoresizingMaskIntoConstraints = false }
            primary.target = self
            primary.action = #selector(continueFlow)
            primary.bezelStyle = .rounded
            primary.keyEquivalent = "\r"
            back.target = self
            back.action = #selector(goBack)
            back.bezelStyle = .rounded
            progress.style = .spinning
            progress.controlSize = .small
            NSLayoutConstraint.activate([
                heading.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
                heading.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
                heading.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -32),
                controller.view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
                controller.view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
                controller.view.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 22),
                controller.view.bottomAnchor.constraint(equalTo: primary.topAnchor, constant: -24),
                primary.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
                primary.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
                primary.widthAnchor.constraint(greaterThanOrEqualToConstant: 100),
                back.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
                back.centerYAnchor.constraint(equalTo: primary.centerYAnchor),
                progress.trailingAnchor.constraint(equalTo: primary.leadingAnchor, constant: -12),
                progress.centerYAnchor.constraint(equalTo: primary.centerYAnchor)
            ])
            (controller as? AirlockStepViewController)?.prepareForPresentation()
        }
        primary.title = navigator.buttonLabel ?? (navigator.isLastStep ? "Done" : "Continue")
        primary.isEnabled = navigator.canContinue && !navigator.isBusy && !navigator.isComplete
        back.isHidden = navigator.currentIndex == 0
        back.isEnabled = navigator.canGoBack
        progress.isHidden = !navigator.isBusy
        if navigator.isBusy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }

    }

    private func pin(_ child: NSView, in parent: NSView) {
        parent.addSubview(child)
        child.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            child.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: parent.trailingAnchor),
            child.topAnchor.constraint(equalTo: parent.topAnchor),
            child.bottomAnchor.constraint(equalTo: parent.bottomAnchor)
        ])
    }

    @objc private func continueFlow() { navigator.goToNext() }
    @objc private func goBack() { navigator.goToPrevious() }
}
