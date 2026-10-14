import AppKit
import QuartzCore
import UsageCore

/// Monday-first reset calendar. Days come from `UsageCalendarPeriod`. Buttons come only from
/// the supplied `UsageResetEvent` values, placed on the local day of each reported reset.
@MainActor
final class UsageCalendarView: NSView {
    /// Click or Return on an event. The value is `UsageResetEvent.id`. Hover only highlights and shows the tooltip.
    var onActivate: ((String) -> Void)?

    /// Selection survives `apply` when that event is still in the new readings.
    private(set) var selectedEventID: String?

    private let weekdayHeader = CalendarWeekdayHeader()
    private let scroll = CalendarScrollView()
    private let grid = CalendarGridView()
    private var snapshot = CalendarSnapshot?.none
    private var displayedEvents: [HomeCalendarEventModel] = []
    private var pendingFocusID: String?
    private var isLayingOut = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        weekdayHeader.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.verticalScrollElasticity = .none
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = grid
        scroll.onScrolled = { [weak self] in self?.syncHeader() }
        grid.onActivate = { [weak self] id in self?.activate(id) }
        grid.onHover = { [weak self] id in self?.grid.setHovered(id) }
        grid.onHoverEnd = { [weak self] id in self?.grid.clearHover(id) }
        addSubview(weekdayHeader)
        addSubview(scroll)
        NSLayoutConstraint.activate([
            weekdayHeader.leadingAnchor.constraint(equalTo: leadingAnchor),
            weekdayHeader.trailingAnchor.constraint(equalTo: trailingAnchor),
            weekdayHeader.topAnchor.constraint(equalTo: topAnchor),
            weekdayHeader.heightAnchor.constraint(equalToConstant: CalendarMetrics.headerHeight),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: weekdayHeader.bottomAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Reset calendar")
    }

    required init?(coder: NSCoder) { nil }

    /// Height of the header plus every day row. The Home document scrolls vertically; the grid scrolls
    /// horizontally only when the view is narrower than seven minimum columns.
    var preferredHeight: CGFloat { CalendarMetrics.headerHeight + grid.contentHeight }

    override var intrinsicContentSize: NSSize {
        NSSize(width: CalendarMetrics.minimumWidth, height: preferredHeight)
    }

    func eventView(for eventID: String) -> NSView? { grid.button(for: eventID) }

    /// The reset button under this mouse or key event, when it belongs to this calendar.
    func eventID(for event: NSEvent) -> String? {
        if event.type == .keyDown || event.type == .keyUp {
            guard event.window === window else { return nil }
            return (window?.firstResponder as? UsageEventButton)?.eventID
        }
        guard let eventWindow = event.window, eventWindow === window else { return nil }
        guard let parent = superview else { return nil }
        let pointInParent = parent.convert(event.locationInWindow, from: nil)
        guard let hit = hitTest(pointInParent) else { return nil }
        var view: NSView? = hit
        while let candidate = view {
            if let button = candidate as? UsageEventButton { return button.eventID }
            view = candidate.superview
        }
        return nil
    }

    func selectEvent(id: String?) {
        selectedEventID = id
        grid.updateEmphasis(selected: selectedEventID)
        publishAccessibilityChildren()
    }

    /// Replace the visible period and readings. Keeps the selected event and keyboard focus when that id remains.
    func apply(period: UsageCalendarPeriod, events: [UsageResetEvent], mode: UsageCalendarMode,
               anchor: Date, now: Date, calendar: Calendar) {
        let focusedID = (window?.firstResponder as? UsageEventButton)?.eventID ?? pendingFocusID
        if let selectedEventID, !events.contains(where: { $0.id == selectedEventID }) {
            self.selectedEventID = nil
        }
        let models = HomeInterfaceFormatting.calendarEvents(events, days: period.days, now: now, calendar: calendar)
        let todayIndex = period.days.firstIndex { calendar.isDate($0, inSameDayAs: now) }
        let next = CalendarSnapshot(days: period.days,
                                   events: models,
                                   weekdayTitles: HomeInterfaceFormatting.weekdayTitles(days: period.days, calendar: calendar),
                                   weekdayHelp: Self.weekdayHelp(days: period.days, calendar: calendar),
                                   todayIndex: todayIndex,
                                   anchor: anchor,
                                   limitToAnchorMonth: mode == .month,
                                   minimumRowHeight: mode == .twoWeeks ? CalendarMetrics.twoWeekRow : CalendarMetrics.monthRow,
                                   calendarIdentifier: calendar.identifier)
        guard next != snapshot else {
            grid.updateEmphasis(selected: selectedEventID)
            restoreFocus(focusedID)
            return
        }
        snapshot = next
        displayedEvents = models
        weekdayHeader.apply(titles: next.weekdayTitles, help: next.weekdayHelp)
        grid.apply(days: period.days, events: models, calendar: calendar, anchor: anchor,
                   limitToAnchorMonth: next.limitToAnchorMonth, minimumRowHeight: next.minimumRowHeight,
                   todayIndex: todayIndex)
        grid.updateEmphasis(selected: selectedEventID)
        invalidateIntrinsicContentSize()
        needsLayout = true
        layoutSubtreeIfNeeded()
        restoreFocus(focusedID)
        publishAccessibilityChildren()
    }

    override func layout() {
        super.layout()
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        let visibleWidth = scroll.contentView.bounds.width
        guard visibleWidth > 1 else { return }
        let width = max(visibleWidth, CalendarMetrics.minimumWidth)
        let height = max(grid.contentHeight, 1)
        if grid.frame.size != NSSize(width: width, height: height) {
            grid.setFrameSize(NSSize(width: width, height: height))
        }
        grid.positionContents()
        syncHeader()
        publishAccessibilityChildren()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restoreFocus(pendingFocusID)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        grid.noteAppearanceChange()
        weekdayHeader.needsDisplay = true
    }

    private func activate(_ id: String) {
        selectedEventID = id
        grid.updateEmphasis(selected: id)
        onActivate?(id)
    }

    private func syncHeader() {
        let columnWidth = grid.bounds.width > 1 ? grid.bounds.width / 7 : bounds.width / 7
        weekdayHeader.columnWidth = columnWidth
        weekdayHeader.scrollOffset = scroll.contentView.bounds.origin.x
        weekdayHeader.needsLayout = true
    }

    private func restoreFocus(_ eventID: String?) {
        guard let eventID, displayedEvents.contains(where: { $0.id == eventID }) || grid.button(for: eventID) != nil,
              let button = grid.button(for: eventID) else {
            pendingFocusID = nil
            return
        }
        guard let window else {
            pendingFocusID = eventID
            return
        }
        pendingFocusID = nil
        if window.firstResponder !== button {
            window.makeFirstResponder(button)
        }
    }

    private func publishAccessibilityChildren() {
        setAccessibilityChildren(grid.accessibilitySequence())
    }

    private static func weekdayHelp(days: [Date], calendar: Calendar) -> [String] {
        let symbols = calendar.weekdaySymbols
        return (0..<7).map { column in
            guard days.indices.contains(column) else { return "" }
            let index = calendar.component(.weekday, from: days[column]) - 1
            guard symbols.indices.contains(index) else { return "" }
            return symbols[index]
        }
    }
}

private struct CalendarSnapshot: Equatable {
    var days: [Date]
    var events: [HomeCalendarEventModel]
    var weekdayTitles: [String]
    var weekdayHelp: [String]
    var todayIndex: Int?
    var anchor: Date
    var limitToAnchorMonth: Bool
    var minimumRowHeight: CGFloat
    var calendarIdentifier: Calendar.Identifier
}

private enum CalendarMetrics {
    static let headerHeight: CGFloat = 24
    /// The badge sits inside the date band with 4 pt above and below, clear of the week's grid line.
    static let todayDiameter: CGFloat = 22
    /// Seven columns fit the content width of the minimum window beside the sidebar.
    static let columnMinimum: CGFloat = 96
    static let minimumWidth: CGFloat = columnMinimum * 7
    static let twoWeekRow: CGFloat = 96
    static let monthRow: CGFloat = 72
    static let eventHeight: CGFloat = 36
    static let eventGap: CGFloat = 4
    static let dateBand: CGFloat = 30
}

@MainActor
private final class CalendarScrollView: HomeNestedScrollView {
    var onScrolled: (() -> Void)?

