import AppKit
import UsageCore

enum HomeReadingTone: Equatable {
    case neutral
    case warning
    case critical

    /// The words carry the meaning. Text stays in label color.
    var word: String? {
        switch self {
        case .neutral: nil
        case .warning: "Low"
        case .critical: "Limit reached"
        }
    }

    var symbolName: String? {
        switch self {
        case .neutral: nil
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "exclamationmark.octagon.fill"
        }
    }

    /// Semantic color for the state symbol only, never for text. Every surface (table, calendar, popover,
    /// sidebar) uses this one color per state.
    var symbolColor: NSColor {
        switch self {
        case .neutral: .labelColor
        case .warning: StateSymbolColor.warning
        case .critical: StateSymbolColor.critical
        }
    }
}

/// State symbol colors. In light appearances the system color is darkened so the symbol reaches 3:1 on white
/// and on the sidebar; plain systemOrange measures 2.33:1 on white. Dark appearances keep the system color,
/// which already exceeds 3:1.
enum StateSymbolColor {
    static let warning = darkenedInLightAppearance(.systemOrange)
    static let critical = darkenedInLightAppearance(.systemRed)

    private static func darkenedInLightAppearance(_ color: NSColor) -> NSColor {
        func resolved(_ name: NSAppearance.Name) -> NSColor {
            var value = color
            NSAppearance(named: name)?.performAsCurrentDrawingAppearance { value = color.usingColorSpace(.sRGB) ?? color }
            return value
        }
        let light = resolved(.aqua).blended(withFraction: 0.3, of: .black) ?? color
        let dark = resolved(.darkAqua)
        return NSColor(name: nil) { appearance in appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
}

/// One quota reading in a table cell. `preface` lines name the window (`Weekly · Fable 5`) and qualify an old
/// value (`Last known`) above it, so `primary` is the value alone and stays whole in a narrow column. A
/// non-neutral `tone` supplies the `Low` or `Limit reached` line below, and the accessibility label carries the
/// full "0% left, Limit reached" phrase.
struct HomeReadingLine: Equatable {
    var preface: [String] = []
    var primary: String
    var secondary: String?
    var tertiary: String?
    var tone: HomeReadingTone
    var accessibilityLabel: String
    var toolTip: String
    /// A permanent provider gap, drawn in secondary color at regular weight.
    var isQuiet = false
}

enum HomeMeterCell: Equatable {
    case message(HomeReadingLine)
    case meters([HomeReadingLine])
}

struct HomeColumnHeadings: Equatable {
    var session: String
    var weekly: String
    var other: String
}

struct HomeAccountRow: Equatable, Identifiable {
    var id: UUID
    var provider: Provider
    var title: String
    var identity: String
    var identityIsEmail: Bool
    var plan: String?
    var status: String?
    var showsReconnect: Bool
    var session: HomeMeterCell
    var weekly: HomeMeterCell
    var other: HomeMeterCell
    var earned: HomeMeterCell
    var updatedPrimary: String
    var updatedSecondary: String?
    var accessibilityLabel: String
    var toolTip: String
}

/// One reset on the calendar: time and scope first (`13:11 · 5-hour`), then what is left now. The section
/// title says these are resets, so the visible scope omits the word; the label and tooltip keep it. A
/// model-scoped window shows only its model (`14:18 · Sonnet`), so it never truncates to look like the
/// account's general weekly reset; the label, tooltip, and popover keep the full `Weekly · Sonnet`.
struct HomeCalendarEventModel: Equatable, Identifiable {
    var id: String
    var provider: Provider
    var timeText: String
    var scopeText: String
    var remainingText: String
    var tone: HomeReadingTone
    var shortIdentity: String
    var accessibilityLabel: String
    var toolTip: String
    var dayIndex: Int
}

/// One line of Home's Weekly Totals. `provider` is set on the first line of each provider's group.
struct HomeTotalLine: Equatable {
    var provider: Provider?
    var label: String
    var value: String
    var detail: String
    var accessibilityLabel: String
    var toolTip: String
}

/// One account in the unavailable-readings banner.
struct HomeAttentionItem: Equatable, Identifiable {
    var id: UUID
    var text: String
    var showsReconnect: Bool
}

struct HomeDetailContent: Equatable {
    struct Row: Equatable {
        var label: String
        var value: String
        var detail: String?
        var tone: HomeReadingTone
        var toolTip: String
    }

    var accountID: UUID
    var heading: String
    var rows: [Row]
    var updated: String
    var updatedToolTip: String
}

@MainActor
enum HomeText {
    static func label(_ string: String, size: CGFloat, weight: NSFont.Weight = .regular,
                      digits: Bool = false, color: NSColor = .labelColor) -> NSTextField {
        let field = HomeStaticTextField(labelWithString: string)
        field.font = digits ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
        field.textColor = color
        field.lineBreakMode = .byTruncatingTail
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.setContentHuggingPriority(.required, for: .vertical)
        return field
    }

    /// State symbol for Low and Limit reached. Nil for an ordinary reading.
    static func stateSymbol(_ tone: HomeReadingTone, color: NSColor? = nil, size: CGFloat = 11) -> NSImageView? {
        guard let name = tone.symbolName, let word = tone.word,
              let image = NSImage(systemSymbolName: name, accessibilityDescription: word)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: size, weight: .semibold)) else { return nil }
        let view = HomePassImageView(image: image)
        view.contentTintColor = color ?? tone.symbolColor
        view.setContentHuggingPriority(.required, for: .horizontal)
        view.setContentCompressionResistancePriority(.required, for: .horizontal)
        view.setAccessibilityElement(false)
        return view
    }
}

