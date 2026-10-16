import AppKit
import Testing
import UsageCore
@testable import AIUsageStats

/// Home content at the minimum window width beside a 260 pt sidebar: every account row and column is
/// visible without a nested vertical scroller or horizontal scrolling.
@Test @MainActor
func homeTableShowsEveryRowAndColumnAtTheMinimumWidth() async throws {
    _ = NSApplication.shared
    let model = ApplicationModel(isDemo: true)
    await model.load()
    let home = HomeViewController(model: model)
    home.isAccountLoadComplete = { true }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = home.view
    home.render()
    window.contentView?.layoutSubtreeIfNeeded()
    var pending: [NSView] = [home.view]
    var found: NSTableView?
    while let view = pending.popLast() {
        if let table = view as? NSTableView, table.accessibilityLabel() == "Account usage" { found = table; break }
        pending.append(contentsOf: view.subviews)
    }
    let table = try #require(found)
    let clip = try #require(table.enclosingScrollView?.contentView)
    #expect(table.numberOfRows == model.profiles.count)
    let columnExtent = table.rect(ofColumn: table.numberOfColumns - 1).maxX
    #expect(columnExtent <= clip.bounds.width + 1)
    #expect(table.frame.height <= clip.bounds.height + 0.5)
    #expect(table.tableColumns.allSatisfy { $0.width >= $0.minWidth })
    #expect(home.toolbarItemIdentifiers.contains(.homeRefreshAll))
    #expect(!home.windowSubtitle.isEmpty)
}

/// HOME-28: Home renders its readings after accounts load. From a sidebar control, the key view loop then
/// reaches the account table and the calendar events instead of returning to the sidebar.
@Test @MainActor
func keyViewLoopReachesHomeReadingsAfterAccountsLoad() async throws {
    _ = NSApplication.shared
    let model = ApplicationModel(isDemo: true)
    let home = HomeViewController(model: model)
    var loaded = false
    home.isAccountLoadComplete = { loaded }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 780),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let sidebar = NSTableView(frame: NSRect(x: 0, y: 0, width: 260, height: 780))
    let content = NSView(frame: window.contentLayoutRect)
    home.view.frame = NSRect(x: 260, y: 0, width: 1020, height: 780)
    content.addSubview(sidebar)
    content.addSubview(home.view)
    window.contentView = content
    home.render()
    window.recalculateKeyViewLoop()
    await model.load()
    loaded = true
    home.render()
    window.contentView?.layoutSubtreeIfNeeded()
    var loop: [NSView] = []
    var next = sidebar.nextKeyView
    while let view = next, view !== sidebar, loop.count < 500 {
        loop.append(view)
        next = view.nextKeyView
    }
    #expect(loop.contains { ($0 as? NSTableView)?.accessibilityLabel() == "Account usage" })
    #expect(loop.contains { String(describing: type(of: $0)) == "UsageEventButton" })
}

/// HOME-12: at seven 96 pt columns, the narrowest the calendar draws before it scrolls, every event in
/// 2 Weeks and Month is two whole single-line rows. The reset time and the percentage keep their full
/// width, no line is cut vertically, and events in one day never overlap.
@Test @MainActor
func calendarEventTextFitsItsFrameAtTheMinimumColumnWidth() throws {
    _ = NSApplication.shared
    let snapshots = Dictionary(uniqueKeysWithValues: DemoFixtures.homeSnapshots.map { ($0.profileID, $0) })
    let now = Date()
    let calendar = Calendar.current
    let overview = UsageOverview(profiles: DemoFixtures.homeProfiles, snapshots: snapshots, now: now)
    for mode in [UsageCalendarMode.twoWeeks, .month] {
        let period = UsageCalendarPeriod(mode: mode, containing: now, calendar: calendar)
        let view = UsageCalendarView(frame: NSRect(x: 0, y: 0, width: 672, height: 900))
        view.apply(period: period, events: overview.resetEvents, mode: mode, anchor: now, now: now, calendar: calendar)
        view.layoutSubtreeIfNeeded()
        let models = HomeInterfaceFormatting.calendarEvents(overview.resetEvents, days: period.days, now: now, calendar: calendar)
        #expect(!models.isEmpty)
        var buttons: [NSView] = []
        for model in models {
            let button = try #require(view.eventView(for: model.id))
            button.layoutSubtreeIfNeeded()
            buttons.append(button)
            let fields = button.subviews.compactMap { $0 as? NSTextField }
            #expect(fields.count == 4)
            for field in fields {
                #expect(field.frame.minY >= 0 && field.frame.maxY <= button.bounds.height + 0.5)
                #expect(field.frame.minX >= 0 && field.frame.maxX <= button.bounds.width + 0.5)
                #expect(drawnSize(field).height <= field.frame.height + 0.5)
            }
            for whole in [model.timeText, model.remainingText] {
                let field = try #require(fields.first { $0.stringValue == whole })
                #expect(drawnSize(field).width <= field.frame.width + 0.5)
            }
            // HOME-26: a scope or identity field that shows draws at least its first letter and an ellipsis.
            for field in fields where !field.isHidden && field.stringValue.hasPrefix("· ") {
                let fragment = NSTextField(labelWithString: String(field.stringValue.prefix(3)) + "…")
                fragment.font = field.font
                #expect(drawnSize(fragment).width <= field.frame.width + 0.5)
            }
        }
        for (index, button) in buttons.enumerated() {
            #expect(button.frame.maxY <= (button.superview?.bounds.height ?? 0))
            for other in buttons[(index + 1)...] {
                #expect(!button.frame.intersects(other.frame))
            }
        }
    }
}

