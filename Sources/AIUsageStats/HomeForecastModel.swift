import Foundation
import UsageCore
import UsageHistory

/// The forecast range pop-up. History before Now covers the same length as the projection after it.
enum HomeForecastRange: Int, CaseIterable {
    case nextDay
    case nextWeek

    var title: String {
        switch self {
        case .nextDay: "Next 1 day"
        case .nextWeek: "Next 7 days"
        }
    }

    var horizon: ForecastHorizon {
        switch self {
        case .nextDay: .oneDay
        case .nextWeek: .sevenDays
        }
    }
}

/// One provider's pooled weekly chart: solid history runs, a dashed projection from Now, and a fixed 0 to capacity
/// scale.
struct HomeForecastChartModel: Equatable {
    var provider: Provider
    /// Each run is one unbroken line. The space between runs is a gap, never zero.
    var history: [[QuotaHistoryPoint]]
    var projection: [QuotaProjectionPoint]
    var now: Date
    var start: Date
    var end: Date
    var capacityPercent: Double
    var accessibilityLabel: String
}

/// One provider's forecast block: text lines in the totals grid, then the chart. With no recorded history the
/// block is a single plain notice instead.
struct HomeProviderForecast: Equatable {
    var provider: Provider
    var lines: [HomeTotalLine]
    var chart: HomeForecastChartModel?
    var notice: String?
}

enum HomeForecastModel {
    /// Pooled history is sampled on this grid. Polled readings are 300 seconds apart.
    static let historyStep: TimeInterval = 300

    /// Forecast blocks for each provider with an account, Claude first. Claude and Codex are never combined.
    /// `latestReadings` holds each account's latest reading of any age; it may be older than `readings` covers.
    static func providers(overview: UsageOverview, readings: [QuotaReading], latestReadings: [QuotaReading] = [],
                          range: HomeForecastRange, now: Date,
                          calendar: Calendar) -> [HomeProviderForecast] {
        overview.providers.filter { $0.accountCount > 0 }.map { provider in
            forecast(provider, overview: overview, readings: readings, latestReadings: latestReadings, range: range,
                     now: now, calendar: calendar)
        }
    }

    static func historyProvider(_ provider: Provider) -> HistoryProvider {
        switch provider {
        case .claude: .claude
        case .codex: .codex
        }
    }

    /// Readings of each account's general weekly window. A reading is classified with UsageCore's window rules,
    /// using the title of the same window in the account's latest reading, so a model-scoped or named weekly
    /// window never joins the pooled total.
    static func generalWeeklyReadings(_ readings: [QuotaReading], accounts: [UsageOverviewAccount]) -> [QuotaReading] {
        var titles: [UUID: [String: String]] = [:]
        for account in accounts {
            for window in account.snapshot?.windows ?? [] { titles[account.id, default: [:]][window.id] = window.title }
        }
        return readings.filter { reading in
            guard let accountTitles = titles[reading.accountID] else { return false }
            let window = UsageWindow(id: reading.windowID, title: accountTitles[reading.windowID] ?? "",
                                     utilizationPercent: reading.usedPercent, resetsAt: reading.resetsAt,
                                     windowDurationMinutes: reading.windowDurationMinutes)
            return window.role == .weekly
        }
    }

    /// The pooled total of `accounts` over time, sampled every `historyStep` back from `now` to `start`. A sample
    /// exists only when every account's history covers it; a run continues only while each account stays in the
    /// same unbroken segment. Any account's gap is therefore a gap in the pooled line.
    static func pooledHistory(_ segments: [QuotaHistorySegment], accounts: [UUID], from start: Date,
                              to now: Date) -> [[QuotaHistoryPoint]] {
        guard !accounts.isEmpty, now > start else { return [] }
        let byAccount = Dictionary(grouping: segments, by: \.accountID)
        let accountSegments = accounts.map { byAccount[$0] ?? [] }
        guard accountSegments.allSatisfy({ !$0.isEmpty }) else { return [] }
        let count = Int(now.timeIntervalSince(start) / historyStep)
        var runs: [[QuotaHistoryPoint]] = []
        var run: [QuotaHistoryPoint] = []
        var previousSegments: [Int]?
        for step in stride(from: count, through: 0, by: -1) {
            let date = now.addingTimeInterval(-Double(step) * historyStep)
            var total = 0.0
            var indices: [Int] = []
            for segments in accountSegments {
                guard let index = segments.firstIndex(where: { covers($0, date) }),
                      let value = value(of: segments[index], at: date) else { break }
                indices.append(index)
                total += value
            }
            guard indices.count == accountSegments.count else {
                if !run.isEmpty { runs.append(run) }
                run = []
                previousSegments = nil
                continue
            }
            if let previousSegments, previousSegments != indices, !run.isEmpty {
                runs.append(run)
                run = []
            }
            run.append(QuotaHistoryPoint(date: date, remainingPercent: total))
            previousSegments = indices
        }
        if !run.isEmpty { runs.append(run) }
        return runs
    }