/// A scroll view nested in the Home document. Vertical scrolling belongs to the document.
@MainActor
class HomeNestedScrollView: NSScrollView {
    /// The enclosing document owns toolbar insets; a nested view must not shift as it scrolls under the toolbar.
    override var automaticallyAdjustsContentInsets: Bool {
        get { false }
        set {}
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            nextResponder?.scrollWheel(with: event)
        } else {
            super.scrollWheel(with: event)
        }
    }
}

@MainActor
final class HomeStaticTextField: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var acceptsFirstResponder: Bool { false }
}

@MainActor
final class HomePassImageView: NSImageView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

enum HomeInterfaceFormatting {
    static let emptyPeriodText = "No reported resets in this period."
    static let addAccountTitle = "Add an Account"
    static let addAccountMessage = "Add a Claude or Codex account to see remaining quota and reset times."
    static let loadingMessage = "Loading accounts…"
    static let loadErrorTitle = "Accounts Could Not Be Loaded"
    static let loadErrorMessage = "AI Usage Stats could not read its saved account list. Saved accounts were not changed. Choose Retry Loading Accounts to try again."
    static let sessionColumnHelp = "Remaining quota for the 5-hour window. A window is placed here only when its reported duration is 5 hours, or when its name says 5 hours and no duration was reported."
    static let weeklyColumnHelp = "Remaining quota for the weekly window. Other durations stay in the last quota column."
    static let otherColumnHelp = "Every other reported quota window, including model-scoped limits such as Weekly · Fable 5. Names come from the reading."
    static let earnedColumnHelp = "Earned resets available and their next expiry. Expiry is separate from usage window resets and is not placed on the calendar."
    static let updatedColumnHelp = "When this account's usage was last read."
    static let unknownResetText = "Reset time unknown"
    static let noPendingResetText = "No reset pending"

    static func periodTitle(mode: UsageCalendarMode, period: UsageCalendarPeriod, anchor: Date, calendar: Calendar) -> String {
        switch mode {
        case .month:
            return anchor.formatted(.dateTime.month(.wide).year())
        case .twoWeeks:
            guard let first = period.days.first, let last = period.days.last else { return "" }
            return rangeTitle(from: first, to: last, calendar: calendar)
        }
    }

    static func rangeTitle(from start: Date, to end: Date, calendar: Calendar) -> String {
        let startYear = calendar.component(.year, from: start)
        let endYear = calendar.component(.year, from: end)
        let startMonth = calendar.component(.month, from: start)
        let endMonth = calendar.component(.month, from: end)
        let startDay = calendar.component(.day, from: start)
        let endDay = calendar.component(.day, from: end)
        let startMonthText = start.formatted(.dateTime.month(.abbreviated))
        let endMonthText = end.formatted(.dateTime.month(.abbreviated))
        if startYear == endYear, startMonth == endMonth {
            return "\(startMonthText) \(startDay) – \(endDay), \(startYear)"
        }
        if startYear == endYear {
            return "\(startMonthText) \(startDay) – \(endMonthText) \(endDay), \(startYear)"
        }
        return "\(startMonthText) \(startDay), \(startYear) – \(endMonthText) \(endDay), \(endYear)"
    }

    static func readingContext(now: Date, calendar: Calendar) -> String {
        let zone = calendar.timeZone.abbreviation(for: now) ?? calendar.timeZone.identifier
        return "Remaining percentages from the latest reading · Times in \(zone)"
    }

    static func weekdayTitles(days: [Date], calendar: Calendar) -> [String] {
        let symbols = calendar.shortWeekdaySymbols
        return (0..<7).map { column in
            guard days.indices.contains(column) else { return "" }
            let weekday = calendar.component(.weekday, from: days[column])
            let index = weekday - 1
            guard symbols.indices.contains(index) else { return "" }
            return symbols[index]
        }
    }

    static func headings(for accounts: [UsageOverviewAccount]) -> HomeColumnHeadings {
        let windows = accounts.flatMap { $0.snapshot?.windows ?? [] }
        let sessions = windows.filter { $0.role == .session }
        let others = otherScopeLabels(accounts)
        let otherTitle = others.count == 1 ? others.first ?? "Other limits" : "Other limits"
        return HomeColumnHeadings(session: sharedDurationTitle(sessions) ?? "Session", weekly: "Weekly", other: otherTitle)
    }

    static func rows(for accounts: [UsageOverviewAccount], now: Date, calendar: Calendar) -> [HomeAccountRow] {
        // A shared last-column heading names the scope, so its cells show only the value.
        let namesOther = otherScopeLabels(accounts).count > 1
        return accounts.map { accountRow($0, namesOther: namesOther, now: now, calendar: calendar) }
    }

    private static func otherScopeLabels(_ accounts: [UsageOverviewAccount]) -> Set<String> {
        Set(accounts.flatMap { $0.snapshot?.windows ?? [] }.filter { $0.role == .other }.map(scopeLabel))
    }

