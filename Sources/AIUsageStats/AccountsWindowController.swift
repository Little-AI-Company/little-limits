import AppKit
import UsageCore

@MainActor
final class AccountsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private enum Section: Equatable { case account, settings, platform }
    private let model: ApplicationModel
    private var section = Section.account
    private let detailContainer = NSView()
    private let detailScroll = NSScrollView()
    private let settings = GeneralSettingsViewController()
    private var platform: ClaudePlatformViewController?
    private var accountWindowSize: NSSize?
    private let table = NSTableView()
    private let accountTitle = InterfaceControls.label("", size: 20, weight: .semibold)
    private let attention = InterfaceControls.label("", size: 12)
    private let creditHelp = InterfaceControls.label("", size: 12)
    private let usageReadings = AccountReadingView()
    private let creditReadings = AccountReadingView()
    private let accountActions = NSPopUpButton(frame: .zero, pullsDown: true)
    private let detailsItem = NSMenuItem(title: "Connection Details…", action: #selector(showConnectionDetails(_:)), keyEquivalent: "")
    private let loginItem = NSMenuItem(title: "Sign In Again…", action: #selector(signIn(_:)), keyEquivalent: "")
    private let platformItem = NSMenuItem(title: "Manage Claude Platform…", action: #selector(connectConsole(_:)), keyEquivalent: "")
    private let billingItem = NSMenuItem(title: "Open Billing Dashboard", action: #selector(openBilling(_:)), keyEquivalent: "")
    private let removeItem = NSMenuItem(title: "Remove Account…", action: #selector(removeAccount(_:)), keyEquivalent: "")
    private let addAccountButton = NSPopUpButton(frame: .zero, pullsDown: true)
    private let settingsButton = NSButton(title: "", target: nil, action: nil)
    private let manualDisclosure = NSButton(title: "", target: nil, action: nil)
    private let manualEditor = NSStackView()
    private let manualHelp = InterfaceControls.label("Enter the amount shown in billing. This dated record does not update automatically.")
    private let accountEditor = NSStackView()
    private let emptyState = InterfaceControls.label("Add a Claude or Codex account to view its usage.", size: 13)
    private let accountLoadError = NSStackView()
    private let accountLoadMessage = InterfaceControls.label("", size: 13)
    private let retryAccountLoadButton = NSButton(title: "Retry Loading Accounts", target: nil, action: nil)
    private var displayedProfiles: [AccountProfile] = []
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
    private let recoveryButton = NSButton(title: "Review Access…", target: nil, action: nil)
    private let usageButton = NSButton(title: "Check Usage", target: nil, action: nil)
    var onClaudeConnection: ((UUID?, String) -> Void)?
    private let consoleButton = NSButton(title: "Connect Claude Platform…", target: nil, action: nil)
    var onConsoleConnection: ((UUID) -> Void)?
    var isAccountLoadComplete: () -> Bool = { false }
    var onRetryAccountLoad: (() -> Void)?

    init(model: ApplicationModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 540),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "AI Usage Stats"
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 660, height: 460)
        super.init(window: window)
        window.delegate = self
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
        table.allowsEmptySelection = true
        table.backgroundColor = .clear
        table.setAccessibilityLabel("Accounts")
        let accountScroll = NSScrollView()
        accountScroll.documentView = table
        accountScroll.hasVerticalScroller = true
        accountScroll.autohidesScrollers = true
        accountScroll.drawsBackground = false
        accountScroll.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(accountScroll)

        addAccountButton.addItem(withTitle: "Add Account")
        let addClaude = NSMenuItem(title: "Connect Claude Subscription…", action: #selector(connectClaude(_:)), keyEquivalent: "")
        addClaude.target = self
        let addCodex = NSMenuItem(title: "Connect Codex…", action: #selector(connectCodex(_:)), keyEquivalent: "")
        addCodex.target = self
        addAccountButton.menu?.autoenablesItems = false
        addAccountButton.menu?.addItem(addClaude)
        addAccountButton.menu?.addItem(addCodex)
        addAccountButton.setAccessibilityLabel("Add account")
        addAccountButton.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(addAccountButton)
        settingsButton.target = self
        settingsButton.action = #selector(selectSettings(_:))
        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "App Settings")
        settingsButton.imagePosition = .imageOnly
        settingsButton.bezelStyle = .texturedRounded
        settingsButton.showsBorderOnlyWhileMouseInside = true
        settingsButton.toolTip = "App Settings"
        settingsButton.setAccessibilityLabel("App Settings")
        settingsButton.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(settingsButton)
        let divider = InterfaceControls.separator()
        divider.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(divider)

        usageButton.target = self
        usageButton.action = #selector(checkUsage(_:))
        usageButton.title = "Refresh"
        usageButton.setAccessibilityLabel("Refresh usage for all accounts")
        recoveryButton.target = self
        consoleButton.target = self
        consoleButton.action = #selector(connectConsole(_:))
        accountActions.addItem(withTitle: "Account")
        accountActions.setAccessibilityLabel("Account actions")
        accountActions.menu?.autoenablesItems = false
        for item in [detailsItem, loginItem, platformItem, billingItem] {
            item.target = self
            accountActions.menu?.addItem(item)
        }
        removeItem.target = self
        accountActions.menu?.addItem(.separator())
        accountActions.menu?.addItem(removeItem)
        let headerActions = NSStackView(views: [usageButton, accountActions])
        headerActions.orientation = .horizontal
        headerActions.spacing = 8
        let header = InterfaceControls.stack([accountTitle, headerActions], spacing: 8)
        accountTitle.lineBreakMode = .byTruncatingMiddle
        accountTitle.maximumNumberOfLines = 1
        let attentionRow = NSStackView(views: [attention, recoveryButton])
        attentionRow.orientation = .horizontal
        attentionRow.alignment = .firstBaseline
        attentionRow.spacing = 8
        attentionRow.detachesHiddenViews = true
        attention.setContentHuggingPriority(.defaultLow, for: .horizontal)

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
        accountEditor.orientation = .vertical
        accountEditor.alignment = .leading
        accountEditor.spacing = 12
        accountEditor.detachesHiddenViews = true
        let sections: [NSView] = [
            header, attentionRow,
            InterfaceControls.label("Usage", size: 13, weight: .semibold), usageReadings,
            InterfaceControls.separator(),
            InterfaceControls.label("Credits", size: 13, weight: .semibold), creditReadings,
            consoleButton, creditHelp,
            manualHeading, manualEditor
        ]
        for view in sections {
            accountEditor.addArrangedSubview(view)
            if view !== consoleButton && view !== manualHeading {
                view.widthAnchor.constraint(equalTo: accountEditor.widthAnchor).isActive = true
            }
        }
        accountTitle.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        let detailDocument = AccountDetailDocumentView()
        detailScroll.documentView = detailDocument
        detailScroll.hasVerticalScroller = true
        detailScroll.autohidesScrollers = true
        detailScroll.drawsBackground = false
        detailScroll.translatesAutoresizingMaskIntoConstraints = false
        detailDocument.translatesAutoresizingMaskIntoConstraints = false
        retryAccountLoadButton.target = self
        retryAccountLoadButton.action = #selector(retryAccountLoad(_:))
        accountLoadError.orientation = .vertical
        accountLoadError.alignment = .leading
        accountLoadError.spacing = 12
        let loadErrorTitle = InterfaceControls.label("Accounts Could Not Be Loaded", size: 16, weight: .semibold)
        for component in [loadErrorTitle, accountLoadMessage, retryAccountLoadButton] {
            accountLoadError.addArrangedSubview(component)
        }
        accountLoadMessage.widthAnchor.constraint(equalTo: accountLoadError.widthAnchor).isActive = true
        let detailStack = InterfaceControls.stack([accountEditor, accountLoadError, emptyState, status], spacing: 16)
        detailStack.detachesHiddenViews = true
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        detailDocument.addSubview(detailStack)
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(detailContainer)
        detailContainer.addSubview(detailScroll)
        for view in [accountEditor, accountLoadError, emptyState, status] {
            view.widthAnchor.constraint(equalTo: detailStack.widthAnchor).isActive = true
        }
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 200),
            settingsButton.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12),
            settingsButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            settingsButton.widthAnchor.constraint(equalToConstant: 28),
            settingsButton.heightAnchor.constraint(equalToConstant: 28),
            addAccountButton.bottomAnchor.constraint(equalTo: settingsButton.topAnchor, constant: -12),
            addAccountButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            addAccountButton.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            accountScroll.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 12),
            accountScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            accountScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            accountScroll.bottomAnchor.constraint(equalTo: addAccountButton.topAnchor, constant: -12),
            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            detailContainer.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            detailContainer.topAnchor.constraint(equalTo: root.topAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            detailScroll.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailScroll.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailScroll.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailScroll.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor),
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
        if section == .settings {
            if !model.profiles.contains(where: { $0.id == selectedID }) { selectedID = nil }
            table.deselectAll(nil)
        } else if let selectedID, let index = model.profiles.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else if !model.profiles.isEmpty {
            table.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            selectedID = model.profiles[0].id
        } else { selectedID = nil; table.deselectAll(nil) }
        isUpdatingSelection = false
        if section == .platform, previousID != selectedID { showAccountDetail() }
        if let platform, !model.profiles.contains(where: { $0.id == platform.accountID }) { showAccountDetail() }
        let available = !model.isDemo && !model.isChangingAccounts && !model.isRefreshing
        addAccountButton.isEnabled = available && isAccountLoadComplete() && !model.hasAccountLoadFailure
        status.stringValue = model.isDemo ? "Demo accounts cannot be changed."
            : model.isAllowingKeychainAccess ? "Allowing Keychain access…"
            : model.isSigningInClaude ? "Claude sign-in is in progress."
            : model.isChangingAccounts ? "Updating account…" : ""
        status.isHidden = status.stringValue.isEmpty
        let savedChangeCompleted = editorReloadRevision.map { model.completedAccountChanges >= $0 } ?? false
        if previousID != selectedID || (!model.isChangingAccounts && (editorNeedsReload || savedChangeCompleted)) {
            editorNeedsReload = false
            editorReloadRevision = nil
            renderSelection()
        }
        updateSelectionDescription()
        updateEditorAvailability()
        renderAccountLoadState()
        updateWindowTitle()
    }

    private func renderAccountLoadState() {
        let hasLoadError = model.hasAccountLoadFailure
        accountLoadError.isHidden = !hasLoadError
        accountLoadMessage.stringValue = hasLoadError ? model.message ?? "" : ""
        retryAccountLoadButton.isEnabled = hasLoadError && isAccountLoadComplete() && onRetryAccountLoad != nil
        emptyState.isHidden = !model.profiles.isEmpty || hasLoadError
        emptyState.stringValue = isAccountLoadComplete()
            ? "Add a Claude or Codex account to view its usage."
            : "Loading accounts…"
        window?.recalculateKeyViewLoop()
    }

    @objc private func retryAccountLoad(_ sender: Any?) {
        guard isAccountLoadComplete(), model.hasAccountLoadFailure else { return }
        onRetryAccountLoad?()
    }

    func showAccounts() {
        guard window?.attachedSheet == nil else { return }
        showAccountDetail()
        render()
    }

    func showSettings() {
        guard window?.attachedSheet == nil else { return }
        leavePlatform()
        section = .settings
        detailScroll.isHidden = true
        installDetailView(settings.view)
        settings.refresh()
        isUpdatingSelection = true
        table.deselectAll(nil)
        isUpdatingSelection = false
        updateWindowTitle()
        window?.recalculateKeyViewLoop()
    }

    @objc private func selectSettings(_ sender: Any?) { showSettings() }

    func showPlatform(_ controller: ClaudePlatformViewController, accountID: UUID) {
        guard window?.attachedSheet == nil else { return }
        leavePlatform()
        section = .platform
        selectedID = accountID
        platform = controller
        controller.onBack = { [weak self] in self?.showAccountDetail(); self?.render() }
        if settings.isViewLoaded { settings.view.removeFromSuperview() }
        detailScroll.isHidden = true
        accountWindowSize = window?.contentView?.frame.size
        window?.contentMinSize = NSSize(width: 960, height: 600)
        window?.setContentSize(NSSize(width: max(1000, accountWindowSize?.width ?? 0), height: max(700, accountWindowSize?.height ?? 0)))
        installDetailView(controller.view)
        controller.presentPane()
        render()
        window?.recalculateKeyViewLoop()
    }

    private func installDetailView(_ view: NSView) {
        if view.superview === detailContainer { return }
        view.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            view.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor)
        ])
    }

    private func leavePlatform() {
        platform?.hidePane()
        platform?.onBack = nil
        if let platform, platform.isViewLoaded { platform.view.removeFromSuperview() }
        platform = nil
        if let size = accountWindowSize {
            window?.contentMinSize = NSSize(width: 660, height: 460)
            window?.setContentSize(size)
            accountWindowSize = nil
        }
    }

    private func showAccountDetail() {
        leavePlatform()
        section = .account
        if settings.isViewLoaded { settings.view.removeFromSuperview() }
        detailScroll.isHidden = false
        updateWindowTitle()
        window?.recalculateKeyViewLoop()
    }

    private func updateWindowTitle() {
        let title: String
        if section == .settings { title = "App Settings" }
        else if let profile = model.profiles.first(where: { $0.id == selectedID }) {
            title = "\(InterfaceFormatting.provider(profile.provider)) · \(InterfaceFormatting.accountIdentity(profile))"
        } else { title = "AI Usage Stats" }
        if window?.title != title { window?.title = title }
    }

    func windowWillClose(_ notification: Notification) {
        platform?.hidePane(pauseRefresh: true)
    }

    override func showWindow(_ sender: Any?) {
        if section == .platform { platform?.presentPane() }
        super.showWindow(sender)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { model.profiles.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard model.profiles.indices.contains(row) else { return nil }
        let profile = model.profiles[row]
        let cell = NSTableCellView()
        let name = NSTextField(labelWithString: InterfaceFormatting.accountIdentity(profile))
        name.font = .systemFont(ofSize: 13, weight: .medium)
        name.lineBreakMode = .byTruncatingMiddle
        let providerName = InterfaceFormatting.provider(profile.provider)
        let provider = NSTextField(labelWithString: providerName)
        provider.font = .systemFont(ofSize: 11)
        provider.lineBreakMode = .byTruncatingTail
        let emailUnavailable = InterfaceFormatting.accountEmail(profile) == "Email unavailable"
        let accountDescription = "\(providerName), \(name.stringValue)" + (emailUnavailable ? ". Email unavailable" : "")
        for label in [name, provider] {
            label.toolTip = accountDescription
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
        }
        cell.textField = name
        cell.toolTip = accountDescription
        cell.setAccessibilityLabel(accountDescription)
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
        let accountID = model.profiles.indices.contains(index) ? model.profiles[index].id : nil
        let changedAccount = selectedID != accountID
        showAccountDetail()
        selectedID = accountID
        if changedAccount { renderSelection() }
        updateWindowTitle()
        updateEditorAvailability()
    }

    private func renderSelection() {
        guard let id = selectedID, let profile = model.profiles.first(where: { $0.id == id }) else {
            accountEditor.isHidden = true
            emptyState.isHidden = false
            displayedCredits = []
            recoveryButton.isEnabled = false
            manualCategory.removeAllItems()
            updateManualFields()
            return
        }
        accountEditor.isHidden = false
        emptyState.isHidden = true
        updateSelectionDescription()
        let savedManual = model.manualCredits[id] ?? []
        let pendingManual = model.pendingManualCredits[id] ?? []
        displayedCredits = UsageService.unavailableCredits(for: profile.provider)
            .filter { $0.id == "api_balance" || $0.id == "monthly_grant" }
            .map { fallback in savedManual.first(where: { $0.id == fallback.id })
                ?? pendingManual.first(where: { $0.id == fallback.id }) ?? fallback }
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
        accountActions.isEnabled = selectedID != nil
        loginItem.isEnabled = canSave
        removeItem.isEnabled = canSave
        recoveryButton.isEnabled = canSave
        usageButton.isEnabled = canSave
        usageButton.title = model.isRefreshing ? "Refreshing…" : "Refresh"
        let profile = model.profiles.first(where: { $0.id == selectedID })
        consoleButton.isEnabled = canSave && profile?.provider == .claude
        platformItem.isEnabled = consoleButton.isEnabled
        platformItem.isHidden = profile?.provider != .claude
        detailsItem.isEnabled = selectedID != nil
        billingItem.isEnabled = selectedID != nil
        billingItem.title = monthlyGrantNeedsLink ? "Open Claude Billing" : "Open Billing Dashboard"
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
        updateManualDescription()
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
        updateManualDescription()
    }

    private func updateManualDescription() {
        let index = manualCategory.indexOfSelectedItem
        let needsConfirmation = displayedCredits.indices.contains(index) && selectedID.map { id in
            (model.pendingManualCredits[id] ?? []).contains { $0.id == displayedCredits[index].id }
                && !(model.manualCredits[id] ?? []).contains { $0.id == displayedCredits[index].id }
        } == true
        manualHelp.stringValue = needsConfirmation
            ? "This saved balance came from the earlier unverified connection. Confirm it in billing, then choose Save Balance before it is shown as this account's balance."
            : "Enter the amount shown in billing. This dated record does not update automatically."
    }

    func connect(_ provider: Provider) {
        guard isAccountLoadComplete(), !model.hasAccountLoadFailure,
              !model.isDemo, !model.isChangingAccounts, !model.isRefreshing else { return }
        let alert = NSAlert()
        alert.messageText = provider == .claude ? "Connect Claude Subscription" : "Connect Codex Account"
        alert.informativeText = provider == .claude
            ? "Sign in to your Claude subscription at claude.ai in your browser. This updates subscription usage only. Monthly grants and API balances use a separate Claude Platform sign-in at platform.claude.com."
            : "Creates a separate Codex CLI login for this account and opens Terminal to sign in through the official browser flow. Each account keeps its own login. Your existing CLI login is preserved."
        alert.addButton(withTitle: provider == .claude ? "Sign In…" : "Connect")
        alert.addButton(withTitle: "Cancel")
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn,
                  self.isAccountLoadComplete(), !self.model.hasAccountLoadFailure else { return }
            if provider == .claude { self.onClaudeConnection?(nil, "Claude Account") }
            else { self.model.importAccount(provider: provider, label: "Codex Account") }
        }
    }

    private func updateSelectionDescription() {
        guard let id = selectedID, let profile = model.profiles.first(where: { $0.id == id }) else { return }
        accountTitle.stringValue = "\(InterfaceFormatting.provider(profile.provider)) · \(InterfaceFormatting.accountIdentity(profile))"
        accountTitle.toolTip = accountTitle.stringValue
        loginItem.title = profile.provider == .claude ? "Reconnect Subscription…" : "Sign In Again…"
        let snapshot = model.snapshots[id]
        let now = Date()
        let windows = snapshot?.windows ?? []
        usageReadings.render(windows.isEmpty
            ? [AccountReadingView.Reading(label: "Quota", value: "Unavailable", timing: "", detail: snapshot?.detail ?? "No usage reading yet.")]
            : windows.map { usage in
                AccountReadingView.Reading(label: InterfaceFormatting.usageTitle(usage), value: InterfaceFormatting.used(usage),
                                           timing: usage.isActive == false ? "" : InterfaceFormatting.compactReset(usage.resetsAt, now: now),
                                           detail: "\(usage.title): \(InterfaceFormatting.used(usage)). \(InterfaceFormatting.reset(usage, now: now))")
            })
        let credits = snapshot?.credits ?? UsageService.unavailableCredits(for: profile.provider)
        creditReadings.render(credits.map { credit in
            AccountReadingView.Reading(label: InterfaceFormatting.compactCreditTitle(credit), value: credit.amount == nil && !credit.isUnlimited && credit.status == "available" ? "Unknown" : InterfaceFormatting.credit(credit),
                                       timing: InterfaceFormatting.compactCreditTiming(credit, now: now),
                                       detail: InterfaceFormatting.creditDetail(credit, now: now))
        })
        var message = ""
        recoveryButton.isHidden = true
        if let snapshot {
            switch snapshot.state {
            case .authenticationRequired:
                message = profile.provider == .claude ? "Subscription access required." : "Sign-in required."
                if !windows.isEmpty { message += " Last reading retained." }
                recoveryButton.isHidden = false
                recoveryButton.title = profile.source == .claudeOAuth ? "Review Access…" : "Sign In…"
                recoveryButton.action = profile.source == .claudeOAuth ? #selector(showConnectionDetails(_:)) : #selector(signIn(_:))
            case .unavailable: message = "Usage unavailable."
            case .stale: message = "Last usage reading is stale."
            case .available:
                if snapshot.fetchedAt.map({ now.timeIntervalSince($0) >= 300 }) == true
                    || snapshot.currentWindows.contains(where: { $0.resetsAt.map { $0 <= now } == true }) {
                    message = "Last usage reading is stale."
                } else if snapshot.fetchedAt == nil && !windows.isEmpty { message = "Usage observation time unknown." }
            }
        } else { message = "No usage reading yet." }
        if message.isEmpty && model.consoleMessages[id] != nil { message = "API credits need attention." }
        if message.isEmpty && !(model.pendingManualCredits[id] ?? []).isEmpty { message = "Manual balances need confirmation." }
        attention.stringValue = message
        attention.toolTip = [snapshot?.detail, model.consoleMessages[id]].compactMap { $0 }.joined(separator: "\n")
        attention.isHidden = message.isEmpty
        attention.superview?.isHidden = message.isEmpty
        consoleButton.isHidden = profile.provider != .claude || model.consoleConnections[id] != nil
        consoleButton.title = "Connect API Credits…"
        consoleButton.toolTip = "Sign in separately to Claude Platform at platform.claude.com."
        creditHelp.stringValue = consoleButton.isHidden ? "" : "Uses a separate Claude Platform sign-in."
        creditHelp.isHidden = creditHelp.stringValue.isEmpty
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
        details.append("Verified account email: \(InterfaceFormatting.accountEmail(profile))")
        if let path = profile.sourcePath { details.append("Configuration: \(path)") }
        if let organization = model.consoleConnections[id] { details.append("Claude Console organization: \(organization)") }
        details.append(profile.provider == .claude
            ? (profile.source == .claudeOAuth
               ? "Subscription usage uses this account’s separate browser sign-in. The usage endpoint is experimental. Claude Console API credits use a separate connection."
               : "This older profile reads captured Claude Code quota. Reconnect to enable direct subscription usage. Claude Console API credits use a separate connection.")
            : "This account has a separate Codex CLI login. Your existing CLI login is preserved.")
        if let snapshot = model.snapshots[id] {
            if let date = snapshot.fetchedAt { details.append("Last usage reading: \(InterfaceFormatting.exactDate(date)).") }
            for window in snapshot.windows {
                details.append("\(window.title): \(InterfaceFormatting.used(window)). \(InterfaceFormatting.reset(window)).")
            }
            for credit in snapshot.credits { details.append(InterfaceFormatting.creditDetail(credit)) }
            if let detail = snapshot.detail { details.append(detail) }
        }
        if let message = model.consoleMessages[id] { details.append("API billing: \(message)") }
        alert.informativeText = details.joined(separator: "\n\n")
        alert.addButton(withTitle: "Done")
        let canAllowKeychain = profile.source == .claudeOAuth && !model.isDemo && !model.isChangingAccounts && !model.isRefreshing
        if canAllowKeychain {
            alert.addButton(withTitle: "Allow Keychain Access…")
            alert.informativeText += "\n\nAllow Keychain Access reads this account’s existing saved subscription credential. It may show one macOS permission dialog. It does not start sign-in or replace credentials."
        }
        if let window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if canAllowKeychain, response == .alertSecondButtonReturn { self?.model.allowKeychainAccess(id) }
            }
        }
    }

    @objc private func connectClaude(_ sender: Any?) { connect(.claude) }
    @objc private func connectCodex(_ sender: Any?) { connect(.codex) }
    @objc private func signIn(_ sender: Any?) {
        guard let id = selectedID, let profile = model.profiles.first(where: { $0.id == id }) else { return }
        if profile.provider == .claude { onClaudeConnection?(id, InterfaceFormatting.accountIdentity(profile)) }
        else { model.signInCodex(id) }
    }
    @objc private func checkUsage(_ sender: Any?) { model.refresh() }
    @objc private func connectConsole(_ sender: Any?) {
        guard let id = selectedID else { return }
        onConsoleConnection?(id)
    }
    @objc private func removeAccount(_ sender: Any?) {
        guard let id = selectedID, let profile = model.profiles.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(InterfaceFormatting.provider(profile.provider)) · \(InterfaceFormatting.accountIdentity(profile))?"
        alert.informativeText = "Removes this profile and its saved usage from AI Usage Stats."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        if let window { alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn { self?.model.removeAccount(id) }
        } }
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
    private var monthlyGrantNeedsLink: Bool {
        guard let id = selectedID, model.profiles.first(where: { $0.id == id })?.provider == .claude else { return false }
        return model.snapshots[id]?.credits.contains { $0.id == "monthly_grant" && $0.status == "Not linked" } == true
    }

    @objc private func openBilling(_ sender: Any?) {
        let provider = model.profiles.first(where: { $0.id == selectedID })?.provider
        let address = monthlyGrantNeedsLink ? "https://claude.ai/settings/billing"
            : provider == .claude ? "https://platform.claude.com/settings/billing" : "https://platform.openai.com/settings/organization/billing/overview"
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could Not Save Account"
        alert.informativeText = message
        if let window { alert.beginSheetModal(for: window) }
    }
}

@MainActor
private final class AccountDetailDocumentView: NSView {
    override var isFlipped: Bool { true }
}