    private static func covers(_ segment: QuotaHistorySegment, _ date: Date) -> Bool {
        guard let first = segment.points.first, let last = segment.points.last else { return false }
        return first.date <= date && date <= last.date
    }

    /// The segment's value at `date`, linear between points. At a date with two points, a change-only step, the later
    /// value wins.
    private static func value(of segment: QuotaHistorySegment, at date: Date) -> Double? {
        // Binary search for the first point after `date`; points are in date order.
        var low = 0
        var high = segment.points.count
        while low < high {
            let middle = (low + high) / 2
            if segment.points[middle].date > date { high = middle } else { low = middle + 1 }
        }
        let after = low
        guard after < segment.points.count else { return segment.points.last?.remainingPercent }
        guard after > 0 else { return nil }
        let earlier = segment.points[after - 1]
        let later = segment.points[after]
        let span = later.date.timeIntervalSince(earlier.date)
        guard span > 0 else { return later.remainingPercent }
        let share = date.timeIntervalSince(earlier.date) / span
        return earlier.remainingPercent + (later.remainingPercent - earlier.remainingPercent) * share
    }

    private static func forecast(_ provider: ProviderQuotaOverview, overview: UsageOverview, readings: [QuotaReading],
                                 latestReadings: [QuotaReading], range: HomeForecastRange, now: Date, calendar: Calendar) -> HomeProviderForecast {
        let members = overview.accounts.filter { $0.profile.provider == provider.provider }
        let memberIDs = Set(members.map(\.id))
        let own = readings.filter { $0.provider == historyProvider(provider.provider) && memberIDs.contains($0.accountID) }
        let ownLatest = latestReadings.filter {
            $0.provider == historyProvider(provider.provider) && memberIDs.contains($0.accountID)
        }
        guard !own.isEmpty || !ownLatest.isEmpty else {
            return HomeProviderForecast(provider: provider.provider, lines: [], chart: nil,
                                        notice: "\(provider.provider.title): \(noHistoryText)")
        }
        let weekly = generalWeeklyReadings(own, accounts: members)
        let counted = provider.weekly.countedAccountIDs.compactMap { id -> CountedQuota? in
            guard let window = members.first(where: { $0.id == id })?.snapshot?.windows
                .first(where: { $0.isActive != false && $0.role == .weekly }),
                  let used = window.utilizationPercent else { return nil }
            return CountedQuota(accountID: id, remainingPercent: 100 - used, resetsAt: window.resetsAt)
        }
        let result = QuotaForecast.forecast(QuotaForecastInput(provider: historyProvider(provider.provider), history: weekly,
                                                               counted: counted, now: now, horizon: range.horizon))
        let title = provider.provider.title
        var lines = [usageRateLine(result.drain, title: title, hasCounted: !counted.isEmpty, now: now),
                     zeroLine(result.projection, title: title, range: range, now: now, calendar: calendar)]
        let latest = Dictionary(grouping: own + ownLatest, by: \.accountID).mapValues { readings in
            readings.max { $0.observedAt < $1.observedAt }
        }
        for account in members {
            lines.append(updatedLine(account, latest: latest[account.id] ?? nil, now: now, calendar: calendar))
        }
        lines[0].provider = provider.provider

        let start = now.addingTimeInterval(-range.horizon.duration)
        // Every reading is kept: a change-only value recorded before the range holds until its reset or the next
        // reading, which can fall inside the range. Pooling samples only from `start`.
        let segments = QuotaForecast.historySegments(readings: weekly, now: now)
        let history = pooledHistory(segments, accounts: counted.map(\.accountID), from: start, to: now)
        var chart: HomeForecastChartModel?
        if !history.isEmpty || result.projection != nil {
            let capacity = Double(counted.count) * 100
            chart = HomeForecastChartModel(provider: provider.provider, history: history,
                                           projection: result.projection?.points ?? [], now: now, start: start,
                                           end: now.addingTimeInterval(range.horizon.duration),
                                           capacityPercent: capacity,
                                           accessibilityLabel: chartLabel(title: title, capacity: capacity, history: history,
                                                                          projection: result.projection, range: range,
                                                                          now: now, calendar: calendar))
        }
        return HomeProviderForecast(provider: provider.provider, lines: lines, chart: chart, notice: nil)
    }

    static let noHistoryText = "No quota history yet. The forecast appears after the app records readings over time."