    static func calendarEvents(_ events: [UsageResetEvent], days: [Date], now: Date, calendar: Calendar) -> [HomeCalendarEventModel] {
        events.compactMap { event in
            guard event.remainingPercent.isFinite, event.resetsAt > now,
                  let dayIndex = days.firstIndex(where: { calendar.isDate($0, inSameDayAs: event.resetsAt) }) else { return nil }
            let scope = scopeLabel(event.window)
            let exact = InterfaceFormatting.exactDate(event.resetsAt)
            let value = remainingText(event.remainingPercent)
            let label = "\(scope) resets \(exact). \(event.provider.title) \(event.identity), \(value) now"
            return HomeCalendarEventModel(id: event.id, provider: event.provider, timeText: timeText(event.resetsAt),
                                          scopeText: calendarScope(event.window), remainingText: "\(percentText(event.remainingPercent)) left",
                                          tone: tone(for: event.remainingPercent), shortIdentity: event.shortIdentity,
                                          accessibilityLabel: label,
                                          toolTip: "\(label). Latest reading, not a forecast.", dayIndex: dayIndex)
        }
    }

    static func detailContent(account: UsageOverviewAccount, now: Date, calendar: Calendar) -> HomeDetailContent {
        HomeDetailContent(accountID: account.id, heading: heading(account),
                          rows: detailRows(account, now: now, calendar: calendar),
                          updated: updatedSentence(account, now: now),
                          updatedToolTip: updatedToolTip(account, now: now))
    }

    /// Each account whose readings are not current, named with its state and what to do.
    static func attentionItems(_ accounts: [UsageOverviewAccount], now: Date) -> [HomeAttentionItem] {
        accounts.compactMap { account in
            switch account.summary {
            case .available, .inactive: return nil
            case .unknown, .stale, .unavailable, .authenticationRequired: break
            }
            let basis = readingBasis(account, now: now)
            let state: String
            // A reused Codex CLI login is signed in outside the app, so it offers no Reconnect….
            let reconnectable = account.profile.source != .codexDefaultLogin
            switch basis {
            case .authentication:
                state = reconnectable ? "Sign-in required. Choose Reconnect…" : "Sign-in required. Sign in to the Codex CLI in Terminal, then choose Refresh All."
            case .historical: state = "\(staleText(account, now: now)). Choose Refresh All to read it again."
            case .unavailable: state = "Unavailable. Choose Refresh All to try again."
            case .absent: state = "\(absentStatus(account)). Choose Refresh All to try again."
            case .current: state = accountStatus(account, basis: basis, now: now) ?? "Some usage unknown"
            }
            return HomeAttentionItem(id: account.id, text: "\(account.profile.provider.title) \(account.shortIdentity): \(state)",
                                     showsReconnect: basis == .authentication && reconnectable)
        }
    }

    // MARK: Weekly totals

    /// Weekly totals for each provider with two or more accounts. A single account's total is its own weekly value,
    /// which the table already shows.
    static func totalLines(_ overview: UsageOverview, now: Date, calendar: Calendar) -> [HomeTotalLine] {
        let names = Dictionary(uniqueKeysWithValues: overview.accounts.map { ($0.id, "\($0.profile.provider.title) \($0.shortIdentity)") })
        return overview.providers.filter { $0.accountCount > 1 }.flatMap { provider -> [HomeTotalLine] in
            let pools = [provider.weekly] + provider.scopedWeekly
            var lines = pools.map { pool in
                let label = poolLabel(pool)
                let value = poolValue(pool)
                let detail = poolUnknownText(pool) ?? ""
                let help = poolHelp(pool, names: names)
                return HomeTotalLine(label: label, value: value, detail: detail,
                                     accessibilityLabel: "\(provider.provider.title) \(label) total, \(value)\(detail.isEmpty ? "" : ", \(detail)")",
                                     toolTip: help)
            }
            let reset = nextResetText(provider.nextReset, names: names, now: now, calendar: calendar)
            lines.append(HomeTotalLine(label: "Next reset", value: reset.value, detail: reset.detail,
                                       accessibilityLabel: "\(provider.provider.title) next weekly reset, \(reset.value), \(reset.help)",
                                       toolTip: reset.help))
            lines[0].provider = provider.provider
            return lines
        }
    }

    /// `Weekly`, or `Weekly · Fable 5` for a model or meter total.
    static func poolLabel(_ pool: QuotaPool) -> String {
        pool.scopeName.map { "Weekly · \($0)" } ?? "Weekly"
    }

    /// `90% of 300% left`, `Unknown` when no account has a current reading (never `0%`), or `Not supported`
    /// when no account reports the window.
    static func poolValue(_ pool: QuotaPool) -> String {
        if pool.countedAccountIDs.isEmpty, pool.unknownAccountIDs.isEmpty { return "Not supported" }
        guard let remaining = pool.remainingPercent else { return "Unknown" }
        return "\(percentText(remaining)) of \(Int(pool.capacityPercent))% left"
    }

    /// `1 account unknown`, or nil when every account in the pool is counted.
    static func poolUnknownText(_ pool: QuotaPool) -> String? {
        let count = pool.unknownAccountIDs.count
        guard count > 0 else { return nil }
        return "\(count) account\(count == 1 ? "" : "s") unknown"
    }

    static func poolHelp(_ pool: QuotaPool, names: [UUID: String]) -> String {
        let label = poolLabel(pool)
        var parts = ["\(label) remaining quota summed over accounts with a current reading: \(poolValue(pool))."]
        if !pool.countedAccountIDs.isEmpty {
            parts.append("Counted: \(pool.countedAccountIDs.compactMap { names[$0] }.joined(separator: ", ")).")
        }
        if !pool.unknownAccountIDs.isEmpty {
            parts.append("Not counted because the reading is stale, failed, missing, or unmeasured: "
                + "\(pool.unknownAccountIDs.compactMap { names[$0] }.joined(separator: ", ")). Unknown is not zero.")
        }
        return parts.joined(separator: " ")
    }

