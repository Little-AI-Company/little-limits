import AppKit
import UsageCore
import UsageHistory

extension NSToolbarItem.Identifier {
    static let homePeriodNavigation = NSToolbarItem.Identifier("home.periodNavigation")
    static let homeToday = NSToolbarItem.Identifier("home.today")
    static let homeAccountFilter = NSToolbarItem.Identifier("home.accountFilter")
    static let homePeriodLength = NSToolbarItem.Identifier("home.periodLength")
    static let homeRefreshAll = NSToolbarItem.Identifier("home.refreshAll")
}

/// Home: weekly totals, the forecast, then the account table, then the reset calendar, in one scrolling document. Period
/// navigation, the account filter, period length, and Refresh All are window toolbar items; View > Sort Accounts
/// orders the table. Mode, date, filter, sort order, and event selection survive refresh.
@MainActor
final class HomeViewController: NSViewController, NSPopoverDelegate, NSMenuItemValidation,
                                WindowToolbarContributor, WindowCommandHandling {
    var onViewAccount: ((UUID) -> Void)?
    var onReconnectAccount: ((UUID) -> Void)?
    var onRetryAccountLoad: (() -> Void)?
    /// Direct route for the empty-state add buttons. Without it they send `addAccount(_:)` up the responder chain.
    var onAddAccount: ((Provider) -> Void)?
    var isAccountLoadComplete: () -> Bool = { false }
    var onToolbarStateChange: (() -> Void)?

    private(set) var toolbarItemIdentifiers: [NSToolbarItem.Identifier] = []
    private(set) var windowSubtitle = ""

    private let model: ApplicationModel
    private var mode: UsageCalendarMode = .twoWeeks
    private var anchor = Date()
    private var filter: AccountFilter = .all
    private var sortOrder: AccountSortOrder = .saved
    private var filterChoices: [FilterChoice] = []
    private var showsReadings = false
    private var overview = UsageOverview(profiles: [], snapshots: [:])
    private var visibleEvents: [UsageResetEvent] = []
    private var attentionItems: [HomeAttentionItem] = []
    private var displayedNow = Date()
    private var displayedCalendar = Calendar.current
    private var pinnedEventID: String?
    private var presentedEventID: String?
    private var suppressedReturn: NSEvent?
    private var handledClickStamp: TimeInterval?
    private var toolbarItems: [NSToolbarItem.Identifier: NSToolbarItem] = [:]
    private let popover = NSPopover()
    private let details = UsageEventDetailsViewController()
    private let calendarView = UsageCalendarView()
    private let tableView = UsageOverviewTableView()
    private let totalsView = HomeTotalsView()
    private let forecastView = HomeForecastView()
    private let forecastHistory: HomeForecastHistory
    private var forecastRange: HomeForecastRange = .nextWeek
    private var totalsTitle: NSTextField?
    private let contextLabel = NSTextField(labelWithString: "")
    private let attentionStack = NSStackView()
    private let emptyPeriodLabel = NSTextField(labelWithString: HomeInterfaceFormatting.emptyPeriodText)
    private let stateTitle = NSTextField(labelWithString: "")
    private let stateMessage = NSTextField(wrappingLabelWithString: "")
    private let stateDetail = NSTextField(wrappingLabelWithString: "")
    private let addClaudeButton = NSButton(title: "Add Claude Account…", target: nil, action: nil)
    private let addCodexButton = NSButton(title: "Add Codex Account…", target: nil, action: nil)
    private let addButtons = NSStackView()
    private let retryButton = NSButton(title: "Retry Loading Accounts", target: nil, action: nil)
    private let demoLabel = NSTextField(labelWithString: "Example accounts")
    private let readings = NSStackView()
    private let stateStack = NSStackView()
    private let scroll = NSScrollView()
    /// Keeps a short document at the top of the visible area. Its constant removes the toolbar inset,
    /// so a page that fits does not scroll by the toolbar height.
    private var minimumDocumentHeight: NSLayoutConstraint?

    init(model: ApplicationModel) {
        self.model = model
        if let database = model.historyDatabase {
            forecastHistory = HomeForecastHistory(source: .database(database))
        } else if model.isDemo {
            forecastHistory = HomeForecastHistory(source: CommandLine.arguments.contains("--demo-home") ? .demonstration
                : .unavailable("The demonstration has no quota history."))
        } else {
            forecastHistory = HomeForecastHistory(source: .unavailable(model.historyDatabaseError ?? "Quota history is unavailable."))
        }
        super.init(nibName: nil, bundle: nil)
        forecastHistory.onChange = { [weak self] in self?.renderForecast() }
        forecastView.onRangeChange = { [weak self] range in
            self?.forecastRange = range
            self?.renderForecast()
        }
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        configureControls()
        configurePopover()
        let document = HomeDocumentView()
        scroll.documentView = document
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        document.translatesAutoresizingMaskIntoConstraints = false
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.detachesHiddenViews = true
        column.translatesAutoresizingMaskIntoConstraints = false
        readings.orientation = .vertical
        readings.alignment = .leading
        readings.spacing = 8
        readings.detachesHiddenViews = true
        readings.translatesAutoresizingMaskIntoConstraints = false
        attentionStack.orientation = .vertical
        attentionStack.alignment = .leading
        attentionStack.spacing = 4
        attentionStack.detachesHiddenViews = true
        attentionStack.setAccessibilityElement(true)
        attentionStack.setAccessibilityRole(.group)
        attentionStack.setAccessibilityLabel("Accounts needing attention")
        let totalsTitle = sectionTitle("Weekly Totals")
        self.totalsTitle = totalsTitle
        let tableTitle = sectionTitle("Account Usage")
        let calendarTitle = sectionTitle("Reset Calendar")
        for item in [totalsTitle, totalsView, forecastView, tableTitle, contextLabel, attentionStack, tableView, calendarTitle, emptyPeriodLabel,
                     calendarView, demoLabel] {
            readings.addArrangedSubview(item)
        }
        readings.setCustomSpacing(16, after: totalsView)
        readings.setCustomSpacing(16, after: forecastView)
        readings.setCustomSpacing(16, after: tableView)
        stateStack.orientation = .vertical
        stateStack.alignment = .leading
        stateStack.spacing = 8
        stateStack.detachesHiddenViews = true
        stateStack.translatesAutoresizingMaskIntoConstraints = false
        stateTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        stateMessage.font = .systemFont(ofSize: 13)
        stateMessage.preferredMaxLayoutWidth = 420
        stateDetail.font = .systemFont(ofSize: 11)
        stateDetail.textColor = .secondaryLabelColor
        stateDetail.isSelectable = true
        stateDetail.preferredMaxLayoutWidth = 420
        addButtons.orientation = .horizontal
        addButtons.spacing = 8
        addButtons.addArrangedSubview(addClaudeButton)
        addButtons.addArrangedSubview(addCodexButton)
        for item in [stateTitle, stateMessage, stateDetail, addButtons, retryButton] {
            stateStack.addArrangedSubview(item)
        }
        column.addArrangedSubview(readings)
        column.addArrangedSubview(stateStack)
        document.addSubview(column)
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            column.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -16),
            column.topAnchor.constraint(equalTo: document.topAnchor, constant: 16),
            column.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -16),
            readings.widthAnchor.constraint(equalTo: column.widthAnchor),
            stateStack.widthAnchor.constraint(equalTo: column.widthAnchor),
            calendarView.widthAnchor.constraint(equalTo: readings.widthAnchor),
            tableView.widthAnchor.constraint(equalTo: readings.widthAnchor),
            attentionStack.widthAnchor.constraint(equalTo: readings.widthAnchor),
            totalsView.widthAnchor.constraint(equalTo: readings.widthAnchor),
            forecastView.widthAnchor.constraint(equalTo: readings.widthAnchor),
            stateMessage.widthAnchor.constraint(lessThanOrEqualTo: stateStack.widthAnchor),
            stateDetail.widthAnchor.constraint(lessThanOrEqualTo: stateStack.widthAnchor)
        ])
        let minimumHeight = document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor)
        minimumHeight.isActive = true
        minimumDocumentHeight = minimumHeight
        let fit = column.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16)
        fit.priority = .defaultHigh
        fit.isActive = true
        view = scroll
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        let insets = scroll.contentInsets
        let constant = -(insets.top + insets.bottom)
        if let minimumDocumentHeight, minimumDocumentHeight.constant != constant {
            minimumDocumentHeight.constant = constant
        }
    }

    func render() {
        if !isViewLoaded { _ = view }
        let now = Date()
        let calendar = Calendar.current
        displayedNow = now
        displayedCalendar = calendar
        overview = UsageOverview(profiles: model.profiles, snapshots: model.snapshots, now: now)
        if case .account(let id) = filter, !overview.accounts.contains(where: { $0.id == id }) {
            filter = .all
        }
        filterChoices = overview.accounts.map { FilterChoice(id: $0.id, title: "\($0.profile.provider.title) \($0.shortIdentity)") }
        let period = UsageCalendarPeriod(mode: mode, containing: anchor, calendar: calendar)
        visibleEvents = filteredEvents(overview.resetEvents)
        let hasAccounts = !overview.accounts.isEmpty
        let failed = model.hasAccountLoadFailure
        let loaded = isAccountLoadComplete()
        showsReadings = hasAccounts && !failed
        readings.isHidden = !showsReadings
        stateStack.isHidden = showsReadings
        applyPlaceholder(loaded: loaded, failed: failed, hasAccounts: hasAccounts)
        publishToolbarState(subtitle: showsReadings
            ? HomeInterfaceFormatting.periodTitle(mode: mode, period: period, anchor: anchor, calendar: calendar) : "")
        guard showsReadings else {
            if popover.isShown { dismissDetails() }
            return
        }
        let accounts = overview.accounts.filter { account in
            switch filter {
            case .all: true
            case .account(let id): account.id == id
            }
        }
        // Totals pool every account, whatever the filter shows.
        let totals = HomeInterfaceFormatting.totalLines(overview, now: now, calendar: calendar)
        totalsView.apply(totals)
        totalsView.isHidden = totals.isEmpty
        totalsTitle?.isHidden = totals.isEmpty
        forecastHistory.observe(now: now, profiles: model.profiles, snapshots: model.snapshots)
        renderForecast()
        contextLabel.stringValue = HomeInterfaceFormatting.readingContext(now: now, calendar: calendar)
        applyAttention(HomeInterfaceFormatting.attentionItems(accounts, now: now))
        syncAttentionReconnect()
        demoLabel.isHidden = !model.isDemo
        let placed = HomeInterfaceFormatting.calendarEvents(visibleEvents, days: period.days, now: now, calendar: calendar)
        emptyPeriodLabel.isHidden = !placed.isEmpty
        tableView.apply(rows: HomeInterfaceFormatting.rows(for: sortOrder.sorted(accounts, now: now), now: now, calendar: calendar),
                        headings: HomeInterfaceFormatting.headings(for: accounts))
        calendarView.apply(period: period, events: visibleEvents, mode: mode, anchor: anchor, now: now, calendar: calendar)
        refreshPresentedDetails()
    }

    /// The forecast pools every account, whatever the filter shows. It also redraws alone when recorded history
    /// changes or the range changes.
    private func renderForecast() {
        guard isViewLoaded, showsReadings else { return }
        let now = Date()
        let forecasts = HomeForecastModel.providers(overview: overview, readings: forecastHistory.readings,
                                                    latestReadings: forecastHistory.latestReadings, range: forecastRange, now: now, calendar: .current)
        // With no history for any provider, one line replaces the whole forecast.
        let noHistory = forecasts.allSatisfy { $0.lines.isEmpty && $0.chart == nil }
        forecastView.apply(forecasts, notice: forecastHistory.unavailableReason ?? (noHistory ? HomeForecastModel.noHistoryText : nil),
                           range: forecastRange)
    }

    /// Focuses the page's main action when there is one: Add Claude Account… on an empty page, Retry on a load
    /// failure. With readings, the page takes no focus and returns false, so the window keeps focus on the
    /// sidebar Home row; no calendar event looks selected on arrival, and Tab reaches the events after it.
    @discardableResult
    func focusInitialControl() -> Bool {
        if !isViewLoaded { _ = view }
        guard let window = view.window, !showsReadings else { return false }
        for button in [addClaudeButton, retryButton] where !stateStack.isHidden && !button.isHiddenOrHasHiddenAncestor && button.isEnabled {
            window.makeFirstResponder(button)
            return true
        }
        return false
    }

    /// View > Show Account: All Accounts, then one item per account, sent to this page and checked by
    /// `validateMenuItem(_:)`. The same choices as the toolbar Accounts pop-up.
    func accountFilterMenuItems() -> [NSMenuItem] {
        let menu = filterMenu(titles: ["All Accounts"] + filterChoices.map(\.title), action: #selector(chooseFilter(_:)))
        let items = menu.items
        menu.removeAllItems()
        return items
    }

    func dismissDetails() {
        guard isViewLoaded else { return }
        pinnedEventID = nil
        presentedEventID = nil
        if popover.isShown {
            popover.close()
        } else {
            restoreSelectedFocus()
        }
    }

    override func cancelOperation(_ sender: Any?) {
        dismissDetails()
    }

    func popoverShouldClose(_ popover: NSPopover) -> Bool {
        guard let event = NSApp.currentEvent,
              event.type == .leftMouseDown || event.type == .leftMouseUp,
              let id = calendarView.eventID(for: event) else { return true }
        if let stamp = handledClickStamp, abs(event.timestamp - stamp) < 0.4 {
            return false
        }
        handledClickStamp = event.timestamp
        performEventAction(id)
        return false
    }

    func popoverDidClose(_ notification: Notification) {
        pinnedEventID = nil
        presentedEventID = nil
        restoreSelectedFocus()
    }

    // MARK: Toolbar

    func makeToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? {
        let item: NSToolbarItem
        switch identifier {
        case .homePeriodNavigation:
            let images = ["chevron.left", "chevron.right"].compactMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            let group = NSToolbarItemGroup(itemIdentifier: identifier, images: images, selectionMode: .momentary,
                                           labels: ["Previous", "Next"], target: self, action: #selector(navigatePeriod(_:)))
            group.label = "Previous and Next"
            group.paletteLabel = "Previous and Next"
            for (subitem, help) in zip(group.subitems, ["Show the previous period.", "Show the next period."]) {
                subitem.toolTip = help
                subitem.autovalidates = false
            }
            item = group
        case .homeToday:
            item = NSToolbarItem(itemIdentifier: identifier)
            item.title = "Today"
            item.label = "Today"
            item.isBordered = true
            item.target = self
            item.action = #selector(showCurrentPeriod(_:))
            item.toolTip = "Show the period containing today."
        case .homeAccountFilter:
            let popUp = NSPopUpButton(frame: .zero, pullsDown: false)
            popUp.target = self
            popUp.action = #selector(chooseFilter(_:))
            popUp.setAccessibilityLabel("Accounts")
            item = NSToolbarItem(itemIdentifier: identifier)
            item.view = popUp
            item.label = "Accounts"
            item.toolTip = "Show every account or one account in the table and calendar."
        case .homePeriodLength:
            let group = NSToolbarItemGroup(itemIdentifier: identifier, titles: ["Month", "2 Weeks"], selectionMode: .selectOne,
                                           labels: ["Month", "2 Weeks"], target: self, action: #selector(choosePeriodLength(_:)))
            group.label = "Calendar Length"
            group.paletteLabel = "Calendar Length"
            for subitem in group.subitems { subitem.autovalidates = false }
            item = group
        case .homeRefreshAll:
            item = NSToolbarItem(itemIdentifier: identifier)
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh All")
            item.label = "Refresh All"
            item.isBordered = true
            item.target = nil
            item.action = #selector(WindowCommandHandling.refreshAllAccounts(_:))
        default:
            return nil
        }
        item.autovalidates = false
        toolbarItems[identifier] = item
        syncToolbarItems()
        return item
    }

    private func publishToolbarState(subtitle: String) {
        let identifiers: [NSToolbarItem.Identifier] = showsReadings
            ? [.homePeriodNavigation, .homeToday, .flexibleSpace, .homeAccountFilter, .homePeriodLength, .homeRefreshAll]
            : []
        let changed = identifiers != toolbarItemIdentifiers || subtitle != windowSubtitle
        toolbarItemIdentifiers = identifiers
        windowSubtitle = subtitle
        syncToolbarItems()
        if changed { onToolbarStateChange?() }
    }

    /// Applies current state to the items the toolbar holds. Unchanged values are not reassigned.
    private func syncToolbarItems() {
        if let group = toolbarItems[.homePeriodLength] as? NSToolbarItemGroup {
            let index = mode == .month ? 0 : 1
            if group.selectedIndex != index { group.selectedIndex = index }
        }
        if let refresh = toolbarItems[.homeRefreshAll] {
            let enabled = !model.isDemo && !model.profiles.isEmpty && !model.isRefreshing && !model.isChangingAccounts
            if refresh.isEnabled != enabled { refresh.isEnabled = enabled }
            let help = model.isRefreshing ? "Refreshing every account…" : "Read every account again."
            if refresh.toolTip != help { refresh.toolTip = help }
        }
        if let item = toolbarItems[.homeAccountFilter], let popUp = item.view as? NSPopUpButton {
            let titles = ["All Accounts"] + filterChoices.map(\.title)
            if popUp.itemTitles != titles {
                popUp.menu = filterMenu(titles: titles, action: #selector(chooseFilter(_:)))
                let overflow = NSMenuItem(title: "Accounts", action: nil, keyEquivalent: "")
                overflow.submenu = filterMenu(titles: titles, action: #selector(chooseFilter(_:)))
                item.menuFormRepresentation = overflow
            }
            if popUp.indexOfSelectedItem != selectedFilterIndex { popUp.selectItem(at: selectedFilterIndex) }
        }
    }

    private func filterMenu(titles: [String], action: Selector) -> NSMenu {
        let menu = NSMenu()
        for (index, title) in titles.enumerated() {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
            entry.target = self
            entry.tag = index
            menu.addItem(entry)
        }
        return menu
    }

    private var selectedFilterIndex: Int {
        switch filter {
        case .all: 0
        case .account(let id): (filterChoices.firstIndex { $0.id == id } ?? -1) + 1
        }
    }

    // MARK: Commands

    @objc func showPreviousPeriod(_ sender: Any?) {
        guard showsReadings else { return }
        shift(by: -1)
    }

    @objc func showNextPeriod(_ sender: Any?) {
        guard showsReadings else { return }
        shift(by: 1)
    }

    @objc func showCurrentPeriod(_ sender: Any?) {
        guard showsReadings else { return }
        anchor = Date()
        render()
    }

    @objc func showMonthPeriod(_ sender: Any?) {
        guard showsReadings, mode != .month else { return }
        mode = .month
        render()
    }

    @objc func showTwoWeekPeriod(_ sender: Any?) {
        guard showsReadings, mode != .twoWeeks else { return }
        mode = .twoWeeks
        render()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(showMonthPeriod(_:)):
            menuItem.state = mode == .month ? .on : .off
            return showsReadings
        case #selector(showTwoWeekPeriod(_:)):
            menuItem.state = mode == .twoWeeks ? .on : .off
            return showsReadings
        case #selector(showPreviousPeriod(_:)), #selector(showNextPeriod(_:)), #selector(showCurrentPeriod(_:)):
            return showsReadings
        case #selector(chooseFilter(_:)):
            menuItem.state = menuItem.tag == selectedFilterIndex ? .on : .off
            return showsReadings
        case #selector(chooseAccountSortOrder(_:)):
            menuItem.state = AccountSortOrder.allCases.firstIndex(of: sortOrder) == menuItem.tag ? .on : .off
            return showsReadings
        default:
            return true
        }
    }

    @objc private func navigatePeriod(_ sender: Any?) {
        guard let group = toolbarItems[.homePeriodNavigation] as? NSToolbarItemGroup else { return }
        let index = (sender as? NSToolbarItem).flatMap { item in group.subitems.firstIndex { $0 === item } } ?? group.selectedIndex
        if index == 0 { showPreviousPeriod(sender) } else if index == 1 { showNextPeriod(sender) }
    }

    @objc private func choosePeriodLength(_ sender: Any?) {
        guard let group = toolbarItems[.homePeriodLength] as? NSToolbarItemGroup else { return }
        let index = (sender as? NSToolbarItem).flatMap { item in group.subitems.firstIndex { $0 === item } } ?? group.selectedIndex
        if index == 0 { showMonthPeriod(sender) } else if index == 1 { showTwoWeekPeriod(sender) }
    }

    @objc private func chooseFilter(_ sender: Any?) {
        let index = (sender as? NSPopUpButton)?.selectedTag() ?? (sender as? NSMenuItem)?.tag ?? 0
        let choice = index - 1
        filter = filterChoices.indices.contains(choice) ? .account(filterChoices[choice].id) : .all
        render()
    }

    /// View > Sort Accounts. The menu item tag is the index in `AccountSortOrder.allCases`.
    @objc func chooseAccountSortOrder(_ sender: Any?) {
        guard showsReadings, let tag = (sender as? NSMenuItem)?.tag, AccountSortOrder.allCases.indices.contains(tag) else { return }
        let order = AccountSortOrder.allCases[tag]
        guard order != sortOrder else { return }
        sortOrder = order
        render()
    }

    @objc private func addClaudeAccount(_ sender: Any?) { requestAccount(.claude, sender: sender) }
    @objc private func addCodexAccount(_ sender: Any?) { requestAccount(.codex, sender: sender) }

    private func requestAccount(_ provider: Provider, sender: Any?) {
        if let onAddAccount {
            onAddAccount(provider)
        } else {
            _ = NSApp.sendAction(#selector(WindowCommandHandling.addAccount(_:)), to: nil, from: sender)
        }
    }

    @objc private func retryLoad(_ sender: Any?) {
        guard isAccountLoadComplete(), onRetryAccountLoad != nil else { return }
        onRetryAccountLoad?()
    }

    @objc private func reconnectFromAttention(_ sender: NSButton) {
        guard let id = attentionItems.first(where: { $0.id.uuidString == sender.identifier?.rawValue })?.id else { return }
        onReconnectAccount?(id)
    }

    // MARK: Content

    private func configureControls() {
        bind(retryButton, action: #selector(retryLoad(_:)), help: "Try loading accounts again.")
        bind(addClaudeButton, action: #selector(addClaudeAccount(_:)), help: "Sign in to a Claude account.")
        bind(addCodexButton, action: #selector(addCodexAccount(_:)), help: "Add a Codex account signed in with the Codex CLI.")
        contextLabel.font = .systemFont(ofSize: 12)
        contextLabel.textColor = .labelColor
        contextLabel.lineBreakMode = .byTruncatingTail
        emptyPeriodLabel.font = .systemFont(ofSize: 13)
        emptyPeriodLabel.textColor = .labelColor
        demoLabel.font = .systemFont(ofSize: 12)
        demoLabel.textColor = .labelColor
        calendarView.onActivate = { [weak self] id in self?.activate(id) }
        if !model.isDemo {
            tableView.onReconnect = { [weak self] id in self?.onReconnectAccount?(id) }
        }
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = details
        popover.delegate = self
        details.onViewAccount = { [weak self] id in
            self?.dismissDetails()
            self?.onViewAccount?(id)
        }
        details.onReturn = { [weak self] in self?.returnInDetails() }
    }

    private func applyPlaceholder(loaded: Bool, failed: Bool, hasAccounts: Bool) {
        let canChange = loaded && !model.isDemo && !model.isChangingAccounts
        if failed {
            stateTitle.isHidden = false
            stateTitle.stringValue = HomeInterfaceFormatting.loadErrorTitle
            stateMessage.stringValue = HomeInterfaceFormatting.loadErrorMessage
            stateDetail.stringValue = model.message ?? ""
            stateDetail.isHidden = stateDetail.stringValue.isEmpty
            addButtons.isHidden = true
            retryButton.isHidden = false
            retryButton.isEnabled = loaded && onRetryAccountLoad != nil
        } else if !hasAccounts && !loaded {
            stateTitle.isHidden = true
            stateMessage.stringValue = HomeInterfaceFormatting.loadingMessage
            stateDetail.isHidden = true
            addButtons.isHidden = true
            retryButton.isHidden = true
        } else if !hasAccounts {
            stateTitle.isHidden = false
            stateTitle.stringValue = HomeInterfaceFormatting.addAccountTitle
            stateMessage.stringValue = HomeInterfaceFormatting.addAccountMessage
            stateDetail.isHidden = true
            addButtons.isHidden = false
            addClaudeButton.isEnabled = canChange
            addCodexButton.isEnabled = canChange
            retryButton.isHidden = true
        }
    }

    /// One line per affected account, with Reconnect… beside a sign-in failure. Rebuilt only on change.
    private func applyAttention(_ items: [HomeAttentionItem]) {
        attentionStack.isHidden = items.isEmpty
        guard items != attentionItems else { return }
        attentionItems = items
        for view in attentionStack.arrangedSubviews {
            attentionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for item in items {
            let text = NSTextField(wrappingLabelWithString: item.text)
            text.font = .systemFont(ofSize: 12)
            text.textColor = .labelColor
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let line = NSStackView(views: [text])
            line.orientation = .horizontal
            line.alignment = .firstBaseline
            line.spacing = 8
            if item.showsReconnect, !model.isDemo, onReconnectAccount != nil {
                let reconnect = NSButton(title: "Reconnect…", target: self, action: #selector(reconnectFromAttention(_:)))
                reconnect.bezelStyle = .rounded
                reconnect.controlSize = .small
                reconnect.identifier = NSUserInterfaceItemIdentifier(item.id.uuidString)
                reconnect.setAccessibilityLabel("Reconnect \(item.text.components(separatedBy: ":").first ?? "")")
                line.addArrangedSubview(reconnect)
            }
            attentionStack.addArrangedSubview(line)
        }
    }

    /// Reconnect… follows the account page rule even when the attention rows themselves are unchanged.
    private func syncAttentionReconnect() {
        let canReconnect = !model.isRefreshing && !model.isChangingAccounts
        for case let line as NSStackView in attentionStack.arrangedSubviews {
            for case let button as NSButton in line.arrangedSubviews { button.isEnabled = canReconnect }
        }
    }

    private func filteredEvents(_ events: [UsageResetEvent]) -> [UsageResetEvent] {
        switch filter {
        case .all:
            return events
        case .account(let id):
            return events.filter { $0.accountID == id }
        }
    }

    private func activate(_ id: String) {
        if let event = NSApp.currentEvent, let stamp = handledClickStamp,
           event.type == .leftMouseDown || event.type == .leftMouseUp,
           abs(event.timestamp - stamp) < 0.4 {
            return
        }
        performEventAction(id)
    }

    private func performEventAction(_ id: String) {
        if pinnedEventID == id, popover.isShown {
            dismissDetails()
            return
        }
        if NSApp.currentEvent?.type == .keyDown {
            suppressedReturn = NSApp.currentEvent
        }
        showDetails(for: id, pin: true)
    }

    /// Opens on click or Return only. The trailing edge keeps the popover off the sidebar.
    private func showDetails(for eventID: String, pin: Bool) {
        guard let event = visibleEvents.first(where: { $0.id == eventID }),
              let account = overview.accounts.first(where: { $0.id == event.accountID }),
              let anchorView = calendarView.eventView(for: eventID), anchorView.window != nil else { return }
        let needsPresentation = !popover.isShown || presentedEventID != eventID
        let content = HomeInterfaceFormatting.detailContent(account: account, now: displayedNow, calendar: displayedCalendar)
        details.apply(content)
        if popover.contentSize != details.preferredContentSize {
            popover.contentSize = details.preferredContentSize
        }
        presentedEventID = eventID
        if pin {
            pinnedEventID = eventID
            calendarView.selectEvent(id: eventID)
        }
        if needsPresentation {
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxX)
        }
    }

    private func refreshPresentedDetails() {
        guard popover.isShown, let presentedEventID else { return }
        guard visibleEvents.contains(where: { $0.id == presentedEventID }),
              calendarView.eventView(for: presentedEventID) != nil else {
            dismissDetails()
            return
        }
        showDetails(for: presentedEventID, pin: pinnedEventID == presentedEventID)
    }

    private func returnInDetails() {
        if let event = NSApp.currentEvent, event === suppressedReturn {
            suppressedReturn = nil
            return
        }
        suppressedReturn = nil
        dismissDetails()
    }

    private func restoreSelectedFocus() {
        guard let id = calendarView.selectedEventID, let control = calendarView.eventView(for: id) else { return }
        view.window?.makeFirstResponder(control)
    }

    private func shift(by step: Int) {
        let calendar = Calendar.current
        let next = mode == .month
            ? calendar.date(byAdding: .month, value: step, to: anchor)
            : calendar.date(byAdding: .day, value: 14 * step, to: anchor)
        if let next { anchor = next }
        render()
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        label.setAccessibilityRole(.staticText)
        return label
    }

    private func bind(_ button: NSButton, action: Selector, help: String) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.setAccessibilityHelp(help)
    }
}

private enum AccountFilter: Equatable {
    case all
    case account(UUID)
}

private struct FilterChoice: Equatable {
    var id: UUID
    var title: String
}

@MainActor
private final class HomeDocumentView: NSView {
    override var isFlipped: Bool { true }
}
