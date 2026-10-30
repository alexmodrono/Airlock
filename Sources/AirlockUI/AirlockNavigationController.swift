import AppKit
import Combine
import AirlockCore

/// Step navigation lives in its own child window, above the setup content.
@MainActor
final class AirlockNavigationController: NSViewController {
    private let navigator: AirlockNavigator
    let tabs = NSSegmentedControl()
    private var subscription: AnyCancellable?
    var onSelection: (() -> Void)?
    var navigationEnabled: Bool { didSet { refresh() } }

    init(navigator: AirlockNavigator, navigationEnabled: Bool) {
        self.navigator = navigator
        self.navigationEnabled = navigationEnabled
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let surface = AirlockGlassSurface(radius: 24, interactive: true)
        view = surface
        tabs.segmentCount = navigator.steps.count
        tabs.trackingMode = .selectOne
        // The system style is the native segmented picker: a capsule track with
        // a sliding selection that adapts to Liquid Glass, appearance and contrast.
        tabs.segmentStyle = .automatic
        tabs.segmentDistribution = .fillEqually
        tabs.controlSize = .large
        let font = tabs.font ?? .systemFont(ofSize: NSFont.systemFontSize(for: .large))
        tabs.target = self
        tabs.action = #selector(selectStep)
        tabs.setAccessibilityLabel("Setup steps")
        let segmentWidth = navigator.steps.map {
            ($0.title as NSString).size(withAttributes: [.font: font]).width + 28
        }.max() ?? 80
        for (index, step) in navigator.steps.enumerated() {
            tabs.setLabel(step.title, forSegment: index)
            tabs.setToolTip(step.title, forSegment: index)
            tabs.setWidth(segmentWidth, forSegment: index)
        }
        // Long or localized step labels remain reachable on narrow displays.
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        // Overlay scrollers never take height from the picker, so it stays centred
        // even when "Show scroll bars" is set to Always.
        scroll.scrollerStyle = .overlay
        scroll.documentView = tabs
        tabs.sizeToFit()
        tabs.setFrameOrigin(.zero)
        surface.content.addSubview(scroll)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: surface.content.leadingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: surface.content.trailingAnchor, constant: -10),
            scroll.centerYAnchor.constraint(equalTo: surface.content.centerYAnchor),
            scroll.heightAnchor.constraint(equalToConstant: tabs.frame.height)
        ])
        subscription = navigator.objectWillChange.sink { [weak self] in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        refresh()
    }

    var preferredWidth: CGFloat { _ = view; return tabs.frame.width + 20 }

    private func refresh() {
        guard isViewLoaded else { return }
        for index in navigator.steps.indices {
            tabs.setSelected(index == navigator.currentIndex, forSegment: index)
            tabs.setEnabled(navigationEnabled && navigator.canGoTo(index: index), forSegment: index)
        }
    }

    @objc private func selectStep() {
        guard navigationEnabled else { return }
        navigator.goTo(index: tabs.selectedSegment)
        refresh()
        onSelection?()
    }
}