    /// Value `+24%` and detail `in 1d 4h · Tue 21:59 · Claude personal`, with the exact date in the help text.
    static func nextResetText(_ reset: NextQuotaReset, names: [UUID: String], now: Date, calendar: Calendar)
        -> (value: String, detail: String, help: String) {
        switch reset {
        case .reset(let reset):
            let accounts = reset.accountIDs.count == 1 ? names[reset.accountIDs[0]] ?? "1 account" : "\(reset.accountIDs.count) accounts"
            let relative = "in \(UsageFormatting.countdown(to: reset.resetsAt, now: now))"
            let value = "+\(percentText(reset.gainPercent))"
            return (value, "\(relative) · \(scheduleText(reset.resetsAt, now: now, calendar: calendar)) · \(accounts)",
                    "\(accounts) resets \(relative), \(InterfaceFormatting.exactDate(reset.resetsAt)), adding \(value) to the weekly total.")
        case .nonePending:
            return (noPendingResetText, "", "Every counted account has used none of its weekly quota.")
        case .unknown:
            return ("Unknown", "", "No current weekly reading reports when used quota resets.")
        }
    }

    /// `Ahead of pace` when more quota is used than the share of the window that has passed.
    static func paceText(_ verdict: QuotaPace.Verdict) -> String {
        switch verdict {
        case .ahead: "Ahead of pace"
        case .onPace: "On pace"
        case .under: "Under pace"
        }
    }

    static func paceSentence(_ pace: QuotaPace) -> String {
        "\(paceText(pace.verdict)): \(percentText(pace.usedPercent)) used with \(percentText(pace.elapsedPercent)) of the window passed"
    }

    /// `Usable in 8h 58m` for an account with a fully used 5-hour or weekly window.
    static func usableText(_ date: Date?, now: Date) -> String {
        guard let date else { return "Usable time unknown" }
        return "Usable in \(UsageFormatting.countdown(to: date, now: now))"
    }

    /// Value text with its state word: "17% left, Low".
    static func remainingText(_ remaining: Double) -> String {
        let value = "\(percentText(remaining)) left"
        return tone(for: remaining).word.map { "\(value), \($0)" } ?? value
    }

    static func percentText(_ value: Double) -> String {
        guard value.isFinite else { return "Unknown" }
        if value > 0, value < 0.1 {
            let tenth = (value * 10).rounded() / 10
            if tenth < 0.1 { return "<0.1%" }
        }
        let nearest = value.rounded()
        if abs(value - nearest) < 0.05 {
            let whole = Int(nearest)
            if value > 0, whole <= 0 { return "<0.1%" }
            return "\(whole)%"
        }
        let fractional = String(format: "%.1f%%", value)
        if value > 0, fractional == "0.0%" || fractional == "0%" { return "<0.1%" }
        return fractional
    }

    /// Measured zero is the only limit reached. Any positive remaining at or below 20 is low.
    static func tone(for remaining: Double) -> HomeReadingTone {
        guard remaining.isFinite else { return .neutral }
        if remaining == 0 { return .critical }
        if remaining > 0, remaining <= 20 { return .warning }
        return .neutral
    }

    /// Vocabulary names: "5-hour", "Weekly", model-scoped "Weekly · Fable 5".
    static func scopeLabel(_ window: UsageWindow) -> String {
        if let scoped = window.modelScope {
            return "\(baseName(scoped.base, duration: window.windowDurationMinutes)) · \(scoped.name)"
        }
        if let named = window.namedMeter {
            let duration = window.windowDurationMinutes.map(durationLabel) ?? baseName(named.suffix, duration: nil)
            return window.isOrdinaryCodexMeter ? duration : "\(duration) · \(named.prefix)"
        }
        if let minutes = window.windowDurationMinutes { return durationLabel(minutes) }
        return InterfaceFormatting.usageTitle(window)
    }

    static func durationLabel(_ minutes: Int) -> String {
        if minutes == 300 { return "5-hour" }
        if minutes == 10_080 { return "Weekly" }
        if minutes > 0, minutes % 1_440 == 0 {
            let days = minutes / 1_440
            return days == 7 ? "Weekly" : "\(days)-day"
        }
        if minutes > 0, minutes % 60 == 0 { return "\(minutes / 60)-hour" }
        return minutes == 1 ? "1-minute" : "\(minutes)-minute"
    }

    private static func accountRow(_ account: UsageOverviewAccount, namesOther: Bool, now: Date, calendar: Calendar) -> HomeAccountRow {
        let email = InterfaceFormatting.accountEmail(account.profile)
        let identityIsEmail = email != "Email unavailable"
        let identity = identityIsEmail ? email : "Email unavailable"
        let basis = readingBasis(account, now: now)
        let plan = planName(account)
        let status = accountStatus(account, basis: basis, now: now)
        let updated = updatedParts(account, now: now, basis: basis)
        var spoken = ["\(account.profile.provider.title) \(account.shortIdentity)"]
        spoken.append(identityIsEmail ? "Verified email \(identity)" : "Email unavailable. Saved name \(account.identity)")
        if let plan { spoken.append("Plan \(plan)") }
        if let status { spoken.append(status) }
        spoken.append("Updated \(updated.primary)\(updated.secondary.map { ", \($0)" } ?? "")")
        let toolTip = spoken.joined(separator: ". ")
        func cell(_ role: UsageWindowRole) -> HomeMeterCell {
            meterCell(role, account: account, namesWindow: role == .other && namesOther, now: now, calendar: calendar, basis: basis)
        }
        return HomeAccountRow(id: account.id, provider: account.profile.provider,
                              title: "\(account.profile.provider.title) \(account.shortIdentity)",
                              identity: identity, identityIsEmail: identityIsEmail, plan: plan, status: status,
                              showsReconnect: basis == .authentication && account.profile.source != .codexDefaultLogin,
                              session: cell(.session), weekly: cell(.weekly), other: cell(.other),
                              earned: earnedCell(account, now: now, calendar: calendar),
                              updatedPrimary: updated.primary, updatedSecondary: updated.secondary,
                              accessibilityLabel: toolTip, toolTip: toolTip)
    }