    override func reflectScrolledClipView(_ cView: NSClipView) {
        super.reflectScrolledClipView(cView)
        onScrolled?()
    }
}

@MainActor
private final class CalendarWeekdayHeader: NSView {
    var columnWidth: CGFloat = 0
    var scrollOffset: CGFloat = 0
    private var labels: [NSTextField] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        clipsToBounds = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("Weekdays")
    }

    required init?(coder: NSCoder) { nil }

    func apply(titles: [String], help: [String]) {
        if labels.count != 7 {
            labels.forEach { $0.removeFromSuperview() }
            labels = (0..<7).map { _ in
                let label = HomeText.label("", size: 11, weight: .medium, color: .secondaryLabelColor)
                label.alignment = .center
                label.translatesAutoresizingMaskIntoConstraints = false
                addSubview(label)
                return label
            }
        }
        for index in 0..<7 {
            let title = titles.indices.contains(index) ? titles[index] : ""
            if labels[index].stringValue != title { labels[index].stringValue = title }
            let spoken = help.indices.contains(index) && !help[index].isEmpty ? help[index] : title
            labels[index].setAccessibilityLabel(spoken)
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = columnWidth > 1 ? columnWidth : bounds.width / 7
        guard width > 1 else { return }
        for (index, label) in labels.enumerated() {
            label.frame = NSRect(x: CGFloat(index) * width - scrollOffset, y: 2, width: width, height: bounds.height - 4)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setStroke()
        let line = NSBezierPath()
        line.move(to: NSPoint(x: 0, y: 0.5))
        line.line(to: NSPoint(x: bounds.width, y: 0.5))
        line.lineWidth = 1
        line.stroke()
    }
}

@MainActor
private final class CalendarGridView: NSView {
    var onActivate: ((String) -> Void)?
    var onHover: ((String) -> Void)?
    var onHoverEnd: ((String) -> Void)?

    private var days: [Date] = []
    private var events: [HomeCalendarEventModel] = []
    private var eventsByDay: [[HomeCalendarEventModel]] = []
    private var calendar = Calendar.current
    private var anchor = Date()
    private var limitToAnchorMonth = false
    private var minimumRowHeight: CGFloat = CalendarMetrics.twoWeekRow
    private var todayIndex: Int?
    private var dateLabels: [NSTextField] = []
    private var monthLabels: [NSTextField] = []
    private var buttons: [String: UsageEventButton] = [:]
    private var buttonOrder: [String] = []
    private var hoveredEventID: String?
    private var selectedEventID: String?

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        autoresizingMask = []
    }

    required init?(coder: NSCoder) { nil }

    var contentHeight: CGFloat {
        guard !days.isEmpty else { return minimumRowHeight }
        return (0..<weekCount).reduce(0) { $0 + rowHeight($1) }
    }

    func button(for eventID: String) -> UsageEventButton? { buttons[eventID] }

    func apply(days: [Date], events: [HomeCalendarEventModel], calendar: Calendar, anchor: Date,
               limitToAnchorMonth: Bool, minimumRowHeight: CGFloat, todayIndex: Int?) {
        let focusedID = window?.firstResponder as? UsageEventButton
        self.days = days
        self.events = events
        self.calendar = calendar
        self.anchor = anchor
        self.limitToAnchorMonth = limitToAnchorMonth
        self.minimumRowHeight = minimumRowHeight
        self.todayIndex = todayIndex
        eventsByDay = Array(repeating: [], count: days.count)
        for event in events where eventsByDay.indices.contains(event.dayIndex) {
            eventsByDay[event.dayIndex].append(event)
        }
        syncDateLabels()
        syncButtons(preserving: focusedID?.eventID)
        needsDisplay = true
        needsLayout = true
    }

    func positionContents() {
        guard bounds.width > 1, dateLabels.count == days.count, monthLabels.count == days.count else { return }
        let width = bounds.width / 7
        for index in days.indices {
            let origin = cellOrigin(index, columnWidth: width)
            let today = index == todayIndex
            let circle = todayBadgeRect(index, columnWidth: width)
            // Labels are centered on the date band, so the today numeral sits in the middle of its badge.
            let labelHeight = ceil(dateLabels[index].intrinsicContentSize.height)
            let labelY = origin.y + (CalendarMetrics.dateBand - labelHeight) / 2
            if today {
                dateLabels[index].alignment = .center
                dateLabels[index].frame = NSRect(x: circle.minX, y: labelY, width: circle.width, height: labelHeight)
            } else {
                dateLabels[index].alignment = .left
                dateLabels[index].frame = NSRect(x: origin.x + 8, y: labelY, width: width - 16, height: labelHeight)
            }
            let showMonth = today && showsMonthName(index)
            monthLabels[index].isHidden = !showMonth
            if showMonth {
                let monthX = circle.maxX + 4
                monthLabels[index].frame = NSRect(x: monthX, y: labelY,
                                                width: max(0, origin.x + width - 8 - monthX), height: labelHeight)
            }
            var eventY = origin.y + CalendarMetrics.dateBand
            for event in events(on: index) {
                guard let button = buttons[event.id] else { continue }
                button.frame = NSRect(x: origin.x + 4, y: eventY, width: max(32, width - 8), height: CalendarMetrics.eventHeight)
                eventY += CalendarMetrics.eventHeight + CalendarMetrics.eventGap
            }
        }
        needsDisplay = true
    }

    func updateEmphasis(selected: String?) {
        selectedEventID = selected
        applyChrome()
    }

    func setHovered(_ id: String) {
        hoveredEventID = id
        applyChrome()
    }

    func clearHover(_ id: String) {
        guard hoveredEventID == id else { return }
        hoveredEventID = nil
        applyChrome()
    }

    func noteAppearanceChange() {
        applyDateColors()
        applyChrome()
        needsDisplay = true
    }

    func accessibilitySequence() -> [Any] {
        var children: [Any] = []
        for index in days.indices {
            children.append(dateLabels[index])
            for event in events(on: index) {
                if let button = buttons[event.id] { children.append(button) }
            }
        }
        return children
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 1, !days.isEmpty else { return }
        let width = bounds.width
        let columnWidth = width / 7
        let path = NSBezierPath()
        path.lineWidth = 1
        for column in 0...7 {
            let x = min(CGFloat(column) * columnWidth, width) + (column == 7 ? -0.5 : 0.5)
            path.move(to: NSPoint(x: x, y: 0))
            path.line(to: NSPoint(x: x, y: contentHeight))
        }
        var y: CGFloat = 0.5
        path.move(to: NSPoint(x: 0, y: y))
        path.line(to: NSPoint(x: width, y: y))
        for week in 0..<weekCount {
            y += rowHeight(week)
            let lineY = min(y, contentHeight) - 0.5
            path.move(to: NSPoint(x: 0, y: lineY))
            path.line(to: NSPoint(x: width, y: lineY))
        }
        NSColor.separatorColor.setStroke()
        path.stroke()
        if let todayIndex, days.indices.contains(todayIndex) {
            let columnWidth = bounds.width / 7
            let circle = todayBadgeRect(todayIndex, columnWidth: columnWidth)
            // Label color with a background-color numeral keeps contrast in every accent color.
            NSColor.labelColor.setFill()
            NSBezierPath(ovalIn: circle).fill()
        }
    }

    private var weekCount: Int { days.isEmpty ? 0 : (days.count + 6) / 7 }

    private func rowHeight(_ week: Int) -> CGFloat {
        let start = week * 7
        let end = min(start + 7, eventsByDay.count)
        let count = (start..<end).map { eventsByDay[$0].count }.max() ?? 0
        let eventsHeight = count == 0 ? 0 : CGFloat(count) * CalendarMetrics.eventHeight + CGFloat(max(0, count - 1)) * CalendarMetrics.eventGap
        return max(minimumRowHeight, CalendarMetrics.dateBand + eventsHeight + 8)
    }

    private func cellOrigin(_ index: Int, columnWidth: CGFloat) -> NSPoint {
        NSPoint(x: CGFloat(index % 7) * columnWidth, y: rowTop(index / 7))
    }

    private func todayBadgeRect(_ index: Int, columnWidth: CGFloat) -> NSRect {
        let origin = cellOrigin(index, columnWidth: columnWidth)
        let labelWidth = dateLabels.indices.contains(index) ? dateLabels[index].intrinsicContentSize.width : 0
        let diameter = max(CalendarMetrics.todayDiameter, labelWidth.rounded(.up) + 6)
        return NSRect(x: origin.x + 6, y: origin.y + (CalendarMetrics.dateBand - diameter) / 2,
                      width: diameter, height: diameter)
    }

    private func rowTop(_ week: Int) -> CGFloat {
        guard week > 0 else { return 0 }
        return (0..<week).reduce(0) { $0 + rowHeight($1) }
    }

    private func syncDateLabels() {
        if dateLabels.count != days.count {
            dateLabels.forEach { $0.removeFromSuperview() }
            monthLabels.forEach { $0.removeFromSuperview() }
            dateLabels = days.map { _ in makeDateLabel() }
            monthLabels = days.map { _ in makeMonthLabel() }
            for label in dateLabels { addSubview(label) }
            for label in monthLabels { addSubview(label) }
        }
        for index in days.indices {
            let number = calendar.component(.day, from: days[index])
            let today = index == todayIndex
            let text = !today && showsMonthName(index)
                ? "\(days[index].formatted(.dateTime.month(.abbreviated))) \(number)"
                : "\(number)"
            if dateLabels[index].stringValue != text { dateLabels[index].stringValue = text }
            let month = days[index].formatted(.dateTime.month(.abbreviated))
            if monthLabels[index].stringValue != month { monthLabels[index].stringValue = month }
            dateLabels[index].setAccessibilityLabel(dateAccessibility(index))
        }
        applyDateColors()
    }

    private func makeDateLabel() -> NSTextField {
        let label = HomeText.label("", size: 12, weight: .medium, digits: true)
        label.lineBreakMode = .byClipping
        label.autoresizingMask = []
        return label
    }

    private func makeMonthLabel() -> NSTextField {
        let label = HomeText.label("", size: 12, weight: .medium, color: .labelColor)
        label.autoresizingMask = []
        label.isHidden = true
        label.setAccessibilityElement(false)
        return label
    }

    private func applyDateColors() {
        for index in days.indices {
            let outside = limitToAnchorMonth && !calendar.isDate(days[index], equalTo: anchor, toGranularity: .month)
            if index == todayIndex {
                dateLabels[index].textColor = .textBackgroundColor
            } else {
                dateLabels[index].textColor = outside ? .secondaryLabelColor : .labelColor
            }
            monthLabels[index].textColor = .secondaryLabelColor
        }
    }

    private func showsMonthName(_ index: Int) -> Bool {
        let day = days[index]
        if index == 0 || calendar.component(.day, from: day) == 1 { return true }
        return index > 0 && !calendar.isDate(day, equalTo: days[index - 1], toGranularity: .month)
    }

    private func dateAccessibility(_ index: Int) -> String {
        var text = days[index].formatted(.dateTime.weekday(.wide).month(.wide).day().year())
        if index == todayIndex { text += ", today" }
        if limitToAnchorMonth, !calendar.isDate(days[index], equalTo: anchor, toGranularity: .month) {
            text += ", outside this month"
        }
        let count = events(on: index).count
        if count == 0 { text += ". No reported resets" }
        else { text += ". \(count) reported reset\(count == 1 ? "" : "s")" }
        return text
    }

    private func syncButtons(preserving focusedID: String?) {
        let incoming = Set(events.map(\.id))
        for id in buttons.keys.filter({ !incoming.contains($0) }) {
            buttons[id]?.removeFromSuperview()
            buttons[id] = nil
        }
        for event in events {
            let button: UsageEventButton
            if let existing = buttons[event.id] {
                button = existing
            } else {
                button = UsageEventButton()
                button.autoresizingMask = []
                button.onActivate = { [weak self] id in self?.onActivate?(id) }
                button.onHover = { [weak self] id in self?.onHover?(id) }
                button.onHoverEnd = { [weak self] id in self?.onHoverEnd?(id) }
                buttons[event.id] = button
                addSubview(button)
            }
            button.apply(event)
        }
        let order = events.map(\.id)
        if buttonOrder != order {
            let focused = focusedID.flatMap { buttons[$0] }
            for id in order {
                guard let button = buttons[id] else { continue }
                button.removeFromSuperview()
                addSubview(button)
            }
            buttonOrder = order
            if let focused, window?.firstResponder !== focused {
                window?.makeFirstResponder(focused)
            }
        }
        applyChrome()
    }

    private func events(on day: Int) -> [HomeCalendarEventModel] {
        guard eventsByDay.indices.contains(day) else { return [] }
        return eventsByDay[day]
    }

    private func applyChrome() {
        for (id, button) in buttons {
            button.setChrome(selected: id == selectedEventID, hovered: id == hoveredEventID && id != selectedEventID)
        }
    }
}

@MainActor
private final class UsageEventButton: NSButton {
    private(set) var eventID = ""
    var onActivate: ((String) -> Void)?
    var onHover: ((String) -> Void)?
    var onHoverEnd: ((String) -> Void)?

