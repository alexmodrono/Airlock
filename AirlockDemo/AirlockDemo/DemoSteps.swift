import AppKit
import Airlock

/// Crono's compact welcome and grouped preference composition, in AppKit.
@MainActor
class DemoContentController: AirlockStepViewController {
    let stack = NSStackView()
    var centersContent: Bool { false }

    override func loadView() {
        view = NSView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 22
        view.addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(greaterThanOrEqualTo: view.topAnchor),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor)
        ])
        if centersContent { stack.centerYAnchor.constraint(equalTo: view.centerYAnchor).isActive = true }
        else { stack.topAnchor.constraint(equalTo: view.topAnchor).isActive = true }
        configureContent()
    }

    func configureContent() {}

    func add(_ child: NSView) {
        stack.addArrangedSubview(child)
        child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    func header(_ title: String, detail: String, centered: Bool = false) {
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = centered ? .centerX : .leading
        column.spacing = 6
        let heading = label(title, size: centered ? 28 : 22, weight: .semibold)
        let description = label(detail, size: 13, secondary: true)
        for field in [heading, description] {
            field.alignment = centered ? .center : .left
            column.addArrangedSubview(field)
            field.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true
        }
        add(column)
    }

    func symbol(_ name: String, size: CGFloat) -> NSImageView {
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: size, weight: .light))
        image.imageScaling = .scaleProportionallyUpOrDown
        image.contentTintColor = .controlAccentColor
        image.setAccessibilityElement(false)
        return image
    }

    func label(_ text: String, size: CGFloat, weight: NSFont.Weight = .regular, secondary: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight)
        field.textColor = secondary ? .secondaryLabelColor : .labelColor
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func feature(_ icon: String, title: String, detail: String) -> NSView {
        let image = symbol(icon, size: 22)
        let words = NSStackView(views: [label(title, size: 13, weight: .semibold), label(detail, size: 13, secondary: true)])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 2
        let row = NSStackView(views: [image, words])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 14
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 30),
            image.heightAnchor.constraint(equalToConstant: 28),
            words.widthAnchor.constraint(equalTo: row.widthAnchor, constant: -44)
        ])
        for child in words.arrangedSubviews { child.widthAnchor.constraint(equalTo: words.widthAnchor).isActive = true }
        return row
    }
}

final class DemoWelcomeController: DemoContentController {
    override var centersContent: Bool { true }

    override func configureContent() {
        let icon = symbol("door.left.hand.open", size: 52)
        let iconRow = NSView()
        iconRow.addSubview(icon)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconRow.heightAnchor.constraint(equalToConstant: 80),
            icon.widthAnchor.constraint(equalToConstant: 80),
            icon.heightAnchor.constraint(equalToConstant: 80),
            icon.centerXAnchor.constraint(equalTo: iconRow.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: iconRow.centerYAnchor)
        ])
        add(iconRow)
        header("Welcome to Airlock", detail: "A guided start for your Mac app, from the first hello to the final setup step.", centered: true)
        let features = NSStackView(views: [
            feature("hand.wave", title: "Start with a hello", detail: "A familiar greeting and startup sound welcome people in."),
            feature("slider.horizontal.3", title: "Choose what matters", detail: "Group permissions and preferences into focused steps."),
            feature("arrow.left.arrow.right", title: "Move at your own pace", detail: "Return to available steps using the navigation above.")
        ])
        features.orientation = .vertical
        features.alignment = .leading
        features.spacing = 14
        add(features)
        for row in features.arrangedSubviews { row.widthAnchor.constraint(equalTo: features.widthAnchor).isActive = true }
    }
}

final class DemoPreferencesController: DemoContentController {
    override func configureContent() {
        header("Preferences", detail: "These sample choices stay in this demo.")
        let controls = NSStackView()
        controls.orientation = .vertical
        controls.alignment = .leading
        controls.spacing = 16
        controls.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        for title in ["Open at login", "Check for updates"] {
            let toggle = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            toggle.controlSize = .large
            controls.addArrangedSubview(toggle)
        }
        let group = NSBox()
        group.boxType = .custom
        group.borderWidth = 0
        group.fillColor = .windowBackgroundColor.blended(withFraction: 0.045, of: .labelColor) ?? .controlBackgroundColor
        group.cornerRadius = 10
        group.contentViewMargins = .zero
        group.contentView = controls
        add(group)
        group.heightAnchor.constraint(equalTo: controls.heightAnchor).isActive = true
    }
}

final class DemoReadyController: DemoContentController {
    override var centersContent: Bool { true }

    override func configureContent() {
        let icon = symbol("checkmark.circle", size: 64)
        icon.heightAnchor.constraint(equalToConstant: 80).isActive = true
        add(icon)
        header("You're ready", detail: "Your sample preferences are ready.", centered: true)
    }
}
