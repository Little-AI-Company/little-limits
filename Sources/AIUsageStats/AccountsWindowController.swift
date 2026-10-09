import AppKit
import UsageCore

@MainActor
final class AccountsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    private let model: ApplicationModel
    private let table = NSTableView()
    private let nameField = NSTextField(string: "")
    private let accountTitle = InterfaceControls.label("", size: 20, weight: .semibold)
    private let accountDescription = InterfaceControls.label("")
    private let creditDescription = InterfaceControls.label("")
    private let detailsButton = NSButton(title: "Connection Details…", target: nil, action: nil)
    private let billingButton = NSButton(title: "Open Billing Dashboard", target: nil, action: nil)
    private let addAccountButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let manualDisclosure = NSButton(title: "", target: nil, action: nil)
    private let manualEditor = NSStackView()
    private let accountEditor = NSStackView()
    private let emptyState = InterfaceControls.label("Add a Claude or Codex account to view its usage.", size: 13)
    private var displayedProfiles: [AccountProfile] = []
    private var claudeConfigurationURL: URL?
    private let claudeConfigurationField = NSTextField(labelWithString: "")
    private let saveNameButton = NSButton(title: "Save Name", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove Account…", target: nil, action: nil)
    private let manualCategory = NSPopUpButton(frame: .zero, pullsDown: false)
    private let balanceField = NSTextField(string: "")
    private let balanceDate = NSDatePicker()
    private let expiryKnown = NSButton(checkboxWithTitle: "Expiration date known", target: nil, action: nil)
    private let expiryDate = NSDatePicker()
    private let saveBalanceButton = NSButton(title: "Save Balance", target: nil, action: nil)
    private let clearBalanceButton = NSButton(title: "Clear Balance", target: nil, action: nil)
    private let status = InterfaceControls.label("")
    private var selectedID: UUID?
    private var displayedCredits: [CreditBalance] = []
    private var selectedCategoryID: String?
    private var isUpdatingSelection = false
    private var editorNeedsReload = true
    private var editorReloadRevision: Int?
    private let loginButton = NSButton(title: "Sign In Again…", target: nil, action: nil)
    private let consoleButton = NSButton(title: "Connect API Credits…", target: nil, action: nil)
    var onConsoleConnection: ((UUID) -> Void)?

    init(model: ApplicationModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 540),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Accounts"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 660, height: 460)
        super.init(window: window)
        configure()
        window.center()
    }
    required init?(coder: NSCoder) { nil }

    private func configure() {
        guard let root = window?.contentView else { return }
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .followsWindowActiveState
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)

        let accountColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("account"))
        accountColumn.width = 200
        table.addTableColumn(accountColumn)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.style = .sourceList
        table.rowHeight = 48
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.allowsEmptySelection = false
        table.backgroundColor = .clear
        table.setAccessibilityLabel("Connected AI accounts")
        let accountScroll = NSScrollView()
        accountScroll.documentView = table
        accountScroll.hasVerticalScroller = true
        accountScroll.autohidesScrollers = true
        accountScroll.drawsBackground = false
        accountScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(accountScroll)

        addAccountButton.addItem(withTitle: "Add Account")
        let addClaude = NSMenuItem(title: "Connect Claude…", action: #selector(connectClaude(_:)), keyEquivalent: "")
        addClaude.target = self
        let addCodex = NSMenuItem(title: "Connect Codex…", action: #selector(connectCodex(_:)), keyEquivalent: "")
        addCodex.target = self
        addAccountButton.menu?.autoenablesItems = false
        addAccountButton.menu?.addItem(addClaude)
        addAccountButton.menu?.addItem(addCodex)
        addAccountButton.setAccessibilityLabel("Add account")
        addAccountButton.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(addAccountButton)
        let divider = InterfaceControls.separator()
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)

        nameField.placeholderString = "Account name"
        nameField.setAccessibilityLabel("Account name")
        saveNameButton.target = self
        saveNameButton.action = #selector(saveName(_:))
        removeButton.target = self
        removeButton.action = #selector(removeAccount(_:))
        loginButton.target = self
        loginButton.action = #selector(signIn(_:))
        consoleButton.target = self
        consoleButton.action = #selector(connectConsole(_:))
        detailsButton.target = self
        detailsButton.action = #selector(showConnectionDetails(_:))
        billingButton.target = self
        billingButton.action = #selector(openBilling(_:))
        let nameRow = NSStackView(views: [nameField, saveNameButton])
        nameRow.orientation = .horizontal
        nameRow.spacing = 8
        nameField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        let connectionActions = NSStackView(views: [loginButton, detailsButton])
        connectionActions.orientation = .horizontal
        connectionActions.spacing = 8
        connectionActions.detachesHiddenViews = true

        manualCategory.target = self
        manualCategory.action = #selector(selectCredit(_:))
        manualCategory.setAccessibilityLabel("Credit balance category")
        balanceField.placeholderString = "0.00"
        balanceField.setAccessibilityLabel("Manual credit balance")
        balanceField.widthAnchor.constraint(equalToConstant: 130).isActive = true
        balanceDate.datePickerStyle = .textFieldAndStepper
        balanceDate.datePickerElements = [.yearMonthDay, .hourMinute]
        balanceDate.dateValue = Date()
        balanceDate.maxDate = Date()
        balanceDate.setAccessibilityLabel("Balance confirmed date")
        expiryKnown.title = "Set expiration"
        expiryKnown.target = self
        expiryKnown.action = #selector(toggleExpiry(_:))
        expiryDate.datePickerStyle = .textFieldAndStepper
        expiryDate.datePickerElements = [.yearMonthDay, .hourMinute]
        expiryDate.dateValue = Date()
        expiryDate.setAccessibilityLabel("Credit expiration date")
        saveBalanceButton.target = self
        saveBalanceButton.action = #selector(saveBalance(_:))
        clearBalanceButton.target = self
        clearBalanceButton.action = #selector(clearBalance(_:))
        let expiryControls = InterfaceControls.stack([expiryKnown, expiryDate], spacing: 6)
        let form = NSGridView(views: [
            [InterfaceControls.label("Category"), manualCategory],
            [InterfaceControls.label("Amount (USD)"), balanceField],
            [InterfaceControls.label("Confirmed"), balanceDate],
            [InterfaceControls.label("Expires"), expiryControls]
        ])
        form.columnSpacing = 12
        form.rowSpacing = 10
        form.column(at: 0).xPlacement = .trailing
        form.column(at: 1).xPlacement = .leading
        form.rowAlignment = .firstBaseline
        form.cell(atColumnIndex: 0, rowIndex: 3).yPlacement = .top
        let balanceActions = NSStackView(views: [saveBalanceButton, clearBalanceButton])
        balanceActions.orientation = .horizontal
        balanceActions.spacing = 8
        let manualHelp = InterfaceControls.label("Enter the amount shown in billing. This dated record does not update automatically.")
        manualEditor.orientation = .vertical
        manualEditor.alignment = .leading
        manualEditor.spacing = 12
        for view in [manualHelp, form, balanceActions] { manualEditor.addArrangedSubview(view) }
        manualHelp.widthAnchor.constraint(equalTo: manualEditor.widthAnchor).isActive = true
        manualEditor.isHidden = true
        manualDisclosure.bezelStyle = .disclosure
        manualDisclosure.setButtonType(.onOff)
        manualDisclosure.target = self
        manualDisclosure.action = #selector(toggleManualEditor(_:))
        manualDisclosure.setAccessibilityLabel("Show manual balance editor")
        let manualHeading = NSStackView(views: [manualDisclosure, InterfaceControls.label("Manual balance", size: 13)])
        manualHeading.orientation = .horizontal
        manualHeading.spacing = 6
        let creditActions = NSStackView(views: [consoleButton, billingButton])
        creditActions.orientation = .vertical
        creditActions.alignment = .leading
        creditActions.spacing = 8
        creditActions.detachesHiddenViews = true
        accountEditor.orientation = .vertical
        accountEditor.alignment = .leading
        accountEditor.spacing = 12
        accountEditor.detachesHiddenViews = true
        let sections: [NSView] = [
            accountTitle,
            InterfaceControls.label("Name", size: 13, weight: .semibold), nameRow,
            InterfaceControls.separator(),
            InterfaceControls.label("Connection", size: 13, weight: .semibold), accountDescription, connectionActions,
            InterfaceControls.separator(),
            InterfaceControls.label("API Credits", size: 13, weight: .semibold), creditDescription, creditActions,
            manualHeading, manualEditor,
            InterfaceControls.separator(), removeButton
        ]
        for view in sections { accountEditor.addArrangedSubview(view) }
        for view in sections where view is NSTextField || view is NSBox || view === nameRow || view === manualEditor {
            view.widthAnchor.constraint(equalTo: accountEditor.widthAnchor).isActive = true
        }
        let detailDocument = AccountDetailDocumentView()
        let detailScroll = NSScrollView()
        detailScroll.documentView = detailDocument
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.drawsBackground = false
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        detailDocument.translatesAutoresizingMaskIntoConstraints = false
        let detailStack = InterfaceControls.stack([accountEditor, emptyState, status], spacing: 16)
        detailStack.detachesHiddenViews = true
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailDocument.addSubview(detailStack)
        root.addSubview(detailScroll)
        for view in [accountEditor, emptyState, status] {
            view.widthAnchor.constraint(equalTo: detailStack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 200),
            addAccountButton.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 16),
            addAccountButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            addAccountButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            accountScroll.topAnchor.constraint(equalTo: addAccountButton.bottomAnchor, constant: 12),
            accountScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            accountScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            accountScroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            detailScroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            detailScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            detailScroll.topAnchor.constraint(equalTo: root.topAnchor),
            detailScroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            detailDocument.widthAnchor.constraint(equalTo: detailScroll.contentView.widthAnchor),
            detailStack.topAnchor.constraint(equalTo: detailDocument.topAnchor, constant: 22),
            detailStack.leadingAnchor.constraint(equalTo: detailDocument.leadingAnchor, constant: 24),
            detailStack.trailingAnchor.constraint(equalTo: detailDocument.trailingAnchor, constant: -24),
            detailStack.bottomAnchor.constraint(equalTo: detailDocument.bottomAnchor, constant: -22)
        ])
        window?.initialFirstResponder = table
        window?.recalculateKeyViewLoop()
        render()
    }

    func render() {
        let previousID = selectedID
        isUpdatingSelection = true
        if displayedProfiles != model.profiles {
            displayedProfiles = model.profiles
            table.reloadData()
        }
        if let selectedID, let index = model.profiles.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !model.profiles.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            selectedID = model.profiles[0].id
        } else { selectedID = nil }
        isUpdatingSelection = false
        let available = !model.isDemo && !model.isChangingAccounts && !model.isRefreshing
        addAccountButton.isEnabled = available
        saveNameButton.isEnabled = available && selectedID != nil
        removeButton.isEnabled = available && selectedID != nil
        status.stringValue = model.isDemo ? "Demo accounts cannot be changed." : model.isChangingAccounts ? "Saving account…" : ""
        status.isHidden = status.stringValue.isEmpty
        let savedChangeCompleted = editorReloadRevision.map { model.completedAccountChanges >= $0 } ?? false
        if previousID != selectedID || (!model.isChangingAccounts && (editorNeedsReload || savedChangeCompleted)) {
            editorNeedsReload = false
            editorReloadRevision = nil
            renderSelection()
        }
        updateSelectionDescription()
        updateEditorAvailability()
    }

    func numberOfRows(in tableView: NSTableView) -> Int { model.profiles.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard model.profiles.indices.contains(row) else { return nil }
        let profile = model.profiles[row]
        let cell = NSTableCellView()
        let name = NSTextField(labelWithString: profile.label)
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingTail
        let provider = NSTextField(labelWithString: InterfaceFormatting.provider(profile.provider))
        provider.font = .systemFont(ofSize: 11)
        provider.textColor = .secondaryLabelColor
        for label in [name, provider] {
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
        }
        cell.textField = name
        cell.setAccessibilityLabel("\(profile.label), \(InterfaceFormatting.provider(profile.provider))")
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            name.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            name.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
            provider.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            provider.trailingAnchor.constraint(equalTo: name.trailingAnchor),
            provider.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 3)
        ])
        return cell
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection else { return }
        let index = table.selectedRow
        selectedID = model.profiles.indices.contains(index) ? model.profiles[index].id : nil
        renderSelection()
        updateEditorAvailability()
    }

    private func renderSelection() {
        guard let id = selectedID, let profile = model.profiles.first(where: { $0.id == id }) else {
            nameField.stringValue = ""
            accountEditor.isHidden = true
            emptyState.isHidden = false
            displayedCredits = []
            loginButton.isEnabled = false
            manualCategory.removeAllItems()
            updateManualFields()
            return
        }
        accountEditor.isHidden = false
        emptyState.isHidden = true
        nameField.stringValue = profile.label
        updateSelectionDescription()
        let savedManual = model.manualCredits[id] ?? []
        displayedCredits = UsageService.unavailableCredits(for: profile.provider)
            .filter { $0.id == "api_balance" || $0.id == "monthly_grant" }
            .map { fallback in savedManual.first(where: { $0.id == fallback.id }) ?? fallback }
        loginButton.isEnabled = profile.provider == .codex && !model.isDemo && !model.isChangingAccounts && !model.isRefreshing
        manualCategory.removeAllItems()
        manualCategory.addItems(withTitles: displayedCredits.map(\.title))
        if let selectedCategoryID, let index = displayedCredits.firstIndex(where: { $0.id == selectedCategoryID }) {
            manualCategory.selectItem(at: index)
        }
        updateManualFields()
    }

    private func updateEditorAvailability() {
        let editable = !model.isDemo && selectedID != nil
        let canSave = editable && !model.isRefreshing && !model.isChangingAccounts
        nameField.isEnabled = editable
        saveNameButton.isEnabled = canSave
        removeButton.isEnabled = canSave
        loginButton.isEnabled = canSave && model.profiles.first(where: { $0.id == selectedID })?.provider == .codex
        consoleButton.isEnabled = canSave && model.profiles.first(where: { $0.id == selectedID })?.provider == .claude
        consoleButton.title = selectedID.flatMap { model.consoleConnections[$0] } == nil ? "Connect API Credits…" : "Manage API Credits…"
        detailsButton.isEnabled = selectedID != nil
        billingButton.isEnabled = selectedID != nil
        manualDisclosure.isEnabled = selectedID != nil
        let index = manualCategory.indexOfSelectedItem
        let hasCredit = displayedCredits.indices.contains(index)
        manualCategory.isEnabled = editable && hasCredit
        balanceField.isEnabled = editable && hasCredit
        balanceDate.isEnabled = editable && hasCredit
        expiryKnown.isEnabled = editable && hasCredit
        expiryDate.isEnabled = editable && hasCredit && expiryKnown.state == .on
        saveBalanceButton.isEnabled = canSave && hasCredit
        clearBalanceButton.isEnabled = canSave && hasCredit && displayedCredits[index].source == .manual
    }

    private func updateManualFields() {
        let index = manualCategory.indexOfSelectedItem
        guard displayedCredits.indices.contains(index) else {
            balanceField.stringValue = ""
            balanceField.isEnabled = false
            saveBalanceButton.isEnabled = false
            clearBalanceButton.isEnabled = false
            balanceDate.isEnabled = false
            expiryKnown.isEnabled = false
            expiryDate.isEnabled = false
            return
        }
        let credit = displayedCredits[index]
        selectedCategoryID = credit.id
        balanceField.stringValue = credit.amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
        balanceDate.dateValue = credit.asOf ?? Date()
        balanceDate.maxDate = Date()
        expiryKnown.state = credit.expiresAt == nil ? .off : .on
        expiryDate.dateValue = credit.expiresAt ?? Date()
        let available = !model.isDemo && !model.isRefreshing && !model.isChangingAccounts
        balanceField.isEnabled = available
        balanceDate.isEnabled = available
        expiryKnown.isEnabled = available
        expiryDate.isEnabled = available && expiryKnown.state == .on
        saveBalanceButton.isEnabled = available
        clearBalanceButton.isEnabled = available && credit.source == .manual && credit.amount != nil
    }

    func connect(_ provider: Provider) {
        guard !model.isDemo else { return }
        let alert = NSAlert()
        alert.messageText = "Connect \(InterfaceFormatting.provider(provider)) Account"
        if provider == .claude {
            alert.informativeText = "Connects Claude Code from the folder below. Quota reporting is added to its status line and your existing output is preserved. Usage appears after your next Claude response. Choose a different configuration folder to connect another account."
        } else {
            alert.informativeText = "Creates a separate Codex CLI login for this account and opens Terminal to sign in through the official browser flow. Each account keeps its own login. Your existing CLI login is preserved."
        }
        let field = NSTextField(string: "\(InterfaceFormatting.provider(provider)) Account")
        field.setAccessibilityLabel("New account name")
        if provider == .claude {
            let configurationPath = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory() + "/.claude"
            claudeConfigurationURL = URL(fileURLWithPath: configurationPath).standardizedFileURL
            updateClaudeConfigurationField()
            claudeConfigurationField.setAccessibilityLabel("Claude Code configuration folder")
            claudeConfigurationField.lineBreakMode = .byTruncatingMiddle
            claudeConfigurationField.isSelectable = true
            let chooseFolder = NSButton(title: "Choose Folder…", target: self, action: #selector(chooseClaudeConfiguration(_:)))
            let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 100))
            let nameLabel = NSTextField(labelWithString: "Name")
            let folderLabel = NSTextField(labelWithString: "Folder")
            let accessoryControls: [NSView] = [nameLabel, field, folderLabel, claudeConfigurationField, chooseFolder]
            for view in accessoryControls {
                view.translatesAutoresizingMaskIntoConstraints = false
                accessory.addSubview(view)
            }
            NSLayoutConstraint.activate([
                nameLabel.leadingAnchor.constraint(equalTo: accessory.leadingAnchor),
                nameLabel.topAnchor.constraint(equalTo: accessory.topAnchor, constant: 8),
                field.leadingAnchor.constraint(equalTo: accessory.leadingAnchor, constant: 58),
                field.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
                field.firstBaselineAnchor.constraint(equalTo: nameLabel.firstBaselineAnchor),
                folderLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
                folderLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 20),
                claudeConfigurationField.leadingAnchor.constraint(equalTo: field.leadingAnchor),
                claudeConfigurationField.trailingAnchor.constraint(equalTo: accessory.trailingAnchor),
                claudeConfigurationField.firstBaselineAnchor.constraint(equalTo: folderLabel.firstBaselineAnchor),
                chooseFolder.leadingAnchor.constraint(equalTo: field.leadingAnchor),
                chooseFolder.topAnchor.constraint(equalTo: claudeConfigurationField.bottomAnchor, constant: 8)
            ])
            alert.accessoryView = accessory
        } else {
            field.frame = NSRect(x: 0, y: 0, width: 320, height: 24)
            alert.accessoryView = field
        }
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        if alert.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { showError("Enter an account name."); return }
            if provider == .claude {
                var isDirectory: ObjCBool = false
                guard let url = claudeConfigurationURL,
                      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      isDirectory.boolValue else {
                    showError("The Claude Code configuration folder does not exist. Choose an existing folder, then connect again.")
                    return
                }
                model.importAccount(provider: provider, label: name, configurationURL: url)
            } else { model.importAccount(provider: provider, label: name) }
        }
    }

    @objc private func chooseClaudeConfiguration(_ sender: Any?) {
        let picker = NSOpenPanel()
        picker.title = "Choose Claude Code Configuration"
        picker.message = "Choose the Claude configuration folder for this account."
        picker.canChooseFiles = false
        picker.canChooseDirectories = true
        picker.canCreateDirectories = false
        picker.showsHiddenFiles = true
        picker.directoryURL = claudeConfigurationURL
        picker.prompt = "Choose Folder"
        if picker.runModal() == .OK, let url = picker.url {
            claudeConfigurationURL = url
            updateClaudeConfigurationField()
        }
    }

    private func updateClaudeConfigurationField() {
        claudeConfigurationField.stringValue = claudeConfigurationURL.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "Choose a configuration folder"
        claudeConfigurationField.toolTip = claudeConfigurationURL?.path
    }

    private func updateSelectionDescription() {
        guard let id = selectedID, let profile = model.profiles.first(where: { $0.id == id }) else { return }
        accountTitle.stringValue = InterfaceFormatting.provider(profile.provider)
        loginButton.isHidden = profile.provider != .codex
        consoleButton.isHidden = profile.provider != .claude
        let state = model.snapshots[id]?.state
        if model.isDemo {
            accountDescription.stringValue = "Example account. Connect your own account to receive readings."
        } else if state == .authenticationRequired {
            accountDescription.stringValue = profile.provider == .codex
                ? "Sign in again to restore usage readings."
                : "Sign in through Claude Code to restore usage readings."
        } else {
            accountDescription.stringValue = profile.provider == .claude
                ? "Usage comes from Claude Code after a response."
                : "Usage comes from this account’s separate Codex login."
        }
        creditDescription.stringValue = profile.provider == .claude
            ? (model.consoleConnections[id] == nil
               ? "Connect Claude Console to read credits. This connection is experimental."
               : "Claude Console is linked to this account. This connection is experimental.")
            : "View API billing or enter a dated balance manually."
    }

    @objc private func toggleManualEditor(_ sender: NSButton) {
        manualEditor.isHidden = sender.state != .on
        sender.setAccessibilityLabel(sender.state == .on ? "Hide manual balance editor" : "Show manual balance editor")
        window?.recalculateKeyViewLoop()
    }

    @objc private func showConnectionDetails(_ sender: Any?) {
        guard let id = selectedID, let profile = model.profiles.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "\(InterfaceFormatting.provider(profile.provider)) Connection"
        var details = ["Account identity: \(profile.providerAccountID ?? "Unavailable")"]
        if let path = profile.sourcePath { details.append("Configuration: \(path)") }
        if let organization = model.consoleConnections[id] { details.append("Claude Console organization: \(organization)") }
        details.append(profile.provider == .claude
            ? "Claude Code reports quota through its status line. Your existing status line output is preserved. The experimental Claude Console session is separate from Claude Code."
            : "This account has a separate Codex CLI login. Your existing CLI login is preserved.")
        alert.informativeText = details.joined(separator: "\n\n")
        alert.addButton(withTitle: "Done")
        alert.runModal()
    }

    @objc private func connectClaude(_ sender: Any?) { connect(.claude) }
    @objc private func connectCodex(_ sender: Any?) { connect(.codex) }
    @objc private func signIn(_ sender: Any?) {
        guard let id = selectedID else { return }
        model.signInCodex(id)
    }
    @objc private func connectConsole(_ sender: Any?) {
        guard let id = selectedID else { return }
        onConsoleConnection?(id)
    }
    @objc private func saveName(_ sender: Any?) {
        guard let id = selectedID else { return }
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { showError("Enter an account name."); return }
        editorReloadRevision = model.completedAccountChanges + 1
        model.renameAccount(id, label: name)
    }
    @objc private func removeAccount(_ sender: Any?) {
        guard let id = selectedID, let profile = model.profiles.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(profile.label)?"
        alert.informativeText = "Removes this profile and its saved usage from AI Usage Stats."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { model.removeAccount(id) }
    }
    @objc private func selectCredit(_ sender: Any?) {
        if displayedCredits.indices.contains(manualCategory.indexOfSelectedItem) {
            selectedCategoryID = displayedCredits[manualCategory.indexOfSelectedItem].id
        }
        updateManualFields()
    }
    @objc private func toggleExpiry(_ sender: Any?) { expiryDate.isEnabled = expiryKnown.state == .on }
    @objc private func saveBalance(_ sender: Any?) {
        guard let id = selectedID, displayedCredits.indices.contains(manualCategory.indexOfSelectedItem) else { return }
        let original = displayedCredits[manualCategory.indexOfSelectedItem]
        let scanner = Scanner(string: balanceField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        scanner.locale = Locale.current
        scanner.charactersToBeSkipped = nil
        guard let amount = scanner.scanDecimal(), scanner.isAtEnd, amount >= 0 else {
            showError("Enter a balance of zero or greater, without a currency symbol.")
            return
        }
        let credit = CreditBalance(id: original.id, title: original.title, amount: amount,
                                   unit: original.unit, expiresAt: expiryKnown.state == .on ? expiryDate.dateValue : nil,
                                   source: .manual, asOf: balanceDate.dateValue,
                                   detail: "Entered manually from the billing dashboard.")
        editorReloadRevision = model.completedAccountChanges + 1
        model.setManualCredit(accountID: id, credit: credit)
    }
    @objc private func clearBalance(_ sender: Any?) {
        guard let id = selectedID, displayedCredits.indices.contains(manualCategory.indexOfSelectedItem) else { return }
        let original = displayedCredits[manualCategory.indexOfSelectedItem]
        let credit = CreditBalance(id: original.id, title: original.title, amount: nil, unit: original.unit, source: .manual)
        editorReloadRevision = model.completedAccountChanges + 1
        model.setManualCredit(accountID: id, credit: credit)
    }
    @objc private func openBilling(_ sender: Any?) {
        let provider = model.profiles.first(where: { $0.id == selectedID })?.provider
        let address = provider == .claude ? "https://platform.claude.com/settings/billing" : "https://platform.openai.com/settings/organization/billing/overview"
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could Not Save Account"
        alert.informativeText = message
        alert.runModal()
    }
}

@MainActor
private final class AccountDetailDocumentView: NSView {
    override var isFlipped: Bool { true }
}
