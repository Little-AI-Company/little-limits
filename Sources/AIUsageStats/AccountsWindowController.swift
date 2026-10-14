import AppKit
import UsageCore

@MainActor
final class AccountsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate {
    private enum Section: Equatable { case home, account, settings, platform }
    private enum WindowSurface: Equatable { case home, account, platform }
    private struct WindowSizeLimits {
        var minimum: NSSize
        var maximum: NSSize
    }
    private static let homeRow = 0
    private static let accountRowOffset = 1
    private static let accountWindowMinimumSize = NSSize(width: 660, height: 460)
    private static let accountWindowMaximumSize = NSSize(width: 960, height: 760)
    private static let accountWindowDefaultSize = NSSize(width: 700, height: 540)
    // Seven calendar columns plus the account table. The range stays resizable;
    // account, settings, and Platform keep their own limits.
    private static let homeWindowMinimumSize = NSSize(width: 1020, height: 640)
    private static let homeWindowMaximumSize = NSSize(width: 1680, height: 1040)
    private static let homeWindowDefaultSize = NSSize(width: 1280, height: 780)
    private static let platformWindowMinimumSize = NSSize(width: 960, height: 600)
    private static let platformWindowMaximumSize = NSSize(width: 1280, height: 900)
    private static let platformWindowDefaultSize = NSSize(width: 1000, height: 700)
    // Source-list insets leave the identity label about 52 points narrower than the sidebar.
    // 228 points keeps personal@example.invalid on one line. Longer identities wrap to two.
    private static let sidebarWidth: CGFloat = 228
    private let model: ApplicationModel
    private let home: HomeViewController
    private var section = Section.home
    private let detailContainer = NSView()
    private let detailScroll = NSScrollView()
    private let settings = GeneralSettingsViewController()
    private var platform: ClaudePlatformViewController?
    private var homeWindowSize = AccountsWindowController.homeWindowDefaultSize
    private var accountWindowSize = AccountsWindowController.accountWindowDefaultSize
    private var platformWindowSize: NSSize?
    private var isApplyingWindowSize = false
    private let table = AccountSidebarTableView()
    private let accountTitle = InterfaceControls.label("", size: 20, weight: .semibold)
    private let attention = InterfaceControls.label("", size: 12)
    private let creditHelp = InterfaceControls.label("", size: 12)
    private let usageReadings = AccountReadingView()
    private let creditReadings = AccountReadingView()
    private let accountActions = NSPopUpButton(frame: .zero, pullsDown: true)
    private let detailsItem = NSMenuItem(title: "Details…", action: #selector(showConnectionDetails(_:)), keyEquivalent: "")
    private let reconnectItem = NSMenuItem(title: "Reconnect…", action: #selector(signIn(_:)), keyEquivalent: "")
    private let billingItem = NSMenuItem(title: "Billing…", action: #selector(openBilling(_:)), keyEquivalent: "")
    private let creditsItem = NSMenuItem(title: "API Credits…", action: #selector(connectConsole(_:)), keyEquivalent: "")
    private let removeAccountItem = NSMenuItem(title: "Remove Account…", action: #selector(removeSelectedAccountFromActions(_:)), keyEquivalent: "")
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
    private var sidebarDisplays: [UUID: AccountSidebarCellView.Display] = [:]
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
    private let consoleButton = NSButton(title: "Connect API Credits…", target: nil, action: nil)
    var onConsoleConnection: ((UUID) -> Void)?
    var isAccountLoadComplete: () -> Bool = { false }
    var onRetryAccountLoad: (() -> Void)?

    init(model: ApplicationModel) {
        self.model = model
        self.home = HomeViewController(model: model)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.homeWindowDefaultSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "AI Usage Stats"
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.homeWindowMinimumSize
        window.contentMaxSize = Self.homeWindowMaximumSize
        super.init(window: window)
        window.delegate = self
        configure()
        window.center()
    }
    required init?(coder: NSCoder) { nil }

    private func configure() {
        home.onViewAccount = { [weak self] id in self?.showAccount(id: id) }
        home.onReconnectAccount = { [weak self] id in self?.reconnectAccount(id: id) }
        home.onRetryAccountLoad = { [weak self] in self?.onRetryAccountLoad?() }
        home.isAccountLoadComplete = { [weak self] in self?.isAccountLoadComplete() ?? false }
        guard let root = window?.contentView else { return }
        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        sidebar.state = .followsWindowActiveState
        sidebar.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(sidebar)

        let accountColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("account"))
        accountColumn.resizingMask = .autoresizingMask
        table.addTableColumn(accountColumn)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.autoresizingMask = .width
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.style = .sourceList
        table.rowHeight = AccountSidebarCellView.singleLineRowHeight
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.allowsEmptySelection = true
        table.backgroundColor = .clear
        table.setAccessibilityLabel("Sidebar")
        table.setAccessibilityHelp("Select Home or an account. The context menu and Delete key remove the selected account after confirmation.")
        table.accountMenu = { [weak self] row in self?.accountContextMenu(row: row) }
        table.removeSelectedAccount = { [weak self] in self?.removeSelectedAccount() }
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
        settingsButton.setButtonType(.pushOnPushOff)
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
        consoleButton.title = "Connect API Credits…"
        consoleButton.setAccessibilityLabel("Connect API credits")
        consoleButton.toolTip = "Sign in separately to Claude Platform to read API credits."
        consoleButton.setContentHuggingPriority(.required, for: .horizontal)
        accountActions.addItem(withTitle: "Account")
        accountActions.setAccessibilityLabel("Account")
        accountActions.toolTip = "Actions for the selected account"
        accountActions.menu?.autoenablesItems = false
        for (item, label) in [
            (detailsItem, "Show account connection details"),
            (reconnectItem, "Reconnect selected account"),
            (billingItem, "Open selected account billing"),
            (creditsItem, "Manage selected account API credit connection")
        ] {
            item.target = self
            item.setAccessibilityLabel(label)
            accountActions.menu?.addItem(item)
        }
        detailsItem.toolTip = "Show account connection details"
        reconnectItem.toolTip = "Reconnect selected account"
        billingItem.toolTip = "Open account billing dashboard"
        creditsItem.toolTip = "Manage automatic API credit readings for this account"
        accountActions.menu?.addItem(.separator())
        removeAccountItem.target = self
        removeAccountItem.setAccessibilityLabel("Remove selected account")
        accountActions.menu?.addItem(removeAccountItem)
        for button in [usageButton, consoleButton] {
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        }
        accountActions.controlSize = .small
        accountActions.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let headerActions = NSStackView(views: [usageButton, accountActions])
        headerActions.orientation = .horizontal
        headerActions.alignment = .firstBaseline
        headerActions.spacing = 6
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
        let creditsLabel = InterfaceControls.label("Credits", size: 13, weight: .semibold)
        creditsLabel.setContentHuggingPriority(.required, for: .horizontal)
        let creditsHeading = NSStackView(views: [creditsLabel, consoleButton])
        creditsHeading.orientation = .horizontal
        creditsHeading.alignment = .firstBaseline
        creditsHeading.spacing = 12
        creditsHeading.detachesHiddenViews = true
        accountEditor.orientation = .vertical
        accountEditor.alignment = .leading
        accountEditor.spacing = 12
        accountEditor.detachesHiddenViews = true
        let sections: [NSView] = [
            header, attentionRow,
            InterfaceControls.label("Usage", size: 13, weight: .semibold), usageReadings,
            InterfaceControls.separator(),
            creditsHeading, creditReadings,
            creditHelp,
            manualHeading, manualEditor
        ]
        for view in sections {
            accountEditor.addArrangedSubview(view)
            if view !== manualHeading {
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
            sidebar.widthAnchor.constraint(equalToConstant: Self.sidebarWidth),
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
        fitAccountColumn()
        applyWindowLimits(for: .home)
        render()
    }

    func render() {
        let previousID = selectedID
        let now = Date()
        let nextDisplays = Dictionary(uniqueKeysWithValues: model.profiles.map { profile in
            (profile.id, sidebarDisplay(profile: profile, now: now))
        })
        isUpdatingSelection = true
        let profilesChanged = displayedProfiles != model.profiles
        if profilesChanged { displayedProfiles = model.profiles }
        if profilesChanged || table.numberOfRows != displayedProfiles.count + 1 {
            sidebarDisplays = nextDisplays
            table.reloadData()
        } else {
            var rowsNeedingHeight = IndexSet()
            for (index, profile) in displayedProfiles.enumerated() where sidebarDisplays[profile.id] != nextDisplays[profile.id] {
                let row = index + Self.accountRowOffset
                if sidebarDisplays[profile.id]?.identity != nextDisplays[profile.id]?.identity {
                    rowsNeedingHeight.insert(row)
                }
                if let display = nextDisplays[profile.id] {
                    (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? AccountSidebarCellView)?.render(display)
                }
            }
            sidebarDisplays = nextDisplays
            if !rowsNeedingHeight.isEmpty {
                table.noteHeightOfRows(withIndexesChanged: rowsNeedingHeight)
            }
        }
        switch section {
        case .settings:
            if !model.profiles.contains(where: { $0.id == selectedID }) { selectedID = nil }
            table.deselectAll(nil)
        case .home:
            if let selectedID, !model.profiles.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
            if table.numberOfRows > Self.homeRow {
                table.selectRowIndexes(IndexSet(integer: Self.homeRow), byExtendingSelection: false)
            }
        case .account, .platform:
            if let selectedID, let row = sidebarRow(for: selectedID) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else if let first = model.profiles.first {
                table.selectRowIndexes(IndexSet(integer: Self.accountRowOffset), byExtendingSelection: false)
                selectedID = first.id
            } else {
                selectedID = nil
                table.deselectAll(nil)
            }
        }
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
        if section == .home {
            if settings.isViewLoaded { settings.view.removeFromSuperview() }
            detailScroll.isHidden = true
            installDetailView(home.view)
            window?.contentView?.layoutSubtreeIfNeeded()
            home.render()
        }
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

    func showHome() {
        guard window?.attachedSheet == nil else { return }
        let entering = section != .home
        leavePlatform()
        if settings.isViewLoaded { settings.view.removeFromSuperview() }
        detailScroll.isHidden = true
        installDetailView(home.view)
        setSection(.home)
        render()
        guard entering, let window, window.isVisible else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        home.focusInitialControl()
    }

    func showSettings() {
        guard window?.attachedSheet == nil else { return }
        leavePlatform()
        hideHome()
        detailScroll.isHidden = true
        installDetailView(settings.view)
        settings.refresh()
        setSection(.settings)
        isUpdatingSelection = true
        table.deselectAll(nil)
        isUpdatingSelection = false
        window?.recalculateKeyViewLoop()
        settings.focusInitialControl()
    }

    @objc private func selectSettings(_ sender: Any?) { showSettings() }

    func showPlatform(_ controller: ClaudePlatformViewController, accountID: UUID) {
        guard window?.attachedSheet == nil else { return }
        leavePlatform()
        hideHome()
        if settings.isViewLoaded { settings.view.removeFromSuperview() }
        selectedID = accountID
        platform = controller
        controller.onBack = { [weak self] in self?.showAccountDetail(); self?.render() }
        detailScroll.isHidden = true
        setSection(.platform)
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
    }

    private func hideHome() {
        guard home.isViewLoaded, home.view.superview != nil else { return }
        home.dismissDetails()
        home.view.removeFromSuperview()
    }

    private func showAccountDetail() {
        leavePlatform()
        hideHome()
        if settings.isViewLoaded { settings.view.removeFromSuperview() }
        detailScroll.isHidden = false
        setSection(.account)
        window?.recalculateKeyViewLoop()
    }

    private func showAccount(id: UUID) {
        guard window?.attachedSheet == nil, model.profiles.contains(where: { $0.id == id }) else { return }
        let changed = selectedID != id
        selectedID = id
        showAccountDetail()
        if changed {
            editorNeedsReload = false
            editorReloadRevision = nil
            renderSelection()
        }
        render()
    }

    private func reconnectAccount(id: UUID) {
        guard canModifyAccounts, window?.attachedSheet == nil,
              let profile = model.profiles.first(where: { $0.id == id }) else { return }
        if profile.provider == .claude { onClaudeConnection?(id, InterfaceFormatting.accountIdentity(profile)) }
        else { model.signInCodex(id) }
    }

    private func updateWindowTitle() {
        updateSettingsButtonState()
        let title: String
        switch section {
        case .settings: title = "App Settings"
        case .home: title = "AI Usage Stats"
        case .account, .platform:
            if let profile = model.profiles.first(where: { $0.id == selectedID }) {
                title = "\(InterfaceFormatting.provider(profile.provider)) · \(InterfaceFormatting.accountIdentity(profile))"
            } else { title = "AI Usage Stats" }
        }
        if window?.title != title { window?.title = title }
    }

    private func updateSettingsButtonState() {
        let selected = section == .settings
        settingsButton.state = selected ? .on : .off
        settingsButton.showsBorderOnlyWhileMouseInside = !selected
    }

    func windowWillClose(_ notification: Notification) {
        platform?.hidePane(pauseRefresh: true)
        if home.isViewLoaded { home.dismissDetails() }
    }

    override func showWindow(_ sender: Any?) {
        let wasVisible = window?.isVisible == true
        if section == .platform { platform?.presentPane() }
        super.showWindow(sender)
        fitAccountColumn()
        guard section == .home, !wasVisible else { return }
        window?.contentView?.layoutSubtreeIfNeeded()
        home.focusInitialControl()
    }

    func windowDidResize(_ notification: Notification) {
        fitAccountColumn()
        guard !isApplyingWindowSize, let size = window?.contentView?.frame.size else { return }
        switch windowSurface(for: section) {
        case .home: homeWindowSize = size
        case .account: accountWindowSize = size
        case .platform: platformWindowSize = size
        }
    }

    private func fitAccountColumn() {
        window?.contentView?.layoutSubtreeIfNeeded()
        let previous = table.tableColumns.first?.width ?? 0
        table.sizeLastColumnToFit()
        let width = table.tableColumns.first?.width ?? 0
        guard abs(width - previous) > 0.5, table.numberOfRows > 0 else { return }
        table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: 0..<table.numberOfRows))
    }

    func numberOfRows(in tableView: NSTableView) -> Int { displayedProfiles.count + 1 }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if row == Self.homeRow {
            let identifier = NSUserInterfaceItemIdentifier("home")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? HomeSidebarCellView ?? HomeSidebarCellView()
            cell.identifier = identifier
            return cell
        }
        guard let index = profileIndex(forSidebarRow: row), let display = sidebarDisplays[displayedProfiles[index].id] else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("account")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? AccountSidebarCellView ?? AccountSidebarCellView()
        cell.identifier = identifier
        cell.noteColumnWidth(tableView.tableColumns.first?.width ?? 0)
        cell.render(display)
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        if row == Self.homeRow { return HomeSidebarCellView.rowHeight }
        guard let index = profileIndex(forSidebarRow: row) else { return AccountSidebarCellView.singleLineRowHeight }
        let identity = sidebarDisplays[displayedProfiles[index].id]?.identity ?? ""
        return AccountSidebarCellView.rowHeight(for: identity, columnWidth: tableView.tableColumns.first?.width ?? 0)
    }

    private func sidebarDisplay(profile: AccountProfile, now: Date) -> AccountSidebarCellView.Display {
        let snapshot = model.snapshots[profile.id]
        let summary = AccountQuotaSummary(snapshot: snapshot, accountID: profile.id, now: now)
        var detail: String
        switch summary {
        case let .available(_, _, title): detail = "Lowest remaining current quota: \(title)."
        case .unknown: detail = "A complete current usage reading is not available."
        case .inactive: detail = "All reported quota windows are inactive."
        case .stale: detail = "The last usage reading is at least five minutes old or a current quota reset is due. Refresh to check usage."
        case .unavailable: detail = "The provider could not supply current usage."
        case .authenticationRequired: detail = "Reconnect or review this account's access to check current usage."
        }
        if let snapshot, snapshot.profileID == profile.id, let fetchedAt = snapshot.fetchedAt {
            detail += " Last reading: \(InterfaceFormatting.exactDate(fetchedAt))."
        }
        if InterfaceFormatting.accountEmail(profile) == "Email unavailable" { detail += " Email unavailable." }
        return AccountSidebarCellView.Display(identity: InterfaceFormatting.accountIdentity(profile),
                                              provider: InterfaceFormatting.provider(profile.provider), summary: summary, detail: detail)
    }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection else { return }
        let row = table.selectedRow
        if row == Self.homeRow {
            showHome()
            return
        }
        guard let accountID = accountID(forSidebarRow: row) else { return }
        let changedAccount = selectedID != accountID
        selectedID = accountID
        showAccountDetail()
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
        recoveryButton.isEnabled = canSave
        usageButton.isEnabled = canSave
        usageButton.title = model.isRefreshing ? "Refreshing…" : "Refresh"
        let profile = model.profiles.first(where: { $0.id == selectedID })
        let platformConnected = profile.map { $0.provider == .claude && model.consoleConnections[$0.id] != nil } ?? false
        detailsItem.isEnabled = profile != nil
        reconnectItem.isEnabled = canSave
        billingItem.isEnabled = profile != nil
        billingItem.toolTip = monthlyGrantNeedsLink ? "Open Claude subscription billing" : "Open account billing dashboard"
        creditsItem.isHidden = !platformConnected
        creditsItem.isEnabled = canSave && platformConnected
        removeAccountItem.isEnabled = canSave && window?.attachedSheet == nil
        accountActions.isEnabled = profile != nil
        consoleButton.isHidden = profile?.provider != .claude || platformConnected
        consoleButton.isEnabled = canSave && profile?.provider == .claude && !platformConnected
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
        reconnectItem.toolTip = profile.provider == .claude ? "Reconnect Claude subscription" : "Sign in to this Codex account again"
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
            AccountReadingView.Reading(label: InterfaceFormatting.compactCreditTitle(credit), value: InterfaceFormatting.credit(credit),
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
        let platformConnected = profile.provider == .claude && model.consoleConnections[id] != nil
        creditHelp.stringValue = profile.provider == .claude && !platformConnected ? "API credits use a separate Claude Platform sign-in." : ""
        creditHelp.isHidden = creditHelp.stringValue.isEmpty
    }

    @objc private func toggleManualEditor(_ sender: NSButton) {
        manualEditor.isHidden = sender.state != .on
        sender.setAccessibilityLabel(sender.state == .on ? "Hide manual balance editor" : "Show manual balance editor")
        window?.recalculateKeyViewLoop()
    }

    @objc private func showConnectionDetails(_ sender: Any?) {
        guard window?.attachedSheet == nil,
              let id = selectedID, let profile = model.profiles.first(where: { $0.id == id }) else { return }
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
        guard canModifyAccounts, window?.attachedSheet == nil,
              let id = selectedID, let profile = model.profiles.first(where: { $0.id == id }) else { return }
        if profile.provider == .claude { onClaudeConnection?(id, InterfaceFormatting.accountIdentity(profile)) }
        else { model.signInCodex(id) }
    }
    @objc private func checkUsage(_ sender: Any?) { model.refresh() }
    @objc private func connectConsole(_ sender: Any?) {
        guard canModifyAccounts, window?.attachedSheet == nil,
              let id = selectedID, model.profiles.first(where: { $0.id == id })?.provider == .claude else { return }
        onConsoleConnection?(id)
    }

    private var canModifyAccounts: Bool { !model.isDemo && !model.isChangingAccounts && !model.isRefreshing }

    private func accountContextMenu(row: Int) -> NSMenu? {
        guard let id = accountID(forSidebarRow: row) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let item = NSMenuItem(title: "Remove Account…", action: #selector(removeAccountFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = id
        item.isEnabled = canModifyAccounts && window?.attachedSheet == nil
        menu.addItem(item)
        return menu
    }

    private func removeSelectedAccount() {
        guard section != .settings, section != .home, let id = accountID(forSidebarRow: table.selectedRow) else { return }
        confirmAccountRemoval(id: id)
    }

    @objc private func removeSelectedAccountFromActions(_ sender: Any?) {
        guard let id = selectedID else { return }
        confirmAccountRemoval(id: id)
    }

    @objc private func removeAccountFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        confirmAccountRemoval(id: id)
    }

    private func confirmAccountRemoval(id: UUID) {
        guard canModifyAccounts, let window, window.attachedSheet == nil,
              let profile = model.profiles.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Remove \(InterfaceFormatting.provider(profile.provider)) · \(InterfaceFormatting.accountIdentity(profile))?"
        alert.informativeText = "Removes this profile and its saved usage from AI Usage Stats."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .alertFirstButtonReturn,
                  self.model.profiles.contains(where: { $0.id == id }) else { return }
            guard self.canModifyAccounts else { self.showAccountRemovalError(); return }
            self.model.removeAccount(id)
        }
    }

    private func showAccountRemovalError() {
        let alert = NSAlert()
        alert.messageText = "Could Not Remove Account"
        alert.informativeText = model.isDemo ? "Demo accounts cannot be removed."
            : model.isRefreshing ? "Usage is refreshing. Remove the account again after the refresh finishes."
            : "An account update is in progress. Remove the account again after the update finishes."
        if let window { alert.beginSheetModal(for: window) }
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
        guard window?.attachedSheet == nil,
              let provider = model.profiles.first(where: { $0.id == selectedID })?.provider else { return }
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

    private func setSection(_ newSection: Section) {
        let previous = windowSurface(for: section)
        section = newSection
        if previous != windowSurface(for: section) { applyWindowLimits(for: windowSurface(for: section)) }
        updateWindowTitle()
    }

    private func windowSurface(for section: Section) -> WindowSurface {
        switch section {
        case .home: return .home
        case .account, .settings: return .account
        case .platform: return .platform
        }
    }

    private func sizeLimits(for surface: WindowSurface) -> WindowSizeLimits {
        switch surface {
        case .home:
            return WindowSizeLimits(minimum: Self.homeWindowMinimumSize, maximum: Self.homeWindowMaximumSize)
        case .account:
            return WindowSizeLimits(minimum: Self.accountWindowMinimumSize, maximum: Self.accountWindowMaximumSize)
        case .platform:
            return WindowSizeLimits(minimum: Self.platformWindowMinimumSize, maximum: Self.platformWindowMaximumSize)
        }
    }

    private func preferredWindowContentSize(for surface: WindowSurface) -> NSSize {
        switch surface {
        case .home: return homeWindowSize
        case .account: return accountWindowSize
        case .platform:
            // Match the previous Platform behavior: grow to the Platform default without shrinking a larger account window.
            return platformWindowSize ?? NSSize(width: max(Self.platformWindowDefaultSize.width, accountWindowSize.width),
                                                height: max(Self.platformWindowDefaultSize.height, accountWindowSize.height))
        }
    }

    private func applyWindowLimits(for surface: WindowSurface) {
        guard let window else { return }
        let limits = sizeLimits(for: surface)
        isApplyingWindowSize = true
        defer { isApplyingWindowSize = false }
        // Lower the minimum before the maximum so a smaller surface can take effect.
        window.contentMinSize = NSSize(width: min(window.contentMinSize.width, limits.minimum.width),
                                       height: min(window.contentMinSize.height, limits.minimum.height))
        window.contentMaxSize = limits.maximum
        window.contentMinSize = limits.minimum
        window.setContentSize(fittedContentSize(preferredWindowContentSize(for: surface), limits: limits))
    }

    private func fittedContentSize(_ proposed: NSSize, limits: WindowSizeLimits) -> NSSize {
        let bounded = NSSize(width: min(max(proposed.width, limits.minimum.width), limits.maximum.width),
                             height: min(max(proposed.height, limits.minimum.height), limits.maximum.height))
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return bounded }
        let contentHeight = window.contentView?.frame.height ?? bounded.height
        let chrome = max(28, window.frame.height - contentHeight)
        return NSSize(width: min(bounded.width, max(limits.minimum.width, visible.width - 24)),
                      height: min(bounded.height, max(limits.minimum.height, visible.height - chrome - 8)))
    }

    // Row 0 is Home. Later rows follow the saved account order and are addressed by UUID.
    private func profileIndex(forSidebarRow row: Int) -> Int? {
        let index = row - Self.accountRowOffset
        guard row != Self.homeRow, displayedProfiles.indices.contains(index) else { return nil }
        return index
    }

    private func accountID(forSidebarRow row: Int) -> UUID? {
        guard let index = profileIndex(forSidebarRow: row) else { return nil }
        let id = displayedProfiles[index].id
        guard model.profiles.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    private func sidebarRow(for accountID: UUID) -> Int? {
        guard let index = displayedProfiles.firstIndex(where: { $0.id == accountID }) else { return nil }
        return index + Self.accountRowOffset
    }
}

@MainActor
private final class HomeSidebarCellView: NSTableCellView {
    static let rowHeight: CGFloat = 32

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let symbol = NSImage(systemSymbolName: "house", accessibilityDescription: nil)
        symbol?.isTemplate = true
        let image = NSImageView()
        image.image = symbol
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        image.imageScaling = .scaleProportionallyDown
        image.translatesAutoresizingMaskIntoConstraints = false
        image.setAccessibilityElement(false)
        let label = NSTextField(labelWithString: "Home")
        label.font = .systemFont(ofSize: 13)
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setAccessibilityElement(false)
        imageView = image
        textField = label
        addSubview(image)
        addSubview(label)
        NSLayoutConstraint.activate([
            image.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            image.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 6),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
        setAccessibilityLabel("Home")
        setAccessibilityHelp("Show the reset calendar and account usage.")
    }

    required init?(coder: NSCoder) { nil }
}

@MainActor
private final class AccountDetailDocumentView: NSView {
    override var isFlipped: Bool { true }
}
