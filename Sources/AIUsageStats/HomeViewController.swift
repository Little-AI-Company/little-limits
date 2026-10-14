import AppKit
import UsageCore

/// Home reset calendar and account usage. Mode, date, filter, and event selection survive refresh.
@MainActor
final class HomeViewController: NSViewController, NSPopoverDelegate {
    var onViewAccount: ((UUID) -> Void)?
    var onReconnectAccount: ((UUID) -> Void)?
    var onRetryAccountLoad: (() -> Void)?
    var isAccountLoadComplete: () -> Bool = { false }

    private let model: ApplicationModel
    private var mode: UsageCalendarMode = .twoWeeks
    private var anchor = Date()
    private var filter: AccountFilter = .all
    private var filterChoices: [UUID] = []
    private var overview = UsageOverview(profiles: [], snapshots: [:])
    private var visibleEvents: [UsageResetEvent] = []
    private var displayedNow = Date()
    private var displayedCalendar = Calendar.current
    private var pinnedEventID: String?
    private var presentedEventID: String?
    private var suppressedReturn: NSEvent?
    private var handledClickStamp: TimeInterval?
    private let popover = NSPopover()
    private let details = UsageEventDetailsViewController()
    private let calendarView = UsageCalendarView()
    private let tableView = UsageOverviewTableView()
    private let previousButton = NSButton(title: "Previous", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next", target: nil, action: nil)
    private let todayButton = NSButton(title: "Today", target: nil, action: nil)
    private let periodLabel = NSTextField(labelWithString: "")
    private let filterButton = NSPopUpButton()
    private let modeControl = NSSegmentedControl(labels: ["Month", "2 Weeks"], trackingMode: .selectOne, target: nil, action: nil)
    private let refreshButton = NSButton(title: "Refresh All", target: nil, action: nil)
    private let contextLabel = NSTextField(labelWithString: "")
    private let attentionLabel = NSTextField(wrappingLabelWithString: HomeInterfaceFormatting.attentionText)
    private let emptyPeriodLabel = NSTextField(labelWithString: HomeInterfaceFormatting.emptyPeriodText)
    private let stateTitle = NSTextField(labelWithString: "")
    private let stateMessage = NSTextField(wrappingLabelWithString: "")
    private let retryButton = NSButton(title: "Retry Loading Accounts", target: nil, action: nil)
    private let demoLabel = NSTextField(labelWithString: "Example accounts")
    private let readings = NSStackView()
    private let stateStack = NSStackView()
    private let toolbar = NSStackView()

    init(model: ApplicationModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let root = NSView()
        configureControls()
        configurePopover()
        let column = NSStackView()
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.detachesHiddenViews = true
        column.translatesAutoresizingMaskIntoConstraints = false
        for item in [previousButton, nextButton, todayButton, periodLabel, flexibleSpacer(), filterButton, modeControl, refreshButton] {
            toolbar.addArrangedSubview(item)
        }
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        readings.orientation = .vertical
        readings.alignment = .leading
        readings.spacing = 8
        readings.detachesHiddenViews = true
        readings.translatesAutoresizingMaskIntoConstraints = false
        let calendarTitle = sectionTitle("Reset calendar")
        let tableTitle = sectionTitle("Account usage")
        for item in [calendarTitle, contextLabel, attentionLabel, calendarView, emptyPeriodLabel, tableTitle, tableView, demoLabel] {
            readings.addArrangedSubview(item)
        }
        stateStack.orientation = .vertical
        stateStack.alignment = .leading
        stateStack.spacing = 8
        stateStack.detachesHiddenViews = true
        stateStack.translatesAutoresizingMaskIntoConstraints = false
        stateTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        stateMessage.font = .systemFont(ofSize: 13)
        stateMessage.preferredMaxLayoutWidth = 420
        for item in [stateTitle, stateMessage, retryButton] {
            stateStack.addArrangedSubview(item)
        }
        column.addArrangedSubview(toolbar)
        column.addArrangedSubview(readings)
        column.addArrangedSubview(stateStack)
        root.addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            column.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            column.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            column.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -16),
            toolbar.widthAnchor.constraint(equalTo: column.widthAnchor),
            readings.widthAnchor.constraint(equalTo: column.widthAnchor),
            stateStack.widthAnchor.constraint(equalTo: column.widthAnchor),
            calendarView.widthAnchor.constraint(equalTo: readings.widthAnchor),
            tableView.widthAnchor.constraint(equalTo: readings.widthAnchor),
            attentionLabel.widthAnchor.constraint(equalTo: readings.widthAnchor),
            stateMessage.widthAnchor.constraint(lessThanOrEqualTo: stateStack.widthAnchor)
        ])
        let balance = calendarView.heightAnchor.constraint(equalTo: tableView.heightAnchor)
        balance.priority = NSLayoutConstraint.Priority(750)
        balance.isActive = true
        let calendarFloor = calendarView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180)
        calendarFloor.priority = NSLayoutConstraint.Priority(750)
        calendarFloor.isActive = true
        let tableFloor = tableView.heightAnchor.constraint(greaterThanOrEqualToConstant: 120)
        tableFloor.priority = NSLayoutConstraint.Priority(750)
        tableFloor.isActive = true
        calendarView.setContentHuggingPriority(NSLayoutConstraint.Priority(200), for: .vertical)
        view = root
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
        let period = UsageCalendarPeriod(mode: mode, containing: anchor, calendar: calendar)
        visibleEvents = filteredEvents(overview.resetEvents)
        let hasAccounts = !overview.accounts.isEmpty
        let failed = model.hasAccountLoadFailure
        let loaded = isAccountLoadComplete()
        let showReadings = hasAccounts && !failed
        readings.isHidden = !showReadings
        stateStack.isHidden = showReadings
        applyPlaceholder(loaded: loaded, failed: failed, hasAccounts: hasAccounts)
        applyToolbar(showReadings: showReadings, now: now, period: period, calendar: calendar)
        guard showReadings else {
            if popover.isShown { dismissDetails() }
            return
        }
        let accounts = overview.accounts.filter { account in
            switch filter {
            case .all: true
            case .account(let id): account.id == id
            }
        }
        contextLabel.stringValue = HomeInterfaceFormatting.readingContext(now: now, calendar: calendar)
        attentionLabel.isHidden = !HomeInterfaceFormatting.attentionNeeded(accounts)
        demoLabel.isHidden = !model.isDemo
        let placed = HomeInterfaceFormatting.calendarEvents(visibleEvents, days: period.days, now: now, calendar: calendar)
        emptyPeriodLabel.isHidden = !placed.isEmpty
        calendarView.apply(period: period, events: visibleEvents, mode: mode, anchor: anchor, now: now, calendar: calendar)
        tableView.apply(rows: HomeInterfaceFormatting.rows(for: accounts, now: now, calendar: calendar),
                        headings: HomeInterfaceFormatting.headings(for: accounts))
        refreshPresentedDetails()
    }

    func focusInitialControl() {
        if !isViewLoaded { _ = view }
        guard let window = view.window else { return }
        if let id = calendarView.selectedEventID, let control = calendarView.eventView(for: id) {
            window.makeFirstResponder(control)
            return
        }
        if !previousButton.isHidden, previousButton.isEnabled {
            window.makeFirstResponder(previousButton)
            return
        }
        if !retryButton.isHidden, retryButton.isEnabled {
            window.makeFirstResponder(retryButton)
            return
        }
        window.makeFirstResponder(view)
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

    private func configureControls() {
        bind(previousButton, action: #selector(showPrevious(_:)), help: "Show the previous period.")
        bind(nextButton, action: #selector(showNext(_:)), help: "Show the next period.")
        bind(todayButton, action: #selector(showToday(_:)), help: "Show the period containing today.")
        bind(refreshButton, action: #selector(refreshAll(_:)), help: "Read every account again.")
        bind(retryButton, action: #selector(retryLoad(_:)), help: "Try loading accounts again.")
        filterButton.target = self
        filterButton.action = #selector(changeFilter(_:))
        filterButton.controlSize = .regular
        filterButton.setAccessibilityLabel("Accounts")
        filterButton.addItem(withTitle: "All accounts")
        modeControl.target = self
        modeControl.action = #selector(changeMode(_:))
        modeControl.selectedSegment = 1
        modeControl.segmentDistribution = .fillEqually
        modeControl.setAccessibilityLabel("Calendar length")
        periodLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        periodLabel.textColor = .labelColor
        periodLabel.lineBreakMode = .byTruncatingMiddle
        periodLabel.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(300), for: .horizontal)
        filterButton.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(400), for: .horizontal)
        contextLabel.font = .systemFont(ofSize: 12)
        contextLabel.textColor = .labelColor
        contextLabel.lineBreakMode = .byTruncatingTail
        attentionLabel.font = .systemFont(ofSize: 13)
        attentionLabel.textColor = .labelColor
        emptyPeriodLabel.font = .systemFont(ofSize: 13)
        emptyPeriodLabel.textColor = .labelColor
        demoLabel.font = .systemFont(ofSize: 12)
        demoLabel.textColor = .labelColor
        calendarView.onActivate = { [weak self] id in self?.activate(id) }
        calendarView.onHover = { [weak self] id in self?.hover(id) }
        calendarView.onHoverEnd = { _ in
            // Leaving the button must not dismiss. The pointer still has to reach View Account.
        }
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

    private func applyToolbar(showReadings: Bool, now: Date, period: UsageCalendarPeriod, calendar: Calendar) {
        toolbar.isHidden = !showReadings
        let title = HomeInterfaceFormatting.periodTitle(mode: mode, period: period, anchor: anchor, calendar: calendar)
        if periodLabel.stringValue != title { periodLabel.stringValue = title }
        let navigationEnabled = showReadings
        previousButton.isEnabled = navigationEnabled
        nextButton.isEnabled = navigationEnabled
        todayButton.isEnabled = navigationEnabled
        filterButton.isEnabled = navigationEnabled
        modeControl.isEnabled = navigationEnabled
        let refreshing = model.isRefreshing
        refreshButton.title = refreshing ? "Refreshing…" : "Refresh All"
        refreshButton.isEnabled = !model.isDemo && !model.profiles.isEmpty && !refreshing && !model.isChangingAccounts
        modeControl.selectedSegment = mode == .month ? 0 : 1
        syncFilterMenu()
    }

    private func applyPlaceholder(loaded: Bool, failed: Bool, hasAccounts: Bool) {
        if failed {
            stateTitle.isHidden = false
            stateTitle.stringValue = HomeInterfaceFormatting.loadErrorTitle
            stateMessage.stringValue = model.message ?? ""
            retryButton.isHidden = false
            retryButton.isEnabled = loaded && onRetryAccountLoad != nil
        } else if !hasAccounts && !loaded {
            stateTitle.isHidden = true
            stateMessage.stringValue = HomeInterfaceFormatting.loadingMessage
            retryButton.isHidden = true
        } else if !hasAccounts {
            stateTitle.isHidden = false
            stateTitle.stringValue = HomeInterfaceFormatting.addAccountTitle
            stateMessage.stringValue = HomeInterfaceFormatting.addAccountMessage
            retryButton.isHidden = true
        }
    }

    private func syncFilterMenu() {
        let choices = overview.accounts.map { ($0.id, "\($0.profile.provider.title) \($0.shortIdentity)") }
        let identifiers = choices.map(\.0)
        let titles = choices.map(\.1)
        let currentTitles = (0..<filterButton.numberOfItems).map { filterButton.item(at: $0)?.title ?? "" }
        let expected = ["All accounts"] + titles
        if identifiers != filterChoices || currentTitles != expected {
            filterChoices = identifiers
            filterButton.removeAllItems()
            filterButton.addItem(withTitle: "All accounts")
            for title in titles { filterButton.addItem(withTitle: title) }
        }
        switch filter {
        case .all:
            filterButton.selectItem(at: 0)
        case .account(let id):
            if let index = identifiers.firstIndex(of: id) {
                filterButton.selectItem(at: index + 1)
            } else {
                filter = .all
                filterButton.selectItem(at: 0)
            }
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

    private func hover(_ id: String) {
        guard pinnedEventID == nil else { return }
        showDetails(for: id, pin: false)
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
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .minX)
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

    private func shift(days: Int? = nil, months: Int? = nil) {
        let calendar = Calendar.current
        if let days, let next = calendar.date(byAdding: .day, value: days, to: anchor) {
            anchor = next
        }
        if let months, let next = calendar.date(byAdding: .month, value: months, to: anchor) {
            anchor = next
        }
        render()
    }

    private func sectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        return label
    }

    private func flexibleSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        spacer.setContentCompressionResistancePriority(NSLayoutConstraint.Priority(200), for: .horizontal)
        return spacer
    }

    private func bind(_ button: NSButton, action: Selector, help: String) {
        button.target = self
        button.action = action
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.setAccessibilityHelp(help)
    }

    @objc private func showPrevious(_ sender: Any?) {
        if mode == .month { shift(months: -1) } else { shift(days: -14) }
    }

    @objc private func showNext(_ sender: Any?) {
        if mode == .month { shift(months: 1) } else { shift(days: 14) }
    }

    @objc private func showToday(_ sender: Any?) {
        anchor = Date()
        render()
    }

    @objc private func changeFilter(_ sender: Any?) {
        let index = filterButton.indexOfSelectedItem
        if index <= 0 {
            filter = .all
        } else {
            let choice = index - 1
            if filterChoices.indices.contains(choice) {
                filter = .account(filterChoices[choice])
            }
        }
        render()
    }

    @objc private func changeMode(_ sender: Any?) {
        mode = modeControl.selectedSegment == 0 ? .month : .twoWeeks
        render()
    }

    @objc private func refreshAll(_ sender: Any?) {
        model.refresh()
    }

    @objc private func retryLoad(_ sender: Any?) {
        guard isAccountLoadComplete(), onRetryAccountLoad != nil else { return }
        onRetryAccountLoad?()
    }
}

private enum AccountFilter: Equatable {
    case all
    case account(UUID)
}
