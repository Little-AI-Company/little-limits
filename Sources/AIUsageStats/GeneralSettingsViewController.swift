import AppKit
import ServiceManagement

@MainActor
final class GeneralSettingsViewController: NSViewController {
    private let loginButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let loginStatus = InterfaceControls.label("")
    private let iconButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let storesIconChoice: Bool

    /// Demo sessions show the chosen icon but do not save it.
    init(storesIconChoice: Bool) {
        self.storesIconChoice = storesIconChoice
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        view = root
        loginButton.target = self
        loginButton.action = #selector(toggleLogin(_:))
        loginButton.setAccessibilityLabel("Launch Limits Left at login")
        let startup = InterfaceControls.stack([loginButton, loginStatus], spacing: 6)
        loginStatus.widthAnchor.constraint(equalTo: startup.widthAnchor).isActive = true
        let iconNote = InterfaceControls.label(
            "Changes the icon in the Dock and app switcher while a Limits Left window is open, and in About Limits Left. Finder keeps Enamel.")
        let icon = InterfaceControls.stack([iconButton, iconNote], spacing: 6)
        iconNote.widthAnchor.constraint(equalTo: icon.widthAnchor).isActive = true
        configureIconButton()
        let form = settingsForm([("Startup:", startup), ("App icon:", icon)])
        form.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(form)
        // The page sits under the window toolbar; start below it.
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 24),
            form.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -24),
            form.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor, constant: 24)
        ])
        refreshLoginState()
    }

    private func settingsForm(_ rows: [(title: String, content: NSView)]) -> NSGridView {
        let form = NSGridView(views: rows.map { [InterfaceControls.label($0.title, size: 13), $0.content] })
        form.columnSpacing = 12
        form.rowSpacing = 20
        form.column(at: 0).width = 72
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .fill
        form.yPlacement = .top
        return form
    }

    private func configureIconButton() {
        for choice in AppIconChoice.allCases {
            iconButton.addItem(withTitle: choice.title)
            guard let item = iconButton.lastItem else { continue }
            item.representedObject = choice.rawValue
            // A copy, so resizing the menu image leaves the full-size icon untouched.
            if let image = choice.image(in: .main)?.copy() as? NSImage {
                image.size = NSSize(width: 16, height: 16)
                item.image = image
            }
        }
        iconButton.selectItem(at: AppIconChoice.allCases.firstIndex(of: AppIconChoice(defaults: .standard)) ?? 0)
        iconButton.target = self
        iconButton.action = #selector(chooseIcon(_:))
        iconButton.setAccessibilityLabel("App icon")
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
        case .enabled: loginStatus.stringValue = "Limits Left starts when you log in."
        case .requiresApproval: loginStatus.stringValue = "Allow Limits Left in System Settings → General → Login Items."
        case .notFound, .notRegistered: loginStatus.stringValue = "Limits Left starts when you open it."
        @unknown default: loginStatus.stringValue = "Login item status is unavailable."
        }
    }

    @objc private func chooseIcon(_ sender: NSPopUpButton) {
        guard let choice = (sender.selectedItem?.representedObject as? String).flatMap(AppIconChoice.init(rawValue:)) else { return }
        if storesIconChoice { UserDefaults.standard.set(choice.rawValue, forKey: AppIconChoice.defaultsKey) }
        choice.apply()
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
