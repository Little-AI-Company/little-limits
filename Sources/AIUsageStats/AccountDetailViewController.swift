import AppKit
import UsageCore

/// The account page: usage and credit readings, API Credits controls, the manual balance editor, and Connection Details.
/// Account-level commands live in the window toolbar through `WindowToolbarContributor`.
@MainActor
final class AccountDetailViewController: NSViewController, WindowToolbarContributor, NSMenuItemValidation {
    private static let refreshAllItem = NSToolbarItem.Identifier("AccountRefreshAll")
    private static let refreshAccountItem = NSToolbarItem.Identifier("AccountRefresh")
    private static let reconnectItem = NSToolbarItem.Identifier("AccountReconnect")
    private static let billingItem = NSToolbarItem.Identifier("AccountBilling")
    /// Matches `ClaudeKeychainStore.read`: the saved sign-in exists but macOS has not granted this app access to it.
    private static let keychainPermissionFailure = "Keychain access needs permission"
    private static let codexSignInWait = "Waiting for Codex sign-in in Terminal…"

    private let model: ApplicationModel
    private let scroll = NSScrollView()
    private let attention = InterfaceControls.label("", size: 12)
    private let creditHelp = InterfaceControls.label("", size: 12)
    private let usageReadings = AccountReadingView()
    private let creditReadings = AccountReadingView()
    private let recoveryButton = NSButton(title: "Reconnect…", target: nil, action: nil)
    private let keychainAccessButton = NSButton(title: "Allow Keychain Access…", target: nil, action: nil)
    private let consoleButton = NSButton(title: "Connect API Credits…", target: nil, action: nil)
    private let disconnectConsoleButton = NSButton(title: "Disconnect API Credits", target: nil, action: nil)
    private let connectionDetails = InterfaceControls.label("", size: 12)
    private let manualDisclosure = NSButton(title: "", target: nil, action: nil)
    private let manualEditor = NSStackView()
    private let manualHelp = InterfaceControls.label("Enter the amount shown in billing. This dated record does not update automatically.")
    private let accountEditor = NSStackView()
    private let emptyState = InterfaceControls.label("", size: 13)
    private let accountLoadError = NSStackView()
    private let accountLoadMessage = InterfaceControls.label("", size: 13)
    private let retryAccountLoadButton = NSButton(title: "Retry Loading Accounts", target: nil, action: nil)
    private let manualCategory = NSPopUpButton(frame: .zero, pullsDown: false)
    private let balanceField = NSTextField(string: "")
    private let balanceDate = NSDatePicker()
    private let expiryKnown = NSButton(checkboxWithTitle: "Set expiration", target: nil, action: nil)
    private let expiryDate = NSDatePicker()
    private let saveBalanceButton = NSButton(title: "Save Balance", target: nil, action: nil)
    private let clearBalanceButton = NSButton(title: "Clear Balance", target: nil, action: nil)
    private let status = InterfaceControls.label("")
    private weak var refreshAllToolbarItem: NSToolbarItem?
    private weak var refreshAccountToolbarItem: NSToolbarItem?
    private weak var reconnectToolbarItem: NSToolbarItem?
    private weak var billingToolbarItem: NSToolbarItem?
    private var accountID: UUID?
    private var displayedAccountID: UUID?
    private var displayedCredits: [CreditBalance] = []
    private var selectedCategoryID: String?
    private var editorNeedsReload = true
    private var editorReloadRevision: Int?
    private(set) var windowSubtitle = ""

    var onToolbarStateChange: (() -> Void)?
    var onReconnect: ((UUID) -> Void)?
    var onConsoleConnection: ((UUID) -> Void)?
    var onConsoleDisconnection: ((UUID) -> Void)?
    var isAccountLoadComplete: () -> Bool = { false }
    var onRetryAccountLoad: (() -> Void)?

    init(model: ApplicationModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }

    let toolbarItemIdentifiers: [NSToolbarItem.Identifier] = [.flexibleSpace, AccountDetailViewController.reconnectItem, AccountDetailViewController.billingItem, .space, AccountDetailViewController.refreshAccountItem, AccountDetailViewController.refreshAllItem]

