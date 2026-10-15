import AppKit
import UsageCore

@MainActor
final class AccountsWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate,
                                      NSToolbarDelegate, NSMenuItemValidation, WindowCommandHandling {
    private enum Section: Equatable { case home, models, account, settings, platform }
    private static let accountPasteboardType = NSPasteboard.PasteboardType("com.parkerrex.ai-usage-stats.account-id")
    private static let homeRow = 0
    private static let modelsRow = 1
    private static let accountRowOffset = 2
    private static let windowMinimumSize = NSSize(width: 1020, height: 640)
    private static let windowMaximumSize = NSSize(width: 1680, height: 1040)
    private static let windowDefaultSize = NSSize(width: 1280, height: 780)
    private static let sidebarDefaultWidth: CGFloat = 260
    private static let fixedToolbarItems: [NSToolbarItem.Identifier] = [.toggleSidebar, .sidebarTrackingSeparator]
    private let model: ApplicationModel
    private let home: HomeViewController
    private let models: ModelsViewController
    private let detail: AccountDetailViewController
    private let settings = GeneralSettingsViewController()
    private var platform: ClaudePlatformViewController?
    private let splitController = PageCommandSplitViewController()
    private let pageContainer = NSView()
    private let table = AccountSidebarTableView()
    private let addAccountButton = NSButton(title: "", target: nil, action: nil)
    private let removeAccountButton = NSButton(title: "", target: nil, action: nil)
    private var section = Section.home
    private var selectedID: UUID?
    private var displayedProfiles: [AccountProfile] = []
    private var sidebarDisplays: [UUID: AccountSidebarCellView.Display] = [:]
    private var isUpdatingSelection = false
    private var toolbarPageIdentifiers: [NSToolbarItem.Identifier] = []
    /// `--show-models` opens the Models page the first time the window shows, for local verification.
    private var opensModelsOnFirstShow = CommandLine.arguments.contains("--show-models")
    private weak var toolbarContributor: (any WindowToolbarContributor)?
    var onClaudeConnection: ((UUID?, String) -> Void)?
    var onConsoleConnection: ((UUID) -> Void)?
    var onConsoleDisconnection: ((UUID) -> Void)?
    var isAccountLoadComplete: () -> Bool = { false }
    var onRetryAccountLoad: (() -> Void)?

    init(model: ApplicationModel) {
        self.model = model
        home = HomeViewController(model: model)
        models = ModelsViewController(model: model)
        detail = AccountDetailViewController(model: model)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: Self.windowDefaultSize),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Home"
        window.toolbarStyle = .unified
        window.isReleasedWhenClosed = false
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
        home.onAddAccount = { [weak self] provider in self?.connect(provider) }
        home.isAccountLoadComplete = { [weak self] in self?.isAccountLoadComplete() ?? false }
        detail.onReconnect = { [weak self] id in self?.reconnectAccount(id: id) }
        detail.onConsoleConnection = { [weak self] id in self?.onConsoleConnection?(id) }
        detail.onConsoleDisconnection = { [weak self] id in self?.onConsoleDisconnection?(id) }
        detail.onRetryAccountLoad = { [weak self] in self?.onRetryAccountLoad?() }
        detail.isAccountLoadComplete = { [weak self] in self?.isAccountLoadComplete() ?? false }
        for page in [home, models, detail] as [NSViewController] {
            (page as? any WindowToolbarContributor)?.onToolbarStateChange = { [weak self] in self?.updateToolbar() }
        }
        splitController.commandPage = { [weak self] in self?.visiblePage }
        guard let window else { return }

        let sidebarController = NSViewController()
        sidebarController.view = makeSidebarView()
        sidebarController.view.frame.size = NSSize(width: Self.sidebarDefaultWidth, height: Self.windowDefaultSize.height)
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarController)
        sidebarItem.canCollapse = true
        sidebarItem.allowsFullHeightLayout = true
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 340
        let contentController = NSViewController()
        contentController.view = pageContainer
        pageContainer.frame.size = NSSize(width: Self.windowDefaultSize.width - Self.sidebarDefaultWidth,
                                          height: Self.windowDefaultSize.height)
        splitController.addSplitViewItem(sidebarItem)
        splitController.addSplitViewItem(NSSplitViewItem(viewController: contentController))
        window.contentViewController = splitController
        window.contentMinSize = Self.windowMinimumSize
        window.contentMaxSize = Self.windowMaximumSize

        let toolbar = NSToolbar(identifier: "AccountsWindowToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar

        window.initialFirstResponder = table
        window.setContentSize(fittedContentSize(Self.windowDefaultSize))
        table.sizeLastColumnToFit()
        installPage(home)
        render()
    }

    private func makeSidebarView() -> NSView {
        let accountColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("account"))
        accountColumn.resizingMask = .autoresizingMask
        table.addTableColumn(accountColumn)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.style = .sourceList
        table.rowSizeStyle = .default
        table.allowsEmptySelection = true
        table.setAccessibilityLabel("Sidebar")
        table.setAccessibilityHelp("Select Home, Models, or an account. Drag an account, or choose Move Up or Move Down, to change its order. Use Add Account below the list. Delete asks for confirmation.")
        table.registerForDraggedTypes([Self.accountPasteboardType])
        table.setDraggingSourceOperationMask(.move, forLocal: true)
        table.draggingDestinationFeedbackStyle = .gap
        table.target = self
        table.action = #selector(selectClickedSidebarRow(_:))
        table.accountMenu = { [weak self] row in self?.accountContextMenu(row: row) }
        table.removeSelectedAccount = { [weak self] in self?.removeSelectedAccount(nil) }
        let accountScroll = NSScrollView()
        accountScroll.documentView = table
        accountScroll.hasVerticalScroller = true
        accountScroll.autohidesScrollers = true
        accountScroll.drawsBackground = false
        accountScroll.translatesAutoresizingMaskIntoConstraints = false

        for (button, symbol, label, action) in [
            (addAccountButton, "plus", "Add Account", #selector(addAccount(_:))),
            (removeAccountButton, "minus", "Delete Account", #selector(removeSelectedAccount(_:)))
        ] {
            button.target = self
            button.action = action
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            button.imagePosition = .imageOnly
            button.bezelStyle = .texturedRounded
            button.toolTip = label
            button.setAccessibilityLabel(label)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true
            button.heightAnchor.constraint(equalToConstant: 28).isActive = true
        }
        let sidebarActions = NSStackView(views: [addAccountButton, removeAccountButton])
        sidebarActions.orientation = .horizontal
        sidebarActions.alignment = .centerY
        sidebarActions.spacing = 6
        sidebarActions.translatesAutoresizingMaskIntoConstraints = false
        let sidebar = NSView()
        sidebar.addSubview(accountScroll)
        sidebar.addSubview(sidebarActions)
        // The list scrolls under the toolbar with automatic insets; add and remove sit directly under it.
        NSLayoutConstraint.activate([
            accountScroll.topAnchor.constraint(equalTo: sidebar.topAnchor),
            accountScroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            accountScroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            accountScroll.bottomAnchor.constraint(equalTo: sidebarActions.topAnchor, constant: -8),
            sidebarActions.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            sidebarActions.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -12)
        ])
        return sidebar
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
        if profilesChanged || table.numberOfRows != displayedProfiles.count + Self.accountRowOffset {
            sidebarDisplays = nextDisplays
            table.reloadData()
        } else {
            for (index, profile) in displayedProfiles.enumerated() where sidebarDisplays[profile.id] != nextDisplays[profile.id] {
                if let display = nextDisplays[profile.id] {
                    let row = index + Self.accountRowOffset
                    (table.view(atColumn: 0, row: row, makeIfNecessary: false) as? AccountSidebarCellView)?.render(display)
                }
            }
            sidebarDisplays = nextDisplays
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
        case .models:
            if let selectedID, !model.profiles.contains(where: { $0.id == selectedID }) { self.selectedID = nil }
            if table.numberOfRows > Self.modelsRow {
                table.selectRowIndexes(IndexSet(integer: Self.modelsRow), byExtendingSelection: false)
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
        addAccountButton.isEnabled = canModifyAccounts && isAccountLoadComplete() && !model.hasAccountLoadFailure
        detail.render(accountID: selectedID)
        updateRemoveAvailability()
        updateToolbar()
        if section == .home {
            window?.contentView?.layoutSubtreeIfNeeded()
            home.render()
        }
    }

    // MARK: Pages

    private var visiblePage: NSViewController {
        switch section {
        case .home: home
        case .models: models
        case .account: detail
        case .settings: settings
        case .platform: platform ?? detail
        }
    }

    /// Pins `page` to every edge of the content area, under the toolbar, and removes the previous page.
    private func installPage(_ page: NSViewController) {
        for view in pageContainer.subviews where view !== page.view { view.removeFromSuperview() }
        guard page.view.superview !== pageContainer else { return }
        page.view.translatesAutoresizingMaskIntoConstraints = false
        pageContainer.addSubview(page.view)
        NSLayoutConstraint.activate([
            page.view.leadingAnchor.constraint(equalTo: pageContainer.leadingAnchor),
            page.view.trailingAnchor.constraint(equalTo: pageContainer.trailingAnchor),
            page.view.topAnchor.constraint(equalTo: pageContainer.topAnchor),
            page.view.bottomAnchor.constraint(equalTo: pageContainer.bottomAnchor)
        ])
    }

    func showHome() {
        guard window?.attachedSheet == nil else { return }
        let entering = section != .home
        leavePlatform()
        installPage(home)
        setSection(.home)
        render()
        guard entering, let window, window.isVisible else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        if !home.focusInitialControl() { window.makeFirstResponder(table) }
    }

    func showModels() {
        guard window?.attachedSheet == nil else { return }
        leavePlatform()
        hideHome()
        installPage(models)
        setSection(.models)
        render()
        window?.recalculateKeyViewLoop()
        // The page has no controls of its own, so focus stays in the sidebar.
        window?.makeFirstResponder(table)
    }

    func showSettings() {
        guard window?.attachedSheet == nil else { return }
        leavePlatform()
        hideHome()
        installPage(settings)
        settings.refresh()
        setSection(.settings)
        isUpdatingSelection = true
        table.deselectAll(nil)
        isUpdatingSelection = false
        window?.recalculateKeyViewLoop()
        settings.focusInitialControl()
    }

    func showPlatform(_ controller: ClaudePlatformViewController, accountID: UUID) {
        guard window?.attachedSheet == nil else { return }
        leavePlatform()
        hideHome()
        selectedID = accountID
        platform = controller
        controller.onBack = { [weak self] in self?.showAccountDetail(); self?.render() }
        installPage(controller)
        setSection(.platform)
        controller.presentPane()
        render()
        window?.recalculateKeyViewLoop()
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
        installPage(detail)
        setSection(.account)
        window?.recalculateKeyViewLoop()
    }

    func showAccount(id: UUID) {
        guard window?.attachedSheet == nil, model.profiles.contains(where: { $0.id == id }) else { return }
        selectedID = id
        showAccountDetail()
        render()
    }

    func reconnectAccount(id: UUID) {
        guard canModifyAccounts, window?.attachedSheet == nil,
              let profile = model.profiles.first(where: { $0.id == id }) else { return }
        if profile.provider == .claude { onClaudeConnection?(id, InterfaceFormatting.accountIdentity(profile)) }
        else { model.signInCodex(id) }
    }

    private func setSection(_ newSection: Section) {
        section = newSection
        updateRemoveAvailability()
        updateToolbar()
    }

    // MARK: Toolbar

    private var currentToolbarContributor: (any WindowToolbarContributor)? {
        switch section {
        case .home, .models, .account: visiblePage as? any WindowToolbarContributor
        case .settings, .platform: nil
        }
    }

    /// Rebuilds the page items after the sidebar tracking separator when the page or its item set changes,
    /// then updates the title and subtitle.
    private func updateToolbar() {
        guard let window else { return }
        let contributor = currentToolbarContributor
        let identifiers = contributor?.toolbarItemIdentifiers ?? []
        if let toolbar = window.toolbar, contributor !== toolbarContributor || identifiers != toolbarPageIdentifiers {
            toolbarContributor = contributor
            toolbarPageIdentifiers = identifiers
            while toolbar.items.count > Self.fixedToolbarItems.count { toolbar.removeItem(at: toolbar.items.count - 1) }
            for identifier in identifiers { toolbar.insertItem(withItemIdentifier: identifier, at: toolbar.items.count) }
        }
        let title: String
        var subtitle = contributor?.windowSubtitle ?? ""
        switch section {
        case .home: title = "Home"
        case .models: title = "Models"
        case .settings: title = "Settings"
        case .account, .platform:
            title = model.profiles.first(where: { $0.id == selectedID }).map(distinctIdentity) ?? "Accounts"
            if section == .platform { subtitle = "API Credits" }
        }
        if window.title != title { window.title = title }
        if window.subtitle != subtitle { window.subtitle = subtitle }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.fixedToolbarItems + toolbarPageIdentifiers
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Self.fixedToolbarItems + [.flexibleSpace, .space] + toolbarPageIdentifiers
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        toolbarContributor?.makeToolbarItem(itemIdentifier)
    }

    // MARK: Window

    func windowWillClose(_ notification: Notification) {
        platform?.hidePane(pauseRefresh: true)
        if home.isViewLoaded { home.dismissDetails() }
    }

    override func showWindow(_ sender: Any?) {
        let wasVisible = window?.isVisible == true
        if section == .platform { platform?.presentPane() }
        super.showWindow(sender)
        if opensModelsOnFirstShow {
            opensModelsOnFirstShow = false
            showModels()
        }
        guard section == .home, !wasVisible else { return }
        window?.contentView?.layoutSubtreeIfNeeded()
        if !home.focusInitialControl() { window?.makeFirstResponder(table) }
    }

    /// View > Show Account items while Home shows; empty on other pages, where the filter does not apply.
    func accountFilterMenuItems() -> [NSMenuItem] {
        section == .home ? home.accountFilterMenuItems() : []
    }

    private func fittedContentSize(_ proposed: NSSize) -> NSSize {
        let bounded = NSSize(width: min(max(proposed.width, Self.windowMinimumSize.width), Self.windowMaximumSize.width),
                             height: min(max(proposed.height, Self.windowMinimumSize.height), Self.windowMaximumSize.height))
        guard let window, let visible = (window.screen ?? NSScreen.main)?.visibleFrame else { return bounded }
        let chrome = window.frame.height - window.contentRect(forFrameRect: window.frame).height
        return NSSize(width: min(bounded.width, max(Self.windowMinimumSize.width, visible.width - 24)),
                      height: min(bounded.height, max(Self.windowMinimumSize.height, visible.height - max(28, chrome) - 8)))
    }

    // MARK: Sidebar

    func numberOfRows(in tableView: NSTableView) -> Int { displayedProfiles.count + Self.accountRowOffset }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if row == Self.homeRow {
            let identifier = NSUserInterfaceItemIdentifier("home")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? HomeSidebarCellView ?? HomeSidebarCellView()
            cell.identifier = identifier
            return cell
        }
        if row == Self.modelsRow {
            let identifier = NSUserInterfaceItemIdentifier("models")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? ModelsSidebarCellView ?? ModelsSidebarCellView()
            cell.identifier = identifier
            return cell
        }
        guard let index = profileIndex(forSidebarRow: row), let display = sidebarDisplays[displayedProfiles[index].id] else { return nil }
        let identifier = NSUserInterfaceItemIdentifier("account")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? AccountSidebarCellView ?? AccountSidebarCellView()
        cell.identifier = identifier
        cell.render(display)
        return cell
    }

    private func sidebarDisplay(profile: AccountProfile, now: Date) -> AccountSidebarCellView.Display {
        let snapshot = model.snapshots[profile.id]
        let summary = AccountQuotaSummary(snapshot: snapshot, accountID: profile.id, now: now)
        let lastRead = snapshot.flatMap { $0.profileID == profile.id ? $0.fetchedAt : nil }
        var text: String
        var indicator = AccountSidebarCellView.Indicator.none
        var state: String
        switch summary {
        case let .available(remaining, _, windowTitle):
            let window = snapshot?.currentWindows.first(where: { $0.title == windowTitle }).map(InterfaceFormatting.usageTitle) ?? windowTitle
            var value = "\(Self.remainingText(remaining)) left"
            if remaining <= 0 { value += ", Limit reached"; indicator = .limitReached }
            else if remaining <= 20 { value += ", Low"; indicator = .low }
            text = "\(value) · \(window)"
            state = "\(value). Lowest remaining current quota: \(window)."
        case .unknown:
            text = "Unavailable"
            state = "Unavailable. A complete current usage reading is not available."
        case .inactive:
            text = "Inactive"
            state = "Inactive. All reported quota windows are inactive."
        case .stale:
            indicator = .stale
            text = lastRead.map { "Stale · last read \(Self.shortTime($0))" } ?? "Stale"
            state = "Stale. The last reading is at least five minutes old or a reset has passed. Choose Refresh All to check usage."
        case .unavailable:
            text = "Unavailable"
            state = "Unavailable. The provider could not supply current usage."
        case .authenticationRequired:
            indicator = .signInRequired
            text = "Sign-in required"
            state = "Sign-in required. Choose Reconnect… on the account page."
        }
        if model.isAwaitingCodexSignIn(profile.id) {
            indicator = .none
            text = "Waiting for sign-in"
            state = "Waiting for Codex sign-in in Terminal."
        }
        var description = "\(InterfaceFormatting.provider(profile.provider)), \(InterfaceFormatting.accountIdentity(profile)). \(state)"
        if let lastRead { description += " Last read \(InterfaceFormatting.exactDate(lastRead))." }
        if InterfaceFormatting.accountEmail(profile) == "Email unavailable" { description += " Email unavailable." }
        return AccountSidebarCellView.Display(identity: distinctIdentity(profile), provider: profile.provider,
                                              quotaText: text, indicator: indicator, description: description)
    }

    /// The identity, prefixed with the provider when another saved account shows the same identity, as the
    /// status menu heading does: `Claude · parker@example.invalid`.
    private func distinctIdentity(_ profile: AccountProfile) -> String {
        let identity = InterfaceFormatting.accountIdentity(profile)
        let shared = model.profiles.contains {
            $0.id != profile.id && InterfaceFormatting.accountIdentity($0).caseInsensitiveCompare(identity) == .orderedSame
        }
        return shared ? "\(InterfaceFormatting.provider(profile.provider)) · \(identity)" : identity
    }

    private static func remainingText(_ remaining: Double) -> String {
        if remaining == remaining.rounded() { return String(format: "%.0f%%", remaining) }
        // Keep the displayed side of each status boundary accurate after rounding.
        if remaining > 20, remaining < 20.1 { return ">20%" }
        if remaining > 0, remaining < 0.1 { return "<0.1%" }
        return String(format: "%.1f%%", remaining)
    }

    private static func shortTime(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }

    /// Home and Models keep the system sidebar row height; account rows add the quota line below the identity.
    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard row >= Self.accountRowOffset else { return tableView.rowHeight }
        let identitySize: CGFloat = switch tableView.effectiveRowSizeStyle {
        case .small: 11
        case .large: 15
        default: NSFont.systemFontSize
        }
        let quotaFont = AccountSidebarCellView.quotaFont(identitySize: identitySize)
        return tableView.rowHeight + ceil(NSLayoutManager().defaultLineHeight(for: quotaFont)) + AccountSidebarCellView.lineSpacing
    }

    /// Choosing the selected account row again returns from the Platform pane to the account page. Selection does not
    /// change in that case, so `tableViewSelectionDidChange(_:)` is not called.
    @objc private func selectClickedSidebarRow(_ sender: Any?) {
        let row = table.clickedRow
        guard section == .platform, row == table.selectedRow, let id = accountID(forSidebarRow: row), id == selectedID else { return }
        showAccountDetail()
        render()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isUpdatingSelection else { return }
        let row = table.selectedRow
        if row == Self.homeRow {
            showHome()
            return
        }
        if row == Self.modelsRow {
            showModels()
            return
        }
        guard let accountID = accountID(forSidebarRow: row) else { return }
        selectedID = accountID
        showAccountDetail()
        detail.render(accountID: accountID)
        updateRemoveAvailability()
        updateToolbar()
    }

    private func updateRemoveAvailability() {
        removeAccountButton.isEnabled = canModifyAccounts && selectedSidebarAccountID != nil && window?.attachedSheet == nil
    }

    // MARK: Account changes

    /// Status menu Add Claude Account… and Add Codex Account… open the provider sheet with that provider chosen.
    func connect(_ provider: Provider) {
        presentAddAccountSheet(provider: provider)
    }

    /// File > Add Account… and the sidebar plus button.
    @objc func addAccount(_ sender: Any?) {
        presentAddAccountSheet(provider: .claude)
    }

    private func presentAddAccountSheet(provider: Provider) {
        guard canModifyAccounts, isAccountLoadComplete(), !model.hasAccountLoadFailure,
              let window, window.attachedSheet == nil else { return }
        AddAccountSheetController(provider: provider).present(in: window) { [weak self] provider in
            self?.beginAccountConnection(provider)
        }
    }

    private func beginAccountConnection(_ provider: Provider) {
        guard canModifyAccounts, isAccountLoadComplete(), !model.hasAccountLoadFailure else { return }
        if provider == .claude { onClaudeConnection?(nil, "Claude Account") }
        else { model.importAccount(provider: provider, label: "Codex Account") }
    }

    func windowWillBeginSheet(_ notification: Notification) { updateRemoveAvailability() }
    func windowDidEndSheet(_ notification: Notification) { updateRemoveAvailability() }

    private var canModifyAccounts: Bool { !model.isDemo && !model.isChangingAccounts && !model.isRefreshing }

    private func accountContextMenu(row: Int) -> NSMenu? {
        guard let id = accountID(forSidebarRow: row) else { return nil }
        let menu = NSMenu()
        menu.autoenablesItems = false
        let canChange = canModifyAccounts && window?.attachedSheet == nil
        let index = displayedProfiles.firstIndex { $0.id == id }
        for (title, action, key, enabled) in [
            ("Move Up", #selector(moveAccountUpFromMenu(_:)), NSUpArrowFunctionKey, (index ?? 0) > 0),
            ("Move Down", #selector(moveAccountDownFromMenu(_:)), NSDownArrowFunctionKey, (index ?? displayedProfiles.count) < displayedProfiles.count - 1)
        ] {
            let move = NSMenuItem(title: title, action: action, keyEquivalent: String(UnicodeScalar(key)!))
            move.keyEquivalentModifierMask = [.command, .option]
            move.target = self
            move.representedObject = id
            move.isEnabled = canChange && enabled
            menu.addItem(move)
        }
        menu.addItem(.separator())
        let menuBar = NSMenuItem(title: "Show in Menu Bar", action: #selector(toggleMenuBarFromMenu(_:)), keyEquivalent: "")
        menuBar.target = self
        menuBar.representedObject = id
        menuBar.state = model.showsInMenuBar(id) ? .on : .off
        menu.addItem(menuBar)
        menu.addItem(.separator())
        let item = NSMenuItem(title: "Delete", action: #selector(removeAccountFromMenu(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = id
        item.isEnabled = canChange
        menu.addItem(item)
        return menu
    }

    /// The account selected in the sidebar while its account page or Platform pane shows.
    private var selectedSidebarAccountID: UUID? {
        guard section == .account || section == .platform else { return nil }
        return accountID(forSidebarRow: table.selectedRow)
    }

    /// File > Delete Account…, the sidebar minus button, and the Delete key. Asks for confirmation.
    @objc func removeSelectedAccount(_ sender: Any?) {
        guard let id = selectedSidebarAccountID else { return }
        confirmAccountRemoval(id: id)
    }

    /// File > Reconnect… for the selected account; the same route as the account page Reconnect… item.
    @objc func reconnectSelectedAccount(_ sender: Any?) {
        guard let id = selectedSidebarAccountID else { return }
        reconnectAccount(id: id)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(removeSelectedAccount(_:)):
            canModifyAccounts && window?.attachedSheet == nil && selectedSidebarAccountID != nil
        case #selector(reconnectSelectedAccount(_:)):
            canModifyAccounts && window?.attachedSheet == nil
                && selectedSidebarAccountID.flatMap { id in model.profiles.first { $0.id == id } }.map { $0.source != .codexDefaultLogin } == true
        case #selector(addAccount(_:)):
            canModifyAccounts && isAccountLoadComplete() && !model.hasAccountLoadFailure && window?.attachedSheet == nil
        case #selector(moveSelectedAccountUp(_:)):
            canMoveSelectedAccount(by: -1)
        case #selector(moveSelectedAccountDown(_:)):
            canMoveSelectedAccount(by: 1)
        default: true
        }
    }

    @objc private func toggleMenuBarFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        model.setShowsInMenuBar(!model.showsInMenuBar(id), for: id)
    }

    @objc private func removeAccountFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        confirmAccountRemoval(id: id)
    }

    private func confirmAccountRemoval(id: UUID) {
        guard canModifyAccounts, let window, window.attachedSheet == nil,
              let profile = model.profiles.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete \(InterfaceFormatting.accountIdentity(profile))?"
        alert.informativeText = "Removes this profile and its saved usage from AI Usage Stats."
        alert.addButton(withTitle: "Delete")
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
        alert.messageText = "Could Not Delete Account"
        alert.informativeText = model.isDemo ? "Demo accounts cannot be deleted."
            : model.isRefreshing ? "Usage is refreshing. Delete the account again after the refresh finishes."
            : "An account update is in progress. Delete the account again after the update finishes."
        if let window { alert.beginSheetModal(for: window) }
    }

    // MARK: Reordering

    /// File > Move Up and Move Down act on the selected account.
    @objc func moveSelectedAccountUp(_ sender: Any?) { moveSelectedAccount(by: -1) }
    @objc func moveSelectedAccountDown(_ sender: Any?) { moveSelectedAccount(by: 1) }
    @objc private func moveAccountUpFromMenu(_ sender: NSMenuItem) { moveAccount(representedBy: sender, by: -1) }
    @objc private func moveAccountDownFromMenu(_ sender: NSMenuItem) { moveAccount(representedBy: sender, by: 1) }

    private func moveSelectedAccount(by offset: Int) {
        guard let id = selectedSidebarAccountID else { return }
        moveAccount(id: id, by: offset)
    }

    private func moveAccount(representedBy item: NSMenuItem, by offset: Int) {
        guard let id = item.representedObject as? UUID else { return }
        moveAccount(id: id, by: offset)
    }

    private func canMoveSelectedAccount(by offset: Int) -> Bool {
        guard canModifyAccounts, window?.attachedSheet == nil, let id = selectedSidebarAccountID,
              let index = displayedProfiles.firstIndex(where: { $0.id == id }) else { return false }
        return displayedProfiles.indices.contains(index + offset)
    }

    private func moveAccount(id: UUID, by offset: Int) {
        guard let index = displayedProfiles.firstIndex(where: { $0.id == id }) else { return }
        moveAccount(id: id, toIndex: index + offset)
    }

    /// Slides the row to `index` in the saved account order, then saves it. Selection, page, and edits stay with the UUID.
    private func moveAccount(id: UUID, toIndex index: Int) {
        guard canModifyAccounts, window?.attachedSheet == nil,
              let source = displayedProfiles.firstIndex(where: { $0.id == id }),
              displayedProfiles.indices.contains(index), index != source else { return }
        isUpdatingSelection = true
        table.beginUpdates()
        displayedProfiles.insert(displayedProfiles.remove(at: source), at: index)
        table.moveRow(at: source + Self.accountRowOffset, to: index + Self.accountRowOffset)
        table.endUpdates()
        if section == .account || section == .platform, let selectedID, let row = sidebarRow(for: selectedID) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        isUpdatingSelection = false
        model.moveAccount(id: id, toIndex: index)
    }

    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
        guard canModifyAccounts, let id = accountID(forSidebarRow: row) else { return nil }
        let item = NSPasteboardItem()
        item.setString(id.uuidString, forType: Self.accountPasteboardType)
        return item
    }

    private func draggedAccountID(_ info: any NSDraggingInfo) -> UUID? {
        info.draggingPasteboard.string(forType: Self.accountPasteboardType).flatMap(UUID.init(uuidString:))
    }

    /// A drop lands between account rows, never on a row and never above Home.
    func tableView(_ tableView: NSTableView, validateDrop info: any NSDraggingInfo, proposedRow row: Int,
                   proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
        guard info.draggingSource as? NSTableView === tableView, canModifyAccounts, window?.attachedSheet == nil,
              let id = draggedAccountID(info), let source = displayedProfiles.firstIndex(where: { $0.id == id }) else { return [] }
        let gap = min(max(row, Self.accountRowOffset), displayedProfiles.count + Self.accountRowOffset)
        if gap != row || dropOperation != .above { tableView.setDropRow(gap, dropOperation: .above) }
        let insertion = gap - Self.accountRowOffset
        return insertion == source || insertion == source + 1 ? [] : .move
    }

    func tableView(_ tableView: NSTableView, acceptDrop info: any NSDraggingInfo, row: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {
        guard let id = draggedAccountID(info), let source = displayedProfiles.firstIndex(where: { $0.id == id }) else { return false }
        let insertion = row - Self.accountRowOffset
        let destination = insertion > source ? insertion - 1 : insertion
        guard destination != source else { return false }
        moveAccount(id: id, toIndex: destination)
        return true
    }

    // Row 0 is Home and row 1 is Models. Later rows follow the saved account order and are addressed by UUID.
    private func profileIndex(forSidebarRow row: Int) -> Int? {
        let index = row - Self.accountRowOffset
        guard displayedProfiles.indices.contains(index) else { return nil }
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

/// Offers the visible page as a supplemental action target, so menu commands such as Home's period commands and
/// the account page's Open Billing reach that page while keyboard focus is in the sidebar.
@MainActor
private final class PageCommandSplitViewController: NSSplitViewController {
    private static let pageActions: Set<Selector> = [
        #selector(WindowCommandHandling.showPreviousPeriod(_:)),
        #selector(WindowCommandHandling.showNextPeriod(_:)),
        #selector(WindowCommandHandling.showCurrentPeriod(_:)),
        #selector(WindowCommandHandling.showMonthPeriod(_:)),
        #selector(WindowCommandHandling.showTwoWeekPeriod(_:)),
        #selector(WindowCommandHandling.chooseAccountSortOrder(_:)),
        #selector(WindowCommandHandling.openSelectedAccountBilling(_:)),
        #selector(WindowCommandHandling.refreshSelectedAccount(_:))
    ]
    var commandPage: (() -> NSViewController?)?

    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if Self.pageActions.contains(action), let page = commandPage?(), page.responds(to: action) { return page }
        return super.supplementalTarget(forAction: action, sender: sender)
    }
}