    /// Same admission rule as `UsageOverview`: a fresh available snapshot keeps known windows current.
    /// One missing percentage does not blank the account. Age, failure, sign-in, a missing or future
    /// observation keep values unknown; age and a passed reset keep observed values historical.
    private enum ReadingBasis: Equatable {
        case current
        case historical
        case unavailable
        case authentication
        case absent
    }

    private static func readingBasis(_ account: UsageOverviewAccount, now: Date) -> ReadingBasis {
        guard let snapshot = account.snapshot, snapshot.profileID == account.id else { return .absent }
        switch snapshot.state {
        case .authenticationRequired: return .authentication
        case .unavailable: return .unavailable
        case .stale, .available: break
        }
        guard let fetchedAt = snapshot.fetchedAt, fetchedAt <= now else { return .absent }
        if snapshot.state == .stale { return .historical }
        if now.timeIntervalSince(fetchedAt) >= 300 { return .historical }
        if snapshot.currentWindows.contains(where: { $0.resetsAt.map { $0 <= now } == true }) {
            return .historical
        }
        if snapshot.windows.isEmpty { return .absent }
        return .current
    }

    private static func meterCell(_ role: UsageWindowRole, account: UsageOverviewAccount, namesWindow: Bool,
                                  now: Date, calendar: Calendar, basis: ReadingBasis) -> HomeMeterCell {
        let windows = account.snapshot?.windows ?? []
        let matching = windows.filter { $0.role == role }
        func preface(_ window: UsageWindow) -> [String] { namesWindow ? [scopeLabel(window)] : [] }
        switch basis {
        case .unavailable:
            return .message(message("Unavailable", help: "The provider did not return this quota. Choose Refresh All to try again."))
        case .authentication where windows.isEmpty:
            return .message(message("Unavailable", help: "Sign-in required. Choose Reconnect… to read this quota."))
        case .absent:
            if windows.isEmpty { return .message(message("Unavailable", help: noReadingHelp)) }
            if matching.isEmpty { return .message(message("Unknown", help: "No measured value. Unknown is not zero.")) }
            return .meters(matching.map { window in
                if window.isActive == false { return inactiveLine(window, now: now, calendar: calendar) }
                let scope = scopeLabel(window)
                return HomeReadingLine(preface: preface(window), primary: "Unknown", secondary: "Reading time unknown", tertiary: nil,
                                       tone: .neutral, accessibilityLabel: "\(scope), unknown remaining. Reading time unknown.",
                                       toolTip: "No trustworthy observation time was reported. Unknown is not zero.")
            })
        case .authentication, .current, .historical:
            if matching.isEmpty {
                var line = message("Not supported", help: "This account does not report a quota for this column.")
                line.isQuiet = true
                return .message(line)
            }
            return .meters(matching.map { window -> HomeReadingLine in
                if window.isActive == false { return inactiveLine(window, now: now, calendar: calendar) }
                let scope = scopeLabel(window)
                // A sign-in failure keeps the last known value but not its timing, as in the status menu.
                let schedule = basis == .authentication ? nil
                    : window.resetsAt.map { resetText($0, now: now, calendar: calendar) }
                    ?? (basis == .current && window.hasNoPendingReset ? noPendingResetText : unknownResetText)
                let exact = exactReset(window.resetsAt)
                guard let remaining = remainingPercent(window) else {
                    return HomeReadingLine(preface: preface(window), primary: "Unknown", secondary: schedule, tertiary: nil, tone: .neutral,
                                           accessibilityLabel: "\(scope), unknown remaining\(schedule.map { ", \($0)" } ?? ""). Unknown is not zero.",
                                           toolTip: "\(scope). Remaining quota is unknown. \(exact)")
                }
                if basis != .current {
                    // `Last known` sits on its own line above the value, so the value never truncates.
                    let reason = basis == .authentication ? "Sign-in required" : "Stale reading"
                    let spoken = "\(scope), Last known \(percentText(remaining)) left. \(exact). \(reason)."
                    return HomeReadingLine(preface: preface(window) + ["Last known"], primary: "\(percentText(remaining)) left",
                                           secondary: schedule, tertiary: nil, tone: .neutral,
                                           accessibilityLabel: spoken, toolTip: spoken)
                }
                // The table draws the state word on its own line, so the percentage and the word both stay whole.
                let pace = role == .weekly ? QuotaPace(window: window, now: now) : nil
                let spoken = "\(scope), \(remainingText(remaining)), \(exact)" + (pace.map { ". \(paceSentence($0))" } ?? "")
                return HomeReadingLine(preface: preface(window), primary: "\(percentText(remaining)) left", secondary: schedule,
                                       tertiary: pace.map { paceText($0.verdict) },
                                       tone: tone(for: remaining), accessibilityLabel: spoken, toolTip: spoken)
            })
        }
    }

