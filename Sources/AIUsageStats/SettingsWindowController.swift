import AppKit
import ServiceManagement

@MainActor
final class SettingsWindowController: NSWindowController {
    private let loginButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let loginStatus = InterfaceControls.label("")
    private var settingsStack: NSStackView?

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        loginButton.target = self
        loginButton.action = #selector(toggleLogin(_:))
        let title = InterfaceControls.label("Startup", size: 13, weight: .semibold)
        loginButton.setAccessibilityLabel("Launch AI Usage Stats at login")
        let refresh = InterfaceControls.label("Usage refreshes every 5 minutes. Manual balances keep their recorded amount and date until you update them.")
        let separator = InterfaceControls.separator()
        let stack = InterfaceControls.stack([title, loginButton, loginStatus, separator, refresh], spacing: 12)
        settingsStack = stack
        if let root = window.contentView {
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
            window.setContentSize(NSSize(width: 420, height: stack.fittingSize.height + 48))
            window.initialFirstResponder = loginButton
            window.recalculateKeyViewLoop()
        }
        window.center()
        refreshLoginState()
    }
    required init?(coder: NSCoder) { nil }

    override func showWindow(_ sender: Any?) {
        refreshLoginState()
        super.showWindow(sender)
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
        if let stack = settingsStack {
            window?.contentView?.layoutSubtreeIfNeeded()
            window?.setContentSize(NSSize(width: 420, height: stack.fittingSize.height + 48))
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
            alert.runModal()
        }
        refreshLoginState()
    }
}
