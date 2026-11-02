import AppKit
import ServiceManagement

@MainActor
final class GeneralSettingsViewController: NSViewController {
    private let loginButton = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let loginStatus = InterfaceControls.label("")
    private let iconButton = NSPopUpButton(frame: .zero, pullsDown: false)
    private let storesIconChoice: Bool
    private let morningDigest: MorningDigest
    private let digestButton = NSButton(checkboxWithTitle: "Send a morning digest at", target: nil, action: nil)
    private let digestTime = NSDatePicker()
    private let weekdaysButton = NSButton(checkboxWithTitle: "On weekdays only", target: nil, action: nil)
    private let digestStatus = InterfaceControls.label("")
    private let quotaAlerts: QuotaAlerts
    private let nudgeThreshold = NSPopUpButton(frame: .zero, pullsDown: false)
    private let runDryButton = NSButton(checkboxWithTitle: "Warn when an account will run out and another has room", target: nil, action: nil)
    private let burnRows = InterfaceControls.stack([], spacing: 6)
    private let burnSetup = InterfaceControls.stack([], spacing: 8)
    private var burnFields: [NSTextField] = []
    private var burnProviders: [NSPopUpButton] = []
    private var copySources: [NSButton: NSTextField] = [:]

    init(storesIconChoice: Bool, morningDigest: MorningDigest, quotaAlerts: QuotaAlerts) {
        self.storesIconChoice = storesIconChoice
        self.morningDigest = morningDigest
        self.quotaAlerts = quotaAlerts
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
        let form = settingsForm([("Startup:", startup), ("App icon:", icon), ("Morning digest:", digestSetup()),
                                 ("Alerts:", alertSetup()), ("Burn list:", burnListSetup()), ("AI assistants:", assistantSetup())])
        form.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        let document = SettingsDocumentView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(form)
        root.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            form.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            form.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            form.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
            form.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -24)
        ])
        refreshLoginState()
        refreshDigestState()
    }

    private func digestSetup() -> NSView {
        morningDigest.onPermissionChange = { [weak self] in self?.refreshDigestState() }
        digestButton.target = self
        digestButton.action = #selector(changeDigest(_:))
        weekdaysButton.target = self
        weekdaysButton.action = #selector(changeDigest(_:))
        digestTime.datePickerStyle = .textFieldAndStepper
        digestTime.datePickerElements = .hourMinute
        digestTime.target = self
        digestTime.action = #selector(changeDigest(_:))
        digestTime.setAccessibilityLabel("Morning digest time")
        let first = NSStackView(views: [digestButton, digestTime])
        first.orientation = .horizontal
        first.alignment = .firstBaseline
        first.spacing = 6
        let note = InterfaceControls.label(
            "A notification with what is left on each account and which to use first. If the Mac is asleep at that time, it comes when the Mac wakes, up to 4 hours later.")
        let setup = InterfaceControls.stack([first, weekdaysButton, note, digestStatus], spacing: 6)
        for view in [note, digestStatus] { view.widthAnchor.constraint(equalTo: setup.widthAnchor).isActive = true }
        return setup
    }

    private func alertSetup() -> NSView {
        nudgeThreshold.addItem(withTitle: "Off")
        for threshold in QuotaAlerts.thresholds { nudgeThreshold.addItem(withTitle: "\(threshold)%") }
        nudgeThreshold.selectItem(at: quotaAlerts.preferences.nudgeThreshold.flatMap { QuotaAlerts.thresholds.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)
        nudgeThreshold.target = self
        nudgeThreshold.action = #selector(changeAlerts(_:))
        nudgeThreshold.setAccessibilityLabel("Nudge when at least this much of a week would reset unused")
        runDryButton.state = quotaAlerts.preferences.warnsRunDry ? .on : .off
        runDryButton.target = self
        runDryButton.action = #selector(changeAlerts(_:))
        let first = NSStackView(views: [InterfaceControls.label("Nudge when at least"), nudgeThreshold,
                                        InterfaceControls.label("of a week would reset unused")])
        first.orientation = .horizontal
        first.alignment = .firstBaseline
        first.spacing = 6
        let note = InterfaceControls.label(
            "Nudges come at most twice per weekly window and four times a week, never between 10 PM and 8 AM. The run-out warning comes once until that quota resets.")
        let setup = InterfaceControls.stack([first, runDryButton, note], spacing: 6)
        note.widthAnchor.constraint(equalTo: setup.widthAnchor).isActive = true
        return setup
    }

    @objc private func changeAlerts(_ sender: Any) {
        var preferences = quotaAlerts.preferences
        let index = nudgeThreshold.indexOfSelectedItem
        preferences.nudgeThreshold = index > 0 ? QuotaAlerts.thresholds[index - 1] : nil
        preferences.warnsRunDry = runDryButton.state == .on
        quotaAlerts.update(preferences)
    }

    private func burnListSetup() -> NSView {
        let add = NSButton(title: "Add Task", target: self, action: #selector(addBurnItem(_:)))
        let note = InterfaceControls.label(
            "Tasks worth spending leftover quota on. A nudge shows the top one for that provider and can copy it. Little Limits never runs it.")
        burnSetup.addArrangedSubview(add)
        burnSetup.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo: burnSetup.widthAnchor).isActive = true
        rebuildBurnRows()
        return burnSetup
    }

    private func rebuildBurnRows() {
        burnRows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        burnFields = []
        burnProviders = []
        for (index, item) in quotaAlerts.preferences.burnList.enumerated() {
            let field = NSTextField(string: item.text)
            field.placeholderString = "Write tests for the history store"
            field.target = self
            field.action = #selector(changeBurnList(_:))
            (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = true
            field.setAccessibilityLabel("Burn list task \(index + 1)")
            let provider = NSPopUpButton(frame: .zero, pullsDown: false)
            provider.addItems(withTitles: ["Either", "Claude", "Codex"])
            provider.selectItem(at: item.provider.map { $0 == .claude ? 1 : 2 } ?? 0)
            provider.target = self
            provider.action = #selector(changeBurnList(_:))
            provider.setAccessibilityLabel("Provider for burn list task \(index + 1)")
            let remove = NSButton(title: "Remove", target: self, action: #selector(removeBurnItem(_:)))
            remove.tag = index
            remove.setAccessibilityLabel("Remove burn list task \(index + 1)")
            let row = NSStackView(views: [field, provider, remove])
            row.orientation = .horizontal
            row.alignment = .firstBaseline
            row.spacing = 6
            field.setContentHuggingPriority(.defaultLow, for: .horizontal)
            burnRows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: burnRows.widthAnchor).isActive = true
            burnFields.append(field)
            burnProviders.append(provider)
        }
        if burnFields.isEmpty, burnRows.superview != nil {
            burnSetup.removeView(burnRows)
        } else if !burnFields.isEmpty, burnRows.superview == nil {
            burnSetup.insertArrangedSubview(burnRows, at: 0)
            burnRows.widthAnchor.constraint(equalTo: burnSetup.widthAnchor).isActive = true
        }
    }

    private func currentBurnList() -> [BurnItem] {
        zip(burnFields, burnProviders).map { field, provider in
            BurnItem(text: field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                     provider: provider.indexOfSelectedItem == 1 ? .claude : provider.indexOfSelectedItem == 2 ? .codex : nil)
        }
    }

    @objc private func changeBurnList(_ sender: Any) {
        var preferences = quotaAlerts.preferences
        preferences.burnList = currentBurnList().filter { !$0.text.isEmpty }
        quotaAlerts.update(preferences)
    }

    @objc private func addBurnItem(_ sender: NSButton) {
        var preferences = quotaAlerts.preferences
        preferences.burnList = currentBurnList().filter { !$0.text.isEmpty } + [BurnItem(text: "", provider: nil)]
        quotaAlerts.update(preferences)
        rebuildBurnRows()
        view.window?.makeFirstResponder(burnFields.last)
    }

    @objc private func removeBurnItem(_ sender: NSButton) {
        var list = currentBurnList()
        guard list.indices.contains(sender.tag) else { return }
        list.remove(at: sender.tag)
        var preferences = quotaAlerts.preferences
        preferences.burnList = list.filter { !$0.text.isEmpty }
        quotaAlerts.update(preferences)
        rebuildBurnRows()
    }

    private func refreshDigestState() {
        let preferences = morningDigest.preferences
        digestButton.state = preferences.isEnabled ? .on : .off
        weekdaysButton.state = preferences.weekdaysOnly ? .on : .off
        weekdaysButton.isEnabled = preferences.isEnabled
        digestTime.isEnabled = preferences.isEnabled
        let calendar = Calendar.current
        digestTime.dateValue = calendar.date(byAdding: .minute, value: preferences.minutesAfterMidnight,
                                             to: calendar.startOfDay(for: Date())) ?? Date()
        digestStatus.stringValue = preferences.isEnabled && morningDigest.permission == .denied
            ? "Notifications are off for Little Limits. Turn them on in System Settings > Notifications." : ""
        digestStatus.isHidden = digestStatus.stringValue.isEmpty
    }

    @objc private func changeDigest(_ sender: Any) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: digestTime.dateValue)
        morningDigest.update(MorningDigest.Preferences(isEnabled: digestButton.state == .on,
                                                       minutesAfterMidnight: (parts.hour ?? 8) * 60 + (parts.minute ?? 0),
                                                       weekdaysOnly: weekdaysButton.state == .on))
        refreshDigestState()
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
        refreshDigestState()
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

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}