    private static func inactiveLine(_ window: UsageWindow, now: Date, calendar: Calendar) -> HomeReadingLine {
        let scope = scopeLabel(window)
        let reported = window.resetsAt.map { "Reported reset \(scheduleText($0, now: now, calendar: calendar))" }
        let exact = window.resetsAt.map { InterfaceFormatting.exactDate($0) } ?? unknownResetText
        let help = "\(scope), inactive. \(exact). The provider marked this quota inactive."
        return HomeReadingLine(primary: "\(scope) · Inactive", secondary: reported, tertiary: nil, tone: .neutral,
                               accessibilityLabel: help, toolTip: help)
    }

    private static func earnedCell(_ account: UsageOverviewAccount, now: Date, calendar: Calendar) -> HomeMeterCell {
        let facts = earnedFacts(account, now: now, calendar: calendar)
        if let reason = facts.unavailableReason {
            var line = message(reason, help: facts.help)
            line.isQuiet = !facts.isSupported
            return .message(line)
        }
        let primary = facts.countText ?? "Unknown"
        // `Last known` on the value already marks it old; the third line gives only the read time, so it fits the column.
        return .meters([HomeReadingLine(primary: primary, secondary: facts.expiryText, tertiary: facts.staleReadTime.map { "Last read \($0)" },
                                        tone: .neutral, accessibilityLabel: facts.help, toolTip: facts.help)])
    }

    private struct EarnedFacts {
        var countText: String?
        var expiryText: String?
        var expiryLabel: String?
        var expiryExact: String?
        var unavailableReason: String?
        var staleReadTime: String?
        var isSupported = true
        var help: String
    }

    private static func earnedFacts(_ account: UsageOverviewAccount, now: Date, calendar: Calendar) -> EarnedFacts {
        let basis = readingBasis(account, now: now)
        let credits = account.snapshot?.credits.filter { $0.unit == .resets } ?? []
        // A provider gap is permanent, so it reads the same in every reading state.
        if credits.isEmpty, account.profile.provider == .claude {
            return EarnedFacts(unavailableReason: "Not supported", isSupported: false,
                               help: "Claude accounts do not report earned resets.")
        }
        switch basis {
        case .authentication:
            return EarnedFacts(unavailableReason: "Unavailable", help: "Sign-in required. Choose Reconnect… to read earned resets.")
        case .unavailable:
            return EarnedFacts(unavailableReason: "Unavailable", help: "The provider did not return earned resets.")
        case .absent, .historical, .current:
            break
        }
        if credits.isEmpty {
            if basis == .absent, (account.snapshot?.windows ?? []).isEmpty {
                return EarnedFacts(unavailableReason: "Unavailable", help: noReadingHelp)
            }
            return EarnedFacts(unavailableReason: "Unknown", help: "No earned reset count was reported. Unknown is not zero.")
        }
        guard let aggregate = credits.first(where: { $0.id == "quota_reset_credits" }),
              let amount = aggregate.amount, amount >= 0,
              let observed = aggregate.asOf, observed <= now else {
            return EarnedFacts(unavailableReason: "Unknown", help: "An earned reset count and a trustworthy observation time are required.")
        }
        let reportedGrants = credits.filter { credit in
            guard credit.id != "quota_reset_credits", credit.status?.lowercased() == "available",
                  let date = credit.asOf, date <= now else { return false }
            return true
        }
        let passedExpiry = reportedGrants.compactMap(\.expiresAt).filter { $0 > observed && $0 <= now }.min()
        let stale = now.timeIntervalSince(observed) >= 300 || aggregate.status?.lowercased() == "stale" || passedExpiry != nil
        let grants = reportedGrants.filter { credit in
            stale || credit.asOf.map { now.timeIntervalSince($0) < 300 } == true
        }
        let earliest = passedExpiry ?? grants.compactMap(\.expiresAt).filter { $0 > now }.min()
        let count = wholeNumber(amount)
        let countText = stale ? "Last known \(count)" : "\(count) available"
        let expiryLabel: String?
        let expiryText: String?
        let expiryExact: String?
        if amount > 0, let earliest {
            expiryLabel = "Next expiry"
            expiryText = compactExpiry(earliest, label: passedExpiry != nil ? "Expired" : "Next expires", now: now, calendar: calendar)
            expiryExact = InterfaceFormatting.exactDate(earliest) + (passedExpiry != nil ? " (expired)" : "")
        } else if amount > 0, !grants.isEmpty, amount == Decimal(grants.count),
                  grants.allSatisfy({ $0.doesNotExpire }) {
            expiryLabel = "Expiry"
            expiryText = "No expiry"
            expiryExact = "The provider reported no expiry for all counted available grants."
        } else if amount == 0 {
            expiryLabel = nil
            expiryText = nil
            expiryExact = nil
        } else {
            expiryLabel = "Expiry"
            expiryText = "Expiry unavailable"
            expiryExact = "The expiry of the available earned resets is unknown."
        }
        var help = "Earned resets: \(countText). Observed \(InterfaceFormatting.exactDate(observed))"
        if let expiryExact { help += ". \(expiryLabel ?? "Expiry") \(expiryExact)" }
        if stale { help += ". Stale" }
        if passedExpiry != nil { help += ". An earned reset expired after this reading. Refresh to check current availability." }
        help += ". Earned reset expiry is separate from usage window resets."
        return EarnedFacts(countText: countText, expiryText: expiryText, expiryLabel: expiryLabel,
                           expiryExact: expiryExact,
                           staleReadTime: stale ? timeText(observed) : nil, help: help)
    }

