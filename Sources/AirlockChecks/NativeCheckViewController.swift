import AppKit
import Combine
import AirlockCore
import AirlockUI

@MainActor
final class NativeCheckViewController<Check: FlightCheck>: AirlockStepViewController {
    private let check: Check
    private let stack = NSStackView()
    private let status = NSTextField(wrappingLabelWithString: "")
    private let field = NSTextField()
    private let progress = NSProgressIndicator()
    private var subscriptions = Set<AnyCancellable>()
    private var validation: Task<Void, Never>?
    private var permissionRequest: Task<Void, Never>?
    private var permissionLabels: [PermissionType: NSTextField] = [:]
    private var permissionMessage = ""

    init(check: Check) {
        self.check = check
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.topAnchor.constraint(equalTo: view.topAnchor)
        ])
        var description = check.description
        var instructions: [String] = []
        if let accessibility = check as? AccessibilityCheck {
            description = accessibility.configuration.detailDescription
            instructions = accessibility.configuration.instructions
        } else if let disk = check as? FullDiskAccessCheck {
            description = disk.configuration.detailDescription
            instructions = disk.configuration.instructions
        }
        let explanation = NSTextField(wrappingLabelWithString: description)
        stack.addArrangedSubview(explanation)
        explanation.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        if !instructions.isEmpty {
            let steps = NSTextField(wrappingLabelWithString: instructions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
            stack.addArrangedSubview(steps)
            steps.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        if let permissions = check as? PermissionsCheck {
            for permission in permissions.requiredPermissions {
                let label = NSTextField(labelWithString: permission.displayName)
                let state = NSTextField(labelWithString: "")
                state.textColor = .secondaryLabelColor
                permissionLabels[permission] = state
                let request = CheckActionButton(permission.requestButtonLabel) { [weak self] in
                    self?.request(permission, check: permissions)
                }
                request.setAccessibilityLabel("\(permission.requestButtonLabel) \(permission.displayName)")
                let row = NSStackView(views: [label, state, request])
                row.orientation = .horizontal
                row.spacing = 12
                stack.addArrangedSubview(row)
            }
        }
        if let license = check as? LicenseActivationCheck {
            field.placeholderString = license.configuration.placeholder
            field.setAccessibilityLabel(license.configuration.fieldTitle)
            stack.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.isHidden = !(check is SetupCheck)
        stack.addArrangedSubview(progress)
        progress.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.addArrangedSubview(status)
        check.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }.store(in: &subscriptions)
    }

    override func prepareForPresentation() {
        if let setup = check as? SetupCheck { setup.start() }
        if let welcome = check as? WelcomeCheck { welcome.beginAutoAdvanceIfNeeded() }
        let label = (check as? LicenseActivationCheck)?.configuration.submitButtonTitle ?? (check.actionLabel.isEmpty ? "Continue" : check.actionLabel)
        configureAction(label: label)
        validation?.cancel()
        validation = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.validate()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        refresh()
    }

    private func configureAction(label: String) {
        navigator?.setButtonAction(label: label) { [weak self] in
            guard let self else { return }
            if let license = self.check as? LicenseActivationCheck {
                await license.submitLicenseKey(self.field.stringValue)
            } else {
                self.check.performAction()
            }
            await self.validate()
        }
    }

    override func cancelPendingWork() {
        validation?.cancel()
        validation = nil
        permissionRequest?.cancel()
        permissionRequest = nil
        (check as? SetupCheck)?.cancel()
        (check as? WelcomeCheck)?.cancel()
        (check as? LicenseActivationCheck)?.cancelPendingValidation()
    }

    private func validate() async {
        let passed = await check.validate()
        guard !Task.isCancelled else { return }
        if passed { check.status = .success }
        refresh()
    }

    private func refresh() {
        guard isViewLoaded else { return }
        if let setup = check as? SetupCheck {
            status.stringValue = setup.currentTaskName
            progress.doubleValue = setup.progress
        } else if let license = check as? LicenseActivationCheck {
            status.stringValue = license.validationError ?? ""
        } else {
            status.stringValue = check.status == .success ? "Ready" : permissionMessage
        }
        if let permissions = check as? PermissionsCheck {
            for (permission, label) in permissionLabels {
                label.stringValue = permissions.state(for: permission).isGranted ? "Allowed" : "Not allowed"
            }
        }
        let failed: Bool
        if case .failed = check.status { failed = true } else { failed = false }
        if failed { configureAction(label: "Try Again") }
        if check.status == .success { navigator?.resetButton() }
        navigator?.setContinueEnabled(!(check is SetupCheck) || check.status == .success || failed)
    }

    private func request(_ permission: PermissionType, check: PermissionsCheck) {
        permissionRequest?.cancel()
        permissionRequest = Task { [weak self] in
            let result = await check.checker.requestAccess(for: permission)
            guard let self, !Task.isCancelled else { return }
            if case .requiresManualVerification(let message) = result { self.permissionMessage = message }
            await self.validate()
        }
    }
}

@MainActor
private final class CheckActionButton: NSButton {
    private let handler: @MainActor () -> Void
    init(_ title: String, action: @escaping @MainActor () -> Void) {
        handler = action
        super.init(frame: .zero)
        self.title = title
        bezelStyle = .rounded
        target = self
        self.action = #selector(invoke)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
    @objc private func invoke() { handler() }
}
