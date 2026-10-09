import AppKit

@MainActor
final class FunctionalControlGroupView: NSView {
    private let controls: NSStackView
    private var surface: NSView?
    private var usesGlass: Bool?

    init(controls: [NSView]) {
        self.controls = NSStackView(views: controls)
        super.init(frame: .zero)
        self.controls.orientation = .horizontal
        self.controls.spacing = 4
        self.controls.edgeInsets = NSEdgeInsets(top: 4, left: 8, bottom: 4, right: 8)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(displayOptionsChanged(_:)),
                                                        name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        updateSurface()
    }
    required init?(coder: NSCoder) { nil }

    @objc private func displayOptionsChanged(_ notification: Notification) { updateSurface() }

    private func updateSurface() {
        let workspace = NSWorkspace.shared
        var glassAllowed = false
        if #available(macOS 26, *) {
            glassAllowed = !workspace.accessibilityDisplayShouldReduceTransparency
                && !workspace.accessibilityDisplayShouldIncreaseContrast
                && !CommandLine.arguments.contains("--reduce-transparency")
                && !CommandLine.arguments.contains("--increase-contrast")
        }
        guard usesGlass != glassAllowed else { return }
        usesGlass = glassAllowed
        controls.removeFromSuperview()
        surface?.removeFromSuperview()
        let replacement: NSView
        if #available(macOS 26, *), glassAllowed {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 10
            glass.contentView = controls
            replacement = glass
        } else {
            let plain = NSView()
            plain.addSubview(controls)
            replacement = plain
        }
        surface = replacement
        replacement.translatesAutoresizingMaskIntoConstraints = false
        controls.translatesAutoresizingMaskIntoConstraints = false
        addSubview(replacement)
        NSLayoutConstraint.activate([
            replacement.leadingAnchor.constraint(equalTo: leadingAnchor),
            replacement.trailingAnchor.constraint(equalTo: trailingAnchor),
            replacement.topAnchor.constraint(equalTo: topAnchor),
            replacement.bottomAnchor.constraint(equalTo: bottomAnchor),
            controls.leadingAnchor.constraint(equalTo: replacement.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: replacement.trailingAnchor),
            controls.topAnchor.constraint(equalTo: replacement.topAnchor),
            controls.bottomAnchor.constraint(equalTo: replacement.bottomAnchor)
        ])
    }
}