    private static func detailRows(_ account: UsageOverviewAccount, now: Date, calendar: Calendar) -> [HomeDetailContent.Row] {
        let basis = readingBasis(account, now: now)
        let windows = account.snapshot?.windows ?? []
        var rows: [HomeDetailContent.Row] = windows.map { window in
            let scope = scopeLabel(window)
            let value = detailValue(window, basis: basis)
            let detail = detailSchedule(window, now: now, basis: basis)
            let tone: HomeReadingTone
            if basis == .current, window.isActive != false, let remaining = remainingPercent(window) {
                tone = Self.tone(for: remaining)
            } else {
                tone = .neutral
            }
            return HomeDetailContent.Row(label: scope, value: value, detail: detail, tone: tone,
                                         toolTip: "\(scope). \(value). \(detail ?? "")")
        }
        let status = accountStatus(account, basis: basis, now: now)
        if windows.isEmpty {
            let value = status ?? "Unavailable"
            rows.append(HomeDetailContent.Row(label: "Usage", value: value, detail: nil, tone: .neutral,
                                              toolTip: "No quota windows were reported. \(value). Unknown is not zero."))
        } else if let status {
            rows.append(HomeDetailContent.Row(label: "Status", value: status, detail: nil, tone: .neutral,
                                              toolTip: status))
        }
        let earned = earnedFacts(account, now: now, calendar: calendar)
        if !earned.isSupported {
            return rows
        }
        if let reason = earned.unavailableReason {
            rows.append(HomeDetailContent.Row(label: "Earned resets", value: reason, detail: nil, tone: .neutral, toolTip: earned.help))
        } else {
            rows.append(HomeDetailContent.Row(label: "Earned resets", value: earned.countText ?? "Unknown",
                                              detail: earned.staleReadTime.map { "Stale · last read \($0)" }, tone: .neutral,
                                              toolTip: earned.help))
            if let label = earned.expiryLabel {
                rows.append(HomeDetailContent.Row(label: label, value: earned.expiryExact ?? earned.expiryText ?? "Expiry unavailable",
                                                  detail: nil, tone: .neutral, toolTip: earned.help))
            }
        }
        return rows
    }

    private static func detailValue(_ window: UsageWindow, basis: ReadingBasis) -> String {
        if window.isActive == false { return "Inactive" }
        switch basis {
        case .unavailable: return "Unavailable"
        case .absent: return "Unknown"
        case .historical, .authentication:
            if let remaining = remainingPercent(window) { return "Last known \(percentText(remaining)) left" }
            return "Unknown"
        case .current:
            guard let remaining = remainingPercent(window) else { return "Unknown" }
            return remainingText(remaining)
        }
    }

    private static func detailSchedule(_ window: UsageWindow, now: Date, basis: ReadingBasis) -> String? {
        if window.isActive == false {
            return window.resetsAt.map { "Reported reset \(InterfaceFormatting.exactDate($0))" } ?? unknownResetText
        }
        guard let date = window.resetsAt else { return basis == .current && window.hasNoPendingReset ? noPendingResetText : unknownResetText }
        switch basis {
        case .historical, .authentication:
            return "Last reported reset \(InterfaceFormatting.exactDate(date))"
        case .unavailable, .absent:
            return InterfaceFormatting.exactDate(date)
        case .current:
            if date <= now { return "Reset due \(InterfaceFormatting.exactDate(date))" }
            return "Resets \(InterfaceFormatting.exactDate(date))"
        }
    }

    private static func heading(_ account: UsageOverviewAccount) -> String {
        var parts = ["\(account.profile.provider.title) \(account.shortIdentity)"]
        let email = InterfaceFormatting.accountEmail(account.profile)
        if email != "Email unavailable" {
            parts.append(email)
        } else {
            parts.append("Email unavailable")
            if account.identity != account.shortIdentity { parts.append(account.identity) }
        }
        if let plan = planName(account) { parts.append(plan) }
        return parts.joined(separator: " · ")
    }

    private static func planName(_ account: UsageOverviewAccount) -> String? {
        let plan = account.snapshot?.planName?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let plan, !plan.isEmpty else { return nil }
        return plan
    }

    private static func accountStatus(_ account: UsageOverviewAccount, basis: ReadingBasis, now: Date) -> String? {
        switch basis {
        case .authentication: return "Sign-in required"
        case .unavailable: return "Unavailable"
        case .absent: return absentStatus(account)
        case .historical:
            // A passed model reset makes the row historical, but the general windows can still decide usability.
            if case .exhausted(let usableAt) = AccountUsability(snapshot: account.snapshot, now: now) {
                return "\(staleText(account, now: now)) · \(usableText(usableAt, now: now))"
            }
            return staleText(account, now: now)
        case .current:
            let active = account.snapshot?.currentWindows ?? []
            if case .exhausted(let usableAt) = AccountUsability(snapshot: account.snapshot, now: now) {
                return usableText(usableAt, now: now)
            }
            if active.contains(where: { remainingPercent($0) == nil }) { return "Some usage unknown" }
            if active.isEmpty { return "Inactive" }
            return nil
        }
    }

    /// No reading at all is `Unavailable`; retained windows without a trustworthy time are `Observation time unknown`.
    private static func absentStatus(_ account: UsageOverviewAccount) -> String {
        (account.snapshot?.windows ?? []).isEmpty ? "Unavailable" : "Observation time unknown"
    }

    static let noReadingHelp = "No usage reading yet. Choose Refresh All to read usage."