    /// `About 7.7% per hour`. Unknown is never shown as 0.
    static func usageRateLine(_ drain: QuotaDrainRate?, title: String, hasCounted: Bool, now: Date) -> HomeTotalLine {
        guard let drain else {
            let detail = hasCounted ? "Needs two readings in the last 24 hours" : "No current weekly reading"
            return HomeTotalLine(label: "Usage rate", value: "Unknown", detail: detail,
                                 accessibilityLabel: "\(title) usage rate unknown, \(detail)",
                                 toolTip: "The usage rate is unknown. \(detail). Unknown is not zero.")
        }
        let value = "About \(HomeInterfaceFormatting.percentText(drain.percentPerHour)) per hour"
        let detail = drain.isShortLookback
            ? "From \(UsageFormatting.countdown(to: now.addingTimeInterval(drain.lookback), now: now)) of history"
            : "Last 24 hours"
        return HomeTotalLine(label: "Usage rate", value: value, detail: detail,
                             accessibilityLabel: "\(title) usage rate, \(value.lowercased()), \(detail.lowercased())",
                             toolTip: "Weekly quota used per hour by the counted accounts, summed, \(detail.lowercased()). "
                                 + "Idle time counts. Resets and accounts joining or leaving the total do not.")
    }

    /// `Weekly total reaches 0%` with `Fri 4:56 AM`, or `Not in the next 7 days`.
    static func zeroLine(_ projection: QuotaProjection?, title: String, range: HomeForecastRange, now: Date,
                         calendar: Calendar) -> HomeTotalLine {
        let label = "Weekly total reaches 0%"
        guard let projection else {
            return HomeTotalLine(label: label, value: "Unknown", detail: "",
                                 accessibilityLabel: "\(title) weekly total reaches 0 percent, unknown",
                                 toolTip: "Needs a known usage rate and at least one current weekly reading.")
        }
        guard let date = projection.reachesZeroAt else {
            let value = "Not in the \(range.title.lowercased())"
            return HomeTotalLine(label: label, value: value, detail: "",
                                 accessibilityLabel: "\(title) weekly total does not reach 0 percent in the \(range.title.lowercased())",
                                 toolTip: "At the current usage rate, with each counted account's reset, the weekly total stays above 0%.")
        }
        let value = HomeInterfaceFormatting.scheduleText(date, now: now, calendar: calendar)
        let detail = date <= now ? "Now" : "in \(UsageFormatting.countdown(to: date, now: now))"
        return HomeTotalLine(label: label, value: value, detail: detail,
                             accessibilityLabel: "\(title) weekly total reaches 0 percent \(value), \(detail)",
                             toolTip: "Projected from the usage rate and each counted account's reset: "
                                 + "\(InterfaceFormatting.exactDate(date)).")
    }

    /// The time of the account's latest recorded reading.
    static func updatedLine(_ account: UsageOverviewAccount, latest: QuotaReading?, now: Date,
                             calendar: Calendar) -> HomeTotalLine {
        let name = account.shortIdentity
        guard let latest else {
            return HomeTotalLine(label: "Updated", value: "No recorded reading", detail: name,
                                 accessibilityLabel: "\(account.profile.provider.title) \(name) has no recorded reading",
                                 toolTip: "No reading of \(name) is recorded yet.")
        }
        let value = HomeInterfaceFormatting.scheduleText(latest.observedAt, now: now, calendar: calendar)
        let changesOnly = latest.source.recordsOnlyChanges
        let detail = changesOnly ? "\(name), changes only" : name
        return HomeTotalLine(label: "Updated", value: value, detail: detail,
                             accessibilityLabel: "\(account.profile.provider.title) \(name) updated \(value)"
                                 + (changesOnly ? ", recorded only when quota changes" : ""),
                             toolTip: "Latest recorded reading: \(InterfaceFormatting.exactDate(latest.observedAt))."
                                 + (changesOnly ? " This source records a reading only when quota changes." : ""))
    }

    private static func chartLabel(title: String, capacity: Double, history: [[QuotaHistoryPoint]],
                                   projection: QuotaProjection?, range: HomeForecastRange, now: Date,
                                   calendar: Calendar) -> String {
        var parts = ["\(title) pooled weekly quota remaining, 0 to \(Int(capacity)) percent"]
        if let first = history.first?.first {
            parts.append("history from \(HomeInterfaceFormatting.scheduleText(first.date, now: now, calendar: calendar))"
                + (history.count > 1 ? " with \(history.count - 1) gap\(history.count == 2 ? "" : "s")" : ""))
        } else {
            parts.append("no history in this range")
        }
        if let projection, let start = projection.points.first, let end = projection.points.last {
            parts.append("\(RemainingPercentText.format(start.remainingPercent)) now, "
                + "projected \(RemainingPercentText.format(end.remainingPercent)) at the end of the \(range.title.lowercased())")
        }
        return parts.joined(separator: "; ")
    }
}