    func makeToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        let item: NSToolbarItem
        switch identifier {
        case Self.refreshAllItem:
            item = makeRefreshAllItem()
            refreshAllToolbarItem = item
        case Self.refreshAccountItem:
            item = makeTextItem(identifier, title: "Refresh Account", action: #selector(refreshSelectedAccount(_:)))
            refreshAccountToolbarItem = item
        case Self.reconnectItem:
            item = makeTextItem(identifier, title: "Reconnect…", action: #selector(reconnect(_:)))
            reconnectToolbarItem = item
        case Self.billingItem:
            item = makeTextItem(identifier, title: "Billing", action: #selector(openBilling(_:)))
            billingToolbarItem = item
        default: return nil
        }
        updateToolbarItems()
        return item
    }

    private func updateToolbarItems() {
        let profile = profile
        let canSave = !model.isDemo && profile != nil && !model.isRefreshing && !model.isChangingAccounts
        refreshAllToolbarItem?.isEnabled = !model.isDemo && !model.isRefreshing && !model.isChangingAccounts && !model.profiles.isEmpty
        refreshAllToolbarItem?.toolTip = model.isRefreshing ? "Refreshing…" : "Refresh All"
        refreshAccountToolbarItem?.isEnabled = canRefreshAccount
        refreshAccountToolbarItem?.toolTip = model.isRefreshing ? "Refreshing…" : "Read this account's usage again"
        reconnectToolbarItem?.isEnabled = canSave && profile?.source != .codexDefaultLogin
        reconnectToolbarItem?.toolTip = profile?.source == .codexDefaultLogin
            ? "This account reads the Codex CLI login on this Mac"
            : profile?.provider == .codex
            ? "Sign in to this Codex account again in Terminal" : "Sign in to this Claude subscription again in your browser"
        billingToolbarItem?.isEnabled = profile != nil
        billingToolbarItem?.toolTip = monthlyGrantNeedsLink ? "Open Claude subscription billing in your browser"
            : profile?.provider == .codex ? "Open OpenAI billing in your browser" : "Open Claude Platform billing in your browser"
    }

    private func makeRefreshAllItem() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: Self.refreshAllItem)
        item.label = "Refresh All"
        item.paletteLabel = "Refresh All"
        item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh All")
        item.isBordered = true
        item.autovalidates = false
        // The application delegate refreshes every account; this page only sends the command.
        item.action = #selector(WindowCommandHandling.refreshAllAccounts(_:))
        return item
    }

