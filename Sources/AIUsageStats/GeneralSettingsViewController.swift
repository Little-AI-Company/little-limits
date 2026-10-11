import AppKit
import ServiceManagement

@MainActor
final class GeneralSettingsViewController: NSViewController {
    private let loginButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let loginStatus = InterfaceControls.label("")

    init() { super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        view = root
        loginButton.target = self
        loginButton.action = #selector(toggleLogin(_:))
        let title = InterfaceControls.label("Startup", size: 13, weight: .semibold)
        loginButton.setAccessibilityLabel("Launch AI Usage Stats at login")
        let refresh = InterfaceControls.label("Usage refreshes every 5 minutes. Manual balances keep their recorded amount and date until you update them.")
        let separator = InterfaceControls.separator()
        let stack = InterfaceControls.stack([title, loginButton, loginStatus, separator, refresh], spacing: 12)
        do {
            stack.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(stack)
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 24)
            ])
            for component in [loginStatus, separator, refresh] {
                component.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            }
            root.layoutSubtreeIfNeeded()
        }
        refreshLoginState()
    }
    func refresh() {
        _ = view
        refreshLoginState()
    }

    private func refreshLoginState() {
        let state = SMAppService.mainApp.status
        loginButton.state = state == .enabled || state == .requiresApproval ? .on : .off
        switch state {
        case .enabled: loginStatus.stringValue = "AI Usage Stats starts when you log in."
        case .requiresApproval: loginStatus.stringValue = "Allow AI Usage Stats in System Settings → General → Login Items."
        case .notFound, .notRegistered: loginStatus.stringValue = "AI Usage Stats starts when you open it."
        @unknown default: loginStatus.stringValue = "Login item status is unavailable."
        }

    }

    @objc private func toggleLogin(_ sender: NSButton) {
        do {
            if sender.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could Not Change Launch at Login"
            alert.informativeText = error.localizedDescription
            if let window = view.window { alert.beginSheetModal(for: window) }
        }
        refreshLoginState()
    }
}
