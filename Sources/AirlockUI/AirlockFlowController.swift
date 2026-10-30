import AppKit
import Combine
import AirlockCore
import QuartzCore

@MainActor
public final class AirlockFlowController: NSViewController {
    private let navigator: AirlockNavigator
    private let playsIntro: Bool
    private let playsSound: Bool
    private let startupSound: AirlockStartupSound
    private let content = NSView()
    private let pageHost = NSView()
    private let actions = NSStackView()
    private let heading = NSTextField(labelWithString: "")
    private let primary = NSButton(title: "Continue", target: nil, action: nil)
    private let back = NSButton(title: "Back", target: nil, action: nil)
    private let progress = NSProgressIndicator()
    private var controllers: [String: NSViewController] = [:]
    private var displayed: NSViewController?
    private var displayedIndex: Int?
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
        configureLayout()
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
        pageHost.layer?.removeAnimation(forKey: "Airlock.stepTransition")
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
            let previousIndex = displayedIndex
            pageHost.layer?.removeAnimation(forKey: "Airlock.stepTransition")
            (displayed as? AirlockStepViewController)?.cancelPendingWork()
            (displayed as? AirlockStepViewController)?.navigator = nil
            displayed?.view.removeFromSuperview()
            displayed?.removeFromParent()
            pageHost.subviews.forEach { $0.removeFromSuperview() }
            let controller = controllers[step.id] ?? step.makeViewController()
            controllers[step.id] = controller
            if let native = controller as? AirlockStepViewController { native.navigator = navigator }
            addChild(controller)
            displayed = controller
            displayedIndex = navigator.currentIndex
            heading.stringValue = step.title
            heading.font = .systemFont(ofSize: 26, weight: .semibold)
            pageHost.addSubview(controller.view)
            controller.view.translatesAutoresizingMaskIntoConstraints = false
            var constraints = [
                controller.view.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
                controller.view.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor)
            ]
            if step.showsHeading {
                pageHost.addSubview(heading)
                heading.translatesAutoresizingMaskIntoConstraints = false
                constraints += [
                    heading.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
                    heading.topAnchor.constraint(equalTo: pageHost.topAnchor),
                    heading.trailingAnchor.constraint(lessThanOrEqualTo: pageHost.trailingAnchor),
                    controller.view.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 20)
                ]
            } else {
                constraints.append(controller.view.topAnchor.constraint(equalTo: pageHost.topAnchor))
            }
            NSLayoutConstraint.activate(constraints)
            actions.isHidden = false
            (controller as? AirlockStepViewController)?.prepareForPresentation()
            animateEntrance(from: previousIndex)
        }
        primary.title = navigator.buttonLabel ?? (navigator.isLastStep ? "Done" : "Continue")
        primary.isEnabled = navigator.canContinue && !navigator.isBusy && !navigator.isComplete
        back.isHidden = navigator.currentIndex == 0
        back.isEnabled = navigator.canGoBack
        progress.isHidden = !navigator.isBusy
        if navigator.isBusy { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }

    }

    private func configureLayout() {
        pageHost.wantsLayer = true
        pageHost.layer?.masksToBounds = true
        content.addSubview(pageHost)
        pageHost.translatesAutoresizingMaskIntoConstraints = false
        primary.target = self
        primary.action = #selector(continueFlow)
        primary.bezelStyle = .rounded
        primary.bezelColor = .controlAccentColor
        primary.controlSize = .large
        primary.keyEquivalent = "\r"
        back.target = self
        back.action = #selector(goBack)
        back.bezelStyle = .rounded
        back.controlSize = .large
        back.keyEquivalent = "\u{1b}"
        progress.style = .spinning
        progress.controlSize = .small
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 8
        actions.addArrangedSubview(progress)
        actions.addArrangedSubview(back)
        actions.addArrangedSubview(primary)
        actions.isHidden = true
        content.addSubview(actions)
        actions.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            pageHost.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            pageHost.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            pageHost.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            pageHost.bottomAnchor.constraint(equalTo: actions.topAnchor, constant: -18),
            actions.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 24),
            actions.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            actions.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -18),
            primary.widthAnchor.constraint(greaterThanOrEqualToConstant: 100)
        ])
    }

    private func animateEntrance(from previousIndex: Int?) {
        guard let layer = pageHost.layer else { return }
        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        var animations: [CAAnimation] = [fade]
        if !reducedMotion, let previousIndex {
            let slide = CABasicAnimation(keyPath: "transform.translation.x")
            slide.fromValue = navigator.currentIndex > previousIndex ? 24 : -24
            slide.toValue = 0
            animations.append(slide)
        }
        let transition = CAAnimationGroup()
        transition.animations = animations
        transition.duration = reducedMotion ? 0.15 : 0.3
        transition.timingFunction = CAMediaTimingFunction(name: .easeOut)
        // Only the active live view animates. Retired controllers and sensitive
        // fields disappear immediately, without snapshots or delayed callbacks.
        layer.add(transition, forKey: "Airlock.stepTransition")
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