    private static func updatedParts(_ account: UsageOverviewAccount, now: Date, basis: ReadingBasis) -> (primary: String, secondary: String?) {
        let observed = account.snapshot?.fetchedAt.flatMap { $0 <= now ? $0 : nil }
        switch basis {
        case .authentication:
            return ("Not refreshed", nil)
        case .absent:
            if (account.snapshot?.windows ?? []).isEmpty { return observed.map { (timeText($0), nil) } ?? ("Unavailable", nil) }
            return observed.map { (timeText($0), nil) } ?? ("No reading", nil)
        case .unavailable:
            return observed.map { (timeText($0), "Not refreshed") } ?? ("Not refreshed", nil)
        case .historical:
            return observed.map { (timeText($0), "Stale") } ?? ("No reading", "Stale")
        case .current:
            return observed.map { (timeText($0), nil) } ?? ("No reading", nil)
        }
    }

    private static func updatedSentence(_ account: UsageOverviewAccount, now: Date) -> String {
        guard let date = account.snapshot?.fetchedAt, date <= now else { return "Observation time unknown" }
        let prefix = readingBasis(account, now: now) == .current ? "Updated" : "Last read"
        return "\(prefix) \(InterfaceFormatting.exactDate(date))"
    }

    /// Vocabulary state for an old reading: "Stale · last read 11:09".
    private static func staleText(_ account: UsageOverviewAccount, now: Date) -> String {
        guard let date = account.snapshot?.fetchedAt, date <= now else { return "Stale" }
        return "Stale · last read \(timeText(date))"
    }

    private static func updatedToolTip(_ account: UsageOverviewAccount, now: Date) -> String {
        guard let date = account.snapshot?.fetchedAt else { return "No observation time was reported." }
        if date > now { return "The observation time is in the future, so it is not shown as current." }
        return "Observed \(InterfaceFormatting.exactDate(date))."
    }

    private static func message(_ primary: String, help: String) -> HomeReadingLine {
        HomeReadingLine(primary: primary, secondary: nil, tertiary: nil, tone: .neutral,
                        accessibilityLabel: help, toolTip: help)
    }

    private static func sharedDurationTitle(_ windows: [UsageWindow]) -> String? {
        let labels = Set(windows.map { durationLabel(forSessionHeading: $0) })
        guard labels.count == 1, let label = labels.first else { return nil }
        return label
    }

    private static func durationLabel(forSessionHeading window: UsageWindow) -> String {
        if let minutes = window.windowDurationMinutes { return durationLabel(minutes) }
        let title = scopeLabel(window)
        return title == "5-hour" ? "5-hour" : title
    }

    /// The part of the scope that tells a calendar event apart in a narrow day column: the model or meter
    /// name for a scoped window, otherwise the whole scope.
    static func calendarScope(_ window: UsageWindow) -> String {
        if let scoped = window.modelScope { return scoped.name }
        if let named = window.namedMeter, !window.isOrdinaryCodexMeter { return named.prefix }
        return scopeLabel(window)
    }

    private static func baseName(_ base: String, duration: Int?) -> String {
        if let duration { return durationLabel(duration) }
        if base == "5 hours" || base == "5-hour" { return "5-hour" }
        if base == "7 days" || base == "Weekly" { return "Weekly" }
        if let hours = hourCount(in: base) { return "\(hours)-hour" }
        if let days = dayCount(in: base) { return days == 7 ? "Weekly" : "\(days)-day" }
        return base
    }

    private static func hourCount(in title: String) -> Int? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(" hours") else { return nil }
        return Int(trimmed.dropLast(" hours".count))
    }

    private static func dayCount(in title: String) -> Int? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasSuffix(" days") else { return nil }
        return Int(trimmed.dropLast(" days".count))
    }

    private static func remainingPercent(_ window: UsageWindow) -> Double? {
        guard let used = window.utilizationPercent, used.isFinite else { return nil }
        let remaining = 100 - used
        guard remaining.isFinite else { return nil }
        return remaining
    }

    /// Short reset phrase for table cells: "Resets today 13:43". The exact date stays in the tooltip.
    private static func resetText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let when = scheduleText(date, now: now, calendar: calendar)
        return date > now ? "Resets \(when)" : "Reset passed \(when)"
    }

    /// "today 13:43" within today, "Wed 13:43" within six days, otherwise "Oct 21 13:43".
    static func scheduleText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = timeText(date)
        if calendar.isDate(date, inSameDayAs: now) { return "today \(time)" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? .max
        if abs(days) < 7 { return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(time)" }
        let month = date.formatted(.dateTime.month(.abbreviated))
        let day = calendar.component(.day, from: date)
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return "\(month) \(day) \(time)"
        }
        return "\(month) \(day), \(calendar.component(.year, from: date))"
    }

    private static func compactExpiry(_ date: Date, label: String, now: Date, calendar: Calendar) -> String {
        let month = date.formatted(.dateTime.month(.abbreviated))
        let day = calendar.component(.day, from: date)
        if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            return "\(label) \(month) \(day)"
        }
        return "\(label) \(month) \(day), \(calendar.component(.year, from: date))"
    }

    private static func timeText(_ date: Date) -> String {
        date.formatted(.dateTime.hour().minute())
    }

    private static func exactReset(_ date: Date?) -> String {
        date.map { "Resets \(InterfaceFormatting.exactDate($0))" } ?? unknownResetText
    }

    private static func wholeNumber(_ value: Decimal) -> String {
        var source = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &source, 0, .plain)
        let number = NSDecimalNumber(decimal: value)
        if rounded == value { return "\(NSDecimalNumber(decimal: rounded).intValue)" }
        return number.stringValue
    }
}
