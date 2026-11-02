import AppKit
import ServiceManagement

@MainActor
final class GeneralSettingsViewController: NSViewController {
    private let loginButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let loginStatus = InterfaceControls.label("")
    private let iconButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let storesIconChoice: Bool
    private var copySources: [NSButton: NSTextField] = [:]

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
        loginButton.setAccessibilityLabel("Launch Little Limits at login")
        let startup = InterfaceControls.stack([loginButton, loginStatus], spacing: 6)
        loginStatus.widthAnchor.constraint(equalTo: startup.widthAnchor).isActive = true
        let iconNote = InterfaceControls.label(
            "Changes the icon in the Dock and app switcher while a Little Limits window is open, and in About Little Limits. Finder keeps Paper.")
        let icon = InterfaceControls.stack([iconButton, iconNote], spacing: 6)
        iconNote.widthAnchor.constraint(equalTo: icon.widthAnchor).isActive = true
        configureIconButton()
        let form = settingsForm([("Startup:", startup), ("App icon:", icon), ("AI assistants:", assistantSetup())])
        form.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(form)
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
        form.column(at: 0).width = 96
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .fill
        form.rowAlignment = .firstBaseline
        return form
    }

    private func assistantSetup() -> NSView {
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/little-limits").path
        let quoted = "'" + helper.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let note = InterfaceControls.label(
            "Claude Code, Codex and Claude Desktop can read how much of each account is left from Little Limits once you add it with a command below; Little Limits only copies the text and never edits their settings.")
        let entries = [
            copyableCommand(title: "Claude Code", text: "claude mcp add --scope user little-limits -- \(quoted) mcp",
                            accessibilityName: "Claude Code install command"),
            copyableCommand(title: "Codex CLI", text: "codex mcp add little-limits -- \(quoted) mcp",
                            accessibilityName: "Codex CLI install command"),
            copyableCommand(title: "Claude Desktop, paste into claude_desktop_config.json",
                            text: Self.claudeDesktopConfiguration(helper: helper),
                            accessibilityName: "Claude Desktop configuration"),
            copyableCommand(title: "Status table in Terminal", text: "\(quoted) status",
                            accessibilityName: "Terminal status command")
        ]
        let setup = InterfaceControls.stack([note] + entries, spacing: 10)
        for view in [note] + entries { view.widthAnchor.constraint(equalTo: setup.widthAnchor).isActive = true }
        return setup
    }

    private func copyableCommand(title: String, text: String, accessibilityName: String) -> NSView {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        field.textColor = .labelColor
        field.isSelectable = true
        field.lineBreakMode = .byCharWrapping
        field.setContentCompressionResistancePriority(.required, for: .vertical)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setAccessibilityLabel(accessibilityName)
        let copy = NSButton(title: "Copy", target: self, action: #selector(copyCommand(_:)))
        copy.setAccessibilityLabel("Copy \(accessibilityName)")
        copy.setContentHuggingPriority(.required, for: .horizontal)
        copy.setContentCompressionResistancePriority(.required, for: .horizontal)
        copySources[copy] = field
        let row = NSStackView(views: [field, copy])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        let entry = InterfaceControls.stack([InterfaceControls.label(title), row], spacing: 4)
        row.widthAnchor.constraint(equalTo: entry.widthAnchor).isActive = true
        return entry
    }

    private static func claudeDesktopConfiguration(helper: String) -> String {
        struct Server: Encodable { let command: String; let args: [String] }
        struct Configuration: Encodable { let mcpServers: [String: Server] }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let configuration = Configuration(mcpServers: ["little-limits": Server(command: helper, args: ["mcp"])])
        guard let data = try? encoder.encode(configuration) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    @objc private func copyCommand(_ sender: NSButton) {
        guard let text = copySources[sender]?.stringValue else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func configureIconButton() {
        for choice in AppIconChoice.allCases {
            iconButton.addItem(withTitle: choice.title)
            guard let item = iconButton.lastItem else { continue }
            item.representedObject = choice.rawValue
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
        case .enabled: loginStatus.stringValue = "Little Limits starts when you log in."
        case .requiresApproval: loginStatus.stringValue = "Allow Little Limits in System Settings → General → Login Items."
        case .notFound, .notRegistered: loginStatus.stringValue = "Little Limits starts when you open it."
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