    private let icon = HomePassImageView()
    /// "13:11 · 5-hour resets". Tail truncation shortens the scope; the time is first and stays whole.
    private let resetLine = HomeStaticTextField(labelWithString: "")
    /// "17% left · personal", after the Low or Limit reached symbol.
    private let detailLine = HomeStaticTextField(labelWithString: "")
    private let detailRow = NSStackView()
    private var symbol: NSImageView?
    private var model: HomeCalendarEventModel?
    private var selected = false
    private var hovered = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        title = ""
        imagePosition = .noImage
        focusRingType = .exterior
        clipsToBounds = true
        wantsLayer = true
        target = self
        action = #selector(activate(_:))
        icon.imageScaling = .scaleProportionallyDown
        icon.setAccessibilityElement(false)
        for field in [resetLine, detailLine] {
            field.lineBreakMode = .byTruncatingTail
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            field.setAccessibilityElement(false)
        }
        detailLine.font = .systemFont(ofSize: 11)
        icon.translatesAutoresizingMaskIntoConstraints = false
        let top = NSStackView(views: [icon, resetLine])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 4
        let spacer = NSView()
        spacer.translatesAutoresizingMaskIntoConstraints = false
        spacer.widthAnchor.constraint(equalToConstant: 14).isActive = true
        detailRow.addArrangedSubview(spacer)
        detailRow.addArrangedSubview(detailLine)
        detailRow.orientation = .horizontal
        detailRow.alignment = .centerY
        detailRow.spacing = 4
        let lines = NSStackView(views: [top, detailRow])
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 1
        lines.translatesAutoresizingMaskIntoConstraints = false
        for decorativeView in [top, detailRow, lines, spacer] {
            decorativeView.setAccessibilityElement(false)
        }
        addSubview(lines)
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 14),
            icon.heightAnchor.constraint(equalToConstant: 14),
            lines.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            lines.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            lines.centerYAnchor.constraint(equalTo: centerYAnchor),
            top.trailingAnchor.constraint(lessThanOrEqualTo: lines.trailingAnchor),
            detailRow.trailingAnchor.constraint(lessThanOrEqualTo: lines.trailingAnchor)
        ])
        setAccessibilityRole(.button)
        setAccessibilityElement(true)
        setAccessibilityChildren([])
        setAccessibilityHelp("Press Return to show this account.")
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ event: HomeCalendarEventModel) {
        guard event != model else { return }
        let toneChanged = event.tone != model?.tone
        model = event
        eventID = event.id
        identifier = NSUserInterfaceItemIdentifier(event.id)
        setAccessibilityIdentifier(event.id)
        setAccessibilityLabel(event.accessibilityLabel)
        toolTip = event.toolTip
        let image = ProviderIcons.images[event.provider]
        if icon.image !== image { icon.image = image }
        icon.isHidden = image == nil
        if toneChanged {
            symbol?.removeFromSuperview()
            symbol = HomeText.stateSymbol(event.tone, size: 10)
            if let symbol { detailRow.insertArrangedSubview(symbol, at: 1) }
        }
        refreshColors()
    }

    func setChrome(selected: Bool, hovered: Bool) {
        let changed = self.selected != selected || self.hovered != hovered
        self.selected = selected
        self.hovered = hovered
        setAccessibilitySelected(selected)
        if changed || layer?.backgroundColor == nil && (selected || hovered) {
            refreshColors()
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: bounds,
                                      options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                      owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(eventID)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverEnd?(eventID)
    }

    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case "\r", "\u{3}":
            performClick(nil)
        case "\u{1b}":
            _ = NSApp.sendAction(#selector(NSResponder.cancelOperation(_:)), to: nil, from: self)
        default:
            super.keyDown(with: event)
        }
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5).fill()
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshColors()
    }

    @objc private func activate(_ sender: Any?) { onActivate?(eventID) }

    private func refreshColors() {
        guard let model else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let fill: NSColor? = selected ? .selectedContentBackgroundColor
                : hovered ? .unemphasizedSelectedContentBackgroundColor : nil
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.cornerRadius = fill == nil ? 0 : 5
            layer?.backgroundColor = fill?.cgColor
            CATransaction.commit()
            let primary: NSColor = selected ? .alternateSelectedControlTextColor : .labelColor
            let reset = NSMutableAttributedString(string: model.timeText, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold), .foregroundColor: primary
            ])
            reset.append(NSAttributedString(string: " · \(model.scopeText)", attributes: [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: primary
            ]))
            resetLine.attributedStringValue = reset
            detailLine.stringValue = "\(model.remainingText) · \(model.shortIdentity)"
            detailLine.textColor = primary
            icon.contentTintColor = primary
            symbol?.contentTintColor = selected ? primary : model.tone.symbolColor
        }
    }
}
