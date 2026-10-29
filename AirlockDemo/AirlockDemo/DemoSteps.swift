import AppKit
import Airlock

@MainActor
class DemoContentController: AirlockStepViewController {
    let stack = NSStackView()
    override func loadView() {
        view = NSView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 20
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor)
        ])
        configureContent()
    }
    func configureContent() {}
}

final class DemoWelcomeController: DemoContentController {
    override func configureContent() {
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: "Set up your app in a regular macOS window. Your other applications stay where you left them."))
    }
}

final class DemoPreferencesController: DemoContentController {
    override func configureContent() {
        stack.addArrangedSubview(NSButton(checkboxWithTitle: "Open at login", target: nil, action: nil))
        stack.addArrangedSubview(NSButton(checkboxWithTitle: "Check for updates", target: nil, action: nil))
    }
}

final class DemoReadyController: DemoContentController {
    override func configureContent() {
        stack.addArrangedSubview(NSTextField(wrappingLabelWithString: "Your preferences are ready."))
    }
}
