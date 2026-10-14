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
        loginButton.setAccessibilityLabel("Launch AI Usage Stats at login")
        let startup = InterfaceControls.stack([loginButton, loginStatus], spacing: 6)
        loginStatus.widthAnchor.constraint(equalTo: startup.widthAnchor).isActive = true
        let refresh = InterfaceControls.label("Refresh automatically every 5 minutes.", size: 13)
        let manualBalances = InterfaceControls.label("Manual balances keep their recorded amount and date until you update them.")
        let usage = InterfaceControls.stack([refresh, manualBalances], spacing: 8)
        for label in [refresh, manualBalances] {
            label.widthAnchor.constraint(equalTo: usage.widthAnchor).isActive = true
        }
        let startupForm = settingsRow("Startup:", content: startup)
        let usageForm = settingsRow("Usage:", content: usage)
        let separator = InterfaceControls.separator()
        let stack = InterfaceControls.stack([startupForm, separator, usageForm], spacing: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 28)
        ])
        for component in [startupForm, separator, usageForm] {
            component.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        refreshLoginState()
    }

    private func settingsRow(_ title: String, content: NSView) -> NSGridView {
        let label = InterfaceControls.label(title, size: 13)
        let form = NSGridView(views: [[label, content]])
        form.columnSpacing = 12
        form.column(at: 0).width = 72
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .fill
        form.yPlacement = .top
        return form
    }

    func refresh() {
        _ = view
        refreshLoginState()
    }

    func focusInitialControl() {
        _ = view
        view.window?.makeFirstResponder(loginButton)
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