/// HOME-31: the Reset Calendar sits below a short window. A period command moves its heading into view, since
/// the toolbar controls change only the calendar.
@Test @MainActor
func periodCommandRevealsTheResetCalendar() async throws {
    _ = NSApplication.shared
    let model = ApplicationModel(isDemo: true)
    await model.load()
    let home = HomeViewController(model: model)
    home.isAccountLoadComplete = { true }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1020, height: 400),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = home.view
    home.render()
    window.contentView?.layoutSubtreeIfNeeded()
    let scroll = try #require(home.view as? NSScrollView)
    var pending: [NSView] = [home.view]
    var found: NSTextField?
    while let view = pending.popLast() {
        if let field = view as? NSTextField, field.stringValue == "Reset Calendar" { found = field; break }
        pending.append(contentsOf: view.subviews)
    }
    let heading = try #require(found)
    func headingShows() -> Bool {
        scroll.contentView.documentVisibleRect.contains(heading.convert(heading.bounds, to: scroll.documentView))
    }
    #expect(!headingShows())
    home.showNextPeriod(nil)
    #expect(headingShows())
}

/// HOME-14, HOME-22: at the minimum window (1020 pt beside a 260 pt sidebar, less margins and a vertical
/// scroller: 712 pt of table), no quota cell truncates. `0% left`, `Limit reached`, `Last known`, a
/// model-scoped window name, and the reset time each fit on their own line, for current, sign-in, stale,
/// and missing readings.
@Test @MainActor
func quotaCellTextFitsAtTheMinimumWindowWidth() throws {
    _ = NSApplication.shared
    var states: Set<String> = []
    for fixture in [DemoFixtures.homeSnapshots, DemoFixtures.homeReadingStateSnapshots] {
        let snapshots = Dictionary(uniqueKeysWithValues: fixture.map { ($0.profileID, $0) })
        let now = Date()
        let overview = UsageOverview(profiles: DemoFixtures.homeProfiles, snapshots: snapshots, now: now)
        let tableView = UsageOverviewTableView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 712, height: 640),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = tableView
        tableView.apply(rows: HomeInterfaceFormatting.rows(for: overview.accounts, now: now, calendar: .current),
                        headings: HomeInterfaceFormatting.headings(for: overview.accounts))
        tableView.layoutSubtreeIfNeeded()
        var pending: [NSView] = [tableView]
        var found: NSTableView?
        while let view = pending.popLast() {
            if let table = view as? NSTableView { found = table; break }
            pending.append(contentsOf: view.subviews)
        }
        let table = try #require(found)
        for row in 0..<table.numberOfRows {
            for column in 1..<table.numberOfColumns {
                let cell = try #require(table.view(atColumn: column, row: row, makeIfNecessary: true))
                cell.layoutSubtreeIfNeeded()
                var fields: [NSTextField] = []
                var queue = cell.subviews
                while let view = queue.popLast() {
                    if let field = view as? NSTextField, !field.isHiddenOrHasHiddenAncestor { fields.append(field) }
                    queue.append(contentsOf: view.subviews)
                }
                for field in fields {
                    states.insert(field.stringValue)
                    let frame = field.convert(field.bounds, to: cell)
                    #expect(drawnSize(field).width <= frame.width + 0.5, "\(field.stringValue) truncates")
                    #expect(frame.maxX <= cell.bounds.width + 0.5, "\(field.stringValue) leaves its cell")
                }
            }
        }
    }
    #expect(states.contains("Limit reached"))
    #expect(states.contains("Low"))
    #expect(states.contains("Last known"))
    #expect(states.contains("Weekly · Fable 5"))
}

/// The size the field's cell needs to draw its whole string. A tail-truncating field reports a smaller
/// intrinsic width, so it cannot prove the text is whole.
@MainActor
private func drawnSize(_ field: NSTextField) -> NSSize {
    field.cell?.cellSize ?? field.intrinsicContentSize
}

/// HOME-18: one color per state reaches 3:1 for the state symbol in light appearance, on the white Home
/// background and on the light sidebar, in every surface that draws it.
@Test @MainActor
func stateSymbolColorsReachThreeToOneInLightAppearance() throws {
    func luminance(_ color: NSColor) -> CGFloat {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        func linear(_ value: CGFloat) -> CGFloat { value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent) + 0.0722 * linear(rgb.blueComponent)
    }
    func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
        let (l1, l2) = (luminance(a), luminance(b))
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05)
    }
    let light = try #require(NSAppearance(named: .aqua))
    let sidebar = NSColor(srgbRed: 0xEC / 255, green: 0xED / 255, blue: 0xEE / 255, alpha: 1)
    for tone in [HomeReadingTone.warning, .critical] {
        var symbol = NSColor.clear
        light.performAsCurrentDrawingAppearance { symbol = tone.symbolColor.usingColorSpace(.sRGB) ?? tone.symbolColor }
        #expect(contrast(symbol, .white) >= 3, "\(tone) on white")
        #expect(contrast(symbol, sidebar) >= 3, "\(tone) on the sidebar")
    }
}