    private func makeTextItem(_ identifier: NSToolbarItem.Identifier, title: String, action: Selector) -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: identifier)
        item.title = title
        item.label = title
        item.paletteLabel = title
        item.isBordered = true
        item.autovalidates = false
        item.target = self
        item.action = action
        return item
    }

    override func loadView() {
        let root = NSView()
        view = root
        recoveryButton.target = self
        recoveryButton.action = #selector(reconnect(_:))
        keychainAccessButton.target = self
        keychainAccessButton.action = #selector(allowKeychainAccess(_:))
        keychainAccessButton.toolTip = "Reads this account’s existing saved sign-in. macOS may ask for access. This does not start a new sign-in or replace credentials."
        consoleButton.target = self
        consoleButton.action = #selector(connectConsole(_:))
        consoleButton.toolTip = "Sign in separately to Claude Platform to read API Credits."
        consoleButton.setContentHuggingPriority(.required, for: .horizontal)
        disconnectConsoleButton.target = self
        disconnectConsoleButton.action = #selector(disconnectConsole(_:))
        disconnectConsoleButton.toolTip = "Stop automatic API Credits readings while keeping the separate Claude Platform sign-in."
        let attentionRow = NSStackView(views: [attention, recoveryButton, keychainAccessButton])
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
        let creditsHeading = NSStackView(views: [creditsLabel, consoleButton, disconnectConsoleButton])
        creditsHeading.orientation = .horizontal
        creditsHeading.alignment = .firstBaseline
        creditsHeading.spacing = 12
        creditsHeading.detachesHiddenViews = true
        connectionDetails.isSelectable = true
        let connectionSection = InterfaceControls.stack([InterfaceControls.label("Connection Details", size: 13, weight: .semibold),
                                                         connectionDetails], spacing: 8)
        connectionDetails.widthAnchor.constraint(equalTo: connectionSection.widthAnchor).isActive = true
        accountEditor.orientation = .vertical
        accountEditor.alignment = .leading
        accountEditor.spacing = 12
        accountEditor.detachesHiddenViews = true
        let sections: [NSView] = [
            attentionRow,
            InterfaceControls.label("Usage", size: 13, weight: .semibold), usageReadings,
            InterfaceControls.separator(),
            creditsHeading, creditReadings,
            creditHelp,
            manualHeading, manualEditor,
            InterfaceControls.separator(), connectionSection
        ]
        for view in sections {
            accountEditor.addArrangedSubview(view)
            if view !== manualHeading {
                view.widthAnchor.constraint(equalTo: accountEditor.widthAnchor).isActive = true
            }
        }
        let document = FlippedDocumentView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        document.translatesAutoresizingMaskIntoConstraints = false
        retryAccountLoadButton.target = self
        retryAccountLoadButton.action = #selector(retryAccountLoad(_:))
        let loadErrorTitle = InterfaceControls.label("Accounts Could Not Be Loaded", size: 16, weight: .semibold)
        accountLoadError.orientation = .vertical
        accountLoadError.alignment = .leading
        accountLoadError.spacing = 12
        for component in [loadErrorTitle, accountLoadMessage, retryAccountLoadButton] {
            accountLoadError.addArrangedSubview(component)
        }
        accountLoadMessage.widthAnchor.constraint(equalTo: accountLoadError.widthAnchor).isActive = true
        let detailStack = InterfaceControls.stack([accountEditor, accountLoadError, emptyState, status], spacing: 16)
        detailStack.detachesHiddenViews = true
        detailStack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(detailStack)
        root.addSubview(scroll)
        for view in [accountEditor, accountLoadError, emptyState, status] {
            view.widthAnchor.constraint(equalTo: detailStack.widthAnchor).isActive = true
        }
        // The scroll view passes under the toolbar; its automatic content insets keep the first row visible.
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            detailStack.topAnchor.constraint(equalTo: document.topAnchor, constant: 20),
            detailStack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            detailStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            detailStack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -22)
        ])
    }

    /// Shows `accountID` and applies current model data. Unfinished manual edits survive unless the account changes
    /// or a saved change for this account has completed.
    func render(accountID: UUID?) {
        _ = view
        self.accountID = accountID
        status.stringValue = model.isDemo ? "Demo accounts cannot be changed."
            : model.isAllowingKeychainAccess ? "Allowing Keychain access…"
            : model.isSigningInClaude ? "Claude sign-in is in progress."
            : model.isChangingAccounts ? "Updating account…" : ""
        status.isHidden = status.stringValue.isEmpty
        let savedChangeCompleted = editorReloadRevision.map { model.completedAccountChanges >= $0 } ?? false
        if displayedAccountID != accountID || (!model.isChangingAccounts && (editorNeedsReload || savedChangeCompleted)) {
            editorNeedsReload = false
            editorReloadRevision = nil
            renderSelection()
        }
        updateSelectionDescription()
        updateEditorAvailability()
        renderAccountLoadState()
    }

    private func renderAccountLoadState() {
        let hasLoadError = model.hasAccountLoadFailure
        accountLoadError.isHidden = !hasLoadError
        accountLoadMessage.stringValue = hasLoadError ? model.message ?? "" : ""
        retryAccountLoadButton.isEnabled = hasLoadError && isAccountLoadComplete() && onRetryAccountLoad != nil
        emptyState.isHidden = !model.profiles.isEmpty || hasLoadError
        emptyState.stringValue = isAccountLoadComplete()
            ? "Add a Claude or Codex account to see remaining quota."
            : "Loading accounts…"
        view.window?.recalculateKeyViewLoop()
    }

    @objc private func retryAccountLoad(_ sender: Any?) {
        guard isAccountLoadComplete(), model.hasAccountLoadFailure else { return }
        onRetryAccountLoad?()
    }

    private func renderSelection() {
        displayedAccountID = accountID
        guard let id = accountID, let profile = model.profiles.first(where: { $0.id == id }) else {
            accountEditor.isHidden = true
            emptyState.isHidden = false
            displayedCredits = []
            manualCategory.removeAllItems()
            updateManualFields()
            return
        }
        accountEditor.isHidden = false
        emptyState.isHidden = true
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

    private var profile: AccountProfile? { model.profiles.first(where: { $0.id == accountID }) }
    private var canModifyAccounts: Bool { !model.isDemo && !model.isChangingAccounts && !model.isRefreshing }

    private func updateEditorAvailability() {
        let editable = !model.isDemo && accountID != nil
        let canSave = editable && !model.isRefreshing && !model.isChangingAccounts
        let profile = profile
        let platformConnected = profile.map { $0.provider == .claude && model.consoleConnections[$0.id] != nil } ?? false
        updateToolbarItems()
        recoveryButton.isEnabled = canSave && profile?.source != .codexDefaultLogin
        consoleButton.isHidden = profile?.provider != .claude
        consoleButton.title = platformConnected ? "Manage API Credits…" : "Connect API Credits…"
        consoleButton.isEnabled = canSave && profile?.provider == .claude
        disconnectConsoleButton.isHidden = !platformConnected
        disconnectConsoleButton.isEnabled = canSave && platformConnected
        keychainAccessButton.isEnabled = canSave && !model.isAllowingKeychainAccess
        manualDisclosure.isEnabled = accountID != nil
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
        let needsConfirmation = displayedCredits.indices.contains(index) && accountID.map { id in
            (model.pendingManualCredits[id] ?? []).contains { $0.id == displayedCredits[index].id }
                && !(model.manualCredits[id] ?? []).contains { $0.id == displayedCredits[index].id }
        } == true
        manualHelp.stringValue = needsConfirmation
            ? "This saved balance came from the earlier unverified connection. Confirm it in billing, then choose Save Balance before it is shown as this account's balance."
            : "Enter the amount shown in billing. This dated record does not update automatically."
    }

    private func updateSelectionDescription() {
        guard let id = accountID, let profile = profile else {
            setSubtitle("")
            return
        }
        let snapshot = model.snapshots[id]
        setSubtitle([InterfaceFormatting.provider(profile.provider), snapshot?.planName].compactMap { $0 }.joined(separator: " · "))
        let now = Date()
        let windows = snapshot?.windows ?? []
        let awaitingSignIn = model.isAwaitingCodexSignIn(id)
        usageReadings.render(windows.isEmpty
            ? [AccountReadingView.Reading(label: "Usage", value: "Unavailable", timing: "",
                                          detail: awaitingSignIn ? Self.codexSignInWait
                                              : snapshot?.detail ?? "No usage reading yet. Choose Refresh All to read usage.")]
            : windows.map { usage in
                // The same value and timing as the status menu, so an outdated reading never passes for current.
                let title = InterfaceFormatting.usageTitle(usage)
                let reading = snapshot.map { InterfaceFormatting.reading(usage, snapshot: $0, now: now) }
                    ?? (value: InterfaceFormatting.remaining(usage), timing: "")
                // The page has room for the absolute time beside the countdown: `Resets in 2d 4h · Fri 13:43`.
                var timing = reading.timing
                if timing.hasPrefix("Resets in "), let date = usage.resetsAt {
                    timing += " · \(HomeInterfaceFormatting.scheduleText(date, now: now, calendar: .current))"
                }
                return AccountReadingView.Reading(label: title, value: reading.value, timing: timing,
                                                  detail: "\(title): \(reading.value). \(InterfaceFormatting.reset(usage, snapshot: snapshot, now: now))")
            })
        let credits = snapshot?.credits ?? UsageService.unavailableCredits(for: profile.provider)
        creditReadings.render(credits.map { credit in
            AccountReadingView.Reading(label: InterfaceFormatting.compactCreditTitle(credit), value: InterfaceFormatting.credit(credit),
                                       timing: InterfaceFormatting.compactCreditTiming(credit, now: now),
                                       detail: InterfaceFormatting.creditDetail(credit, now: now))
        })
        renderAttention(profile: profile, snapshot: snapshot, now: now)
        let platformConnected = profile.provider == .claude && model.consoleConnections[id] != nil
        creditHelp.stringValue = profile.provider == .claude && !platformConnected
            ? "API Credits use a separate Claude Platform sign-in. Choose Connect API Credits… to read them." : ""
        creditHelp.isHidden = creditHelp.stringValue.isEmpty
        updateConnectionDetails(profile: profile, snapshot: snapshot)
    }

    /// One state line with at most one recovery action: Reconnect… for failed sign-in, or Allow Keychain Access…
    /// only when the saved sign-in exists but its Keychain read was refused.
    private func renderAttention(profile: AccountProfile, snapshot: AccountSnapshot?, now: Date) {
        var message = ""
        var recovery: NSButton?
        if model.isAwaitingCodexSignIn(profile.id) {
            message = Self.codexSignInWait
        } else if let snapshot {
            switch snapshot.state {
            case .authenticationRequired:
                if profile.source == .claudeOAuth, snapshot.detail?.contains(Self.keychainPermissionFailure) == true {
                    message = "Keychain access needs permission. Your saved sign-in is preserved."
                    recovery = keychainAccessButton
                } else {
                    message = "Sign-in required."
                    recovery = recoveryButton
                }
                if !snapshot.windows.isEmpty { message += " Readings below are last known." }
            case .unavailable: message = "Unavailable. Choose Refresh All to try again."
            case .stale: message = staleMessage(snapshot.fetchedAt)
            case .available:
                if snapshot.fetchedAt.map({ now.timeIntervalSince($0) >= 300 }) == true
                    || snapshot.currentWindows.contains(where: { $0.resetsAt.map { $0 <= now } == true }) {
                    message = staleMessage(snapshot.fetchedAt)
                } else if snapshot.fetchedAt == nil && !snapshot.windows.isEmpty { message = "Last read time unknown." }
            }
        } else { message = "No usage reading yet. Choose Refresh All to read usage." }
        if message.isEmpty && model.consoleMessages[profile.id] != nil { message = "API Credits need attention. See Connection Details." }
        if message.isEmpty && !(model.pendingManualCredits[profile.id] ?? []).isEmpty { message = "Manual balances need confirmation." }
        attention.stringValue = message
        attention.toolTip = model.isAwaitingCodexSignIn(profile.id)
            ? "Finish the sign-in in Terminal. This page updates when it completes."
            : [snapshot?.detail, model.consoleMessages[profile.id]].compactMap { $0 }.joined(separator: "\n")
        recoveryButton.isHidden = recovery !== recoveryButton
        keychainAccessButton.isHidden = recovery !== keychainAccessButton
        attention.superview?.isHidden = message.isEmpty
    }

    private func staleMessage(_ fetchedAt: Date?) -> String {
        guard let fetchedAt else { return "Stale. Choose Refresh All to check usage." }
        let time = Calendar.current.isDateInToday(fetchedAt)
            ? fetchedAt.formatted(date: .omitted, time: .shortened)
            : fetchedAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())
        return "Stale · last read \(time)"
    }

    private func setSubtitle(_ subtitle: String) {
        guard windowSubtitle != subtitle else { return }
        windowSubtitle = subtitle
        onToolbarStateChange?()
    }

    @objc private func toggleManualEditor(_ sender: NSButton) {
        manualEditor.isHidden = sender.state != .on
        sender.setAccessibilityLabel(sender.state == .on ? "Hide manual balance editor" : "Show manual balance editor")
        view.window?.recalculateKeyViewLoop()
    }

    /// Identity, plan, source, last read, exact dates, and errors. Percentages stay in the readings above.
    private func updateConnectionDetails(profile: AccountProfile, snapshot: AccountSnapshot?) {
        let id = profile.id
        var details = ["Email: \(InterfaceFormatting.accountEmail(profile))"]
        if InterfaceFormatting.accountEmail(profile) == "Email unavailable" {
            details.append("Saved name: \(InterfaceFormatting.accountIdentity(profile))")
        }
        if let plan = snapshot?.planName { details.append("Plan: \(plan)") }
        switch profile.source {
        case .claudeOAuth:
            details.append("Source: this account’s Claude subscription sign-in. The usage endpoint is experimental.")
        case .claudeCLI:
            details.append("Source: captured Claude Code quota. Choose Reconnect… to read subscription usage directly.")
        case .codexCLI:
            details.append("Source: this account’s own Codex CLI login. Your existing CLI login is preserved.")
        case .codexDefaultLogin:
            details.append("Source: the Codex CLI login on this Mac, read without changing it.")
        case .manual:
            details.append("Source: dated manual readings.")
        case .demo:
            details.append("Source: example account. Readings are fictional.")
        }
        if let path = profile.sourcePath { details.append("Configuration: \(path)") }
        if let organization = model.consoleConnections[id] { details.append("API Credits organization: \(organization)") }
        if let snapshot {
            details.append("Last read: \(snapshot.fetchedAt.map(InterfaceFormatting.exactDate) ?? "Unknown")")
            for window in snapshot.windows {
                let title = InterfaceFormatting.usageTitle(window)
                if window.isActive == false {
                    details.append("\(title): inactive")
                } else {
                    details.append("\(title) resets: \(window.resetsAt.map(InterfaceFormatting.exactDate) ?? "Reset time unknown")")
                }
            }
            for credit in snapshot.credits {
                if let date = credit.expiresAt {
                    details.append("\(InterfaceFormatting.compactCreditTitle(credit)) expires: \(InterfaceFormatting.exactDate(date))")
                }
                if let asOf = credit.asOf, credit.source == .manual {
                    details.append("\(InterfaceFormatting.compactCreditTitle(credit)) confirmed: \(InterfaceFormatting.exactDate(asOf))")
                }
            }
            if model.isAwaitingCodexSignIn(id) { details.append("Status: \(Self.codexSignInWait)") }
            else if let detail = snapshot.detail { details.append("Error: \(detail)") }
        }
        if let message = model.consoleMessages[id] { details.append("API Credits error: \(message)") }
        let text = details.joined(separator: "\n")
        if connectionDetails.stringValue != text { connectionDetails.stringValue = text }
    }

    @objc private func allowKeychainAccess(_ sender: Any?) {
        guard canModifyAccounts, !model.isAllowingKeychainAccess, view.window?.attachedSheet == nil,
              let id = accountID, profile?.source == .claudeOAuth else { return }
        model.allowKeychainAccess(id)
    }

    @objc private func reconnect(_ sender: Any?) {
        guard let accountID else { return }
        onReconnect?(accountID)
    }

    @objc private func connectConsole(_ sender: Any?) {
        guard canModifyAccounts, view.window?.attachedSheet == nil,
              let id = accountID, profile?.provider == .claude else { return }
        onConsoleConnection?(id)
    }

    @objc private func disconnectConsole(_ sender: Any?) {
        guard canModifyAccounts, view.window?.attachedSheet == nil,
              let id = accountID, model.consoleConnections[id] != nil else { return }
        onConsoleDisconnection?(id)
    }

    @objc private func selectCredit(_ sender: Any?) {
        if displayedCredits.indices.contains(manualCategory.indexOfSelectedItem) {
            selectedCategoryID = displayedCredits[manualCategory.indexOfSelectedItem].id
        }
        updateManualFields()
    }

    @objc private func toggleExpiry(_ sender: Any?) { expiryDate.isEnabled = expiryKnown.state == .on }

    @objc private func saveBalance(_ sender: Any?) {
        guard let id = accountID, displayedCredits.indices.contains(manualCategory.indexOfSelectedItem) else { return }
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
        guard let id = accountID, displayedCredits.indices.contains(manualCategory.indexOfSelectedItem) else { return }
        let original = displayedCredits[manualCategory.indexOfSelectedItem]
        let credit = CreditBalance(id: original.id, title: original.title, amount: nil, unit: original.unit, source: .manual)
        editorReloadRevision = model.completedAccountChanges + 1
        model.setManualCredit(accountID: id, credit: credit)
    }

    private var monthlyGrantNeedsLink: Bool {
        guard let id = accountID, profile?.provider == .claude else { return false }
        return model.snapshots[id]?.credits.contains { $0.id == "monthly_grant" && $0.status == "Not linked" } == true
    }

    /// File > Open Billing. Enabled under the same rule as the Billing toolbar item.
    @objc func openSelectedAccountBilling(_ sender: Any?) { openBilling(sender) }

    /// File > Refresh Account and the Refresh Account toolbar item: reads only this account again.
    @objc func refreshSelectedAccount(_ sender: Any?) {
        guard canRefreshAccount, let id = accountID else { return }
        model.refreshAccount(id)
    }

    private var canRefreshAccount: Bool {
        profile != nil && !model.isDemo && !model.isRefreshing && !model.isChangingAccounts
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(openSelectedAccountBilling(_:)): profile != nil && view.window?.attachedSheet == nil
        case #selector(refreshSelectedAccount(_:)): canRefreshAccount
        default: true
        }
    }

    @objc private func openBilling(_ sender: Any?) {
        guard view.window?.attachedSheet == nil, let provider = profile?.provider else { return }
        let address = monthlyGrantNeedsLink ? "https://claude.ai/settings/billing"
            : provider == .claude ? "https://platform.claude.com/settings/billing" : "https://platform.openai.com/settings/organization/billing/overview"
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could Not Save Balance"
        alert.informativeText = message
        if let window = view.window { alert.beginSheetModal(for: window) }
    }
}

@MainActor
private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}
