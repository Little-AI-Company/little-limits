import AppKit
import GRDB
import OSLog
import UsageCore
import UsageHistory
import UsageHistoryStore

struct BurnItem: Codable, Equatable {
    var text: String
    var provider: Provider?
}

@MainActor
final class QuotaAlerts {
    struct Preferences: Equatable {
        var nudgeThreshold: Int?
        var warnsRunDry = false
        var burnList: [BurnItem] = []
    }

    struct Drain: Equatable {
        let percentPerHour: Double
        let historyHours: Double
    }

    enum NudgeKind: String, Codable {
        case first
        case final
    }

    struct Nudge: Equatable {
        let account: UsageOverviewAccount
        let windowKey: String
        let kind: NudgeKind
        let percentLeft: Double
        let leftover: Double
        let resetsAt: Date
    }

    struct RunDry: Equatable {
        let account: UsageOverviewAccount
        let episodeKey: String
        let percentLeft: Double
        let windowName: String
        let resetsAt: Date?
        let runsOutAt: Date?
        let alternative: UsageOverviewAccount
        let alternativeLeft: Double
        let alternativeResetsSooner: Bool
    }

    struct Ledger: Codable, Equatable {
        struct WindowRecord: Codable, Equatable {
            var kinds: [NudgeKind]
            let resetsAt: Date
        }

        var windows: [String: WindowRecord] = [:]
        var sentAt: [Date] = []
        var snoozedUntil: [String: Date] = [:]
        var skippedWindows: [String: Date] = [:]
        var runDryEpisodes: [String: Double] = [:]
    }

    static let thresholds = [15, 25, 40]
    static let finalLeftover: Double = 15
    static let firstNudgeHorizon: TimeInterval = 36 * 3_600
    static let finalActiveHours: Double = 8
    static let minimumHistoryHours: Double = 12
    static let linearShareExcess: Double = 30
    static let nudgesPerWeek = 4
    static let snoozeDuration: TimeInterval = 3 * 3_600
    static let quietStartHour = 22
    static let quietEndHour = 8
    static let runDryHorizon: TimeInterval = 24 * 3_600
    static let runDrySessionPercent: Double = 10
    static let runDryAlternativePercent: Double = 30
    private static let thresholdKey = "NudgeThreshold"
    private static let runDryKey = "RunDryAlerts"
    private static let burnListKey = "BurnList"
    private static let ledgerKey = "QuotaAlertLedger"
    nonisolated private static let logger = Logger(subsystem: "com.parkerrex.ai-usage-stats", category: "Alerts")

    private let model: ApplicationModel
    private let notifications: LocalNotifications
    private let storesChanges: Bool
    private var ledger: Ledger
    private var isEvaluating = false
    private(set) var preferences: Preferences

    init(model: ApplicationModel, notifications: LocalNotifications) {
        self.model = model
        self.notifications = notifications
        storesChanges = !model.isDemo
        let defaults = UserDefaults.standard
        var preferences = Preferences()
        let threshold = defaults.integer(forKey: Self.thresholdKey)
        preferences.nudgeThreshold = Self.thresholds.contains(threshold) ? threshold : nil
        preferences.warnsRunDry = defaults.bool(forKey: Self.runDryKey)
        if let data = defaults.data(forKey: Self.burnListKey), let list = try? JSONDecoder().decode([BurnItem].self, from: data) {
            preferences.burnList = list
        }
        self.preferences = preferences
        ledger = model.isDemo ? Ledger() : defaults.data(forKey: Self.ledgerKey)
            .flatMap { try? JSONDecoder().decode(Ledger.self, from: $0) } ?? Ledger()
    }

    func update(_ preferences: Preferences) {
        let enabling = (preferences.nudgeThreshold != nil && self.preferences.nudgeThreshold == nil)
            || (preferences.warnsRunDry && !self.preferences.warnsRunDry)
        self.preferences = preferences
        if storesChanges {
            let defaults = UserDefaults.standard
            defaults.set(preferences.nudgeThreshold ?? 0, forKey: Self.thresholdKey)
            defaults.set(preferences.warnsRunDry, forKey: Self.runDryKey)
            defaults.set(try? JSONEncoder().encode(preferences.burnList), forKey: Self.burnListKey)
        }
        if enabling { Task { _ = await notifications.requestPermission() } }
    }

    func burnItem(for provider: Provider) -> BurnItem? {
        preferences.burnList.first { $0.provider == nil || $0.provider == provider }
    }

    func evaluate(now: Date = Date(), calendar: Calendar = .current) {
        guard !isEvaluating, preferences.nudgeThreshold != nil || preferences.warnsRunDry else { return }
        isEvaluating = true
        let overview = UsageOverview(profiles: model.profiles, snapshots: model.snapshots, now: now)
        let database = model.historyDatabase
        Task {
            let drains = await Self.drains(overview: overview, database: database, now: now)
            deliver(overview: overview, drains: drains, now: now, calendar: calendar)
            isEvaluating = false
        }
    }

    private func deliver(overview: UsageOverview, drains: [UUID: Drain], now: Date, calendar: Calendar) {
        prune(overview: overview, now: now)
        if let threshold = preferences.nudgeThreshold, !Self.isQuiet(now, calendar: calendar),
           ledger.sentAt.filter({ now.timeIntervalSince($0) < 7 * 86_400 }).count < Self.nudgesPerWeek {
            let nudges = Self.nudges(overview: overview, drains: drains, threshold: Double(threshold), ledger: ledger,
                                     now: now, calendar: calendar)
            if !nudges.isEmpty {
                for nudge in nudges {
                    var record = ledger.windows[nudge.windowKey] ?? Ledger.WindowRecord(kinds: [], resetsAt: nudge.resetsAt)
                    record.kinds.append(nudge.kind)
                    ledger.windows[nudge.windowKey] = record
                }
                ledger.sentAt.append(now)
                postNudges(nudges, now: now, calendar: calendar)
            }
        }
        if preferences.warnsRunDry {
            for alert in Self.runDryAlerts(overview: overview, drains: drains, ledger: ledger, now: now) {
                ledger.runDryEpisodes[alert.episodeKey] = alert.percentLeft
                postRunDry(alert, now: now, calendar: calendar)
            }
        }
        saveLedger()
    }

    func handle(action: String, userInfo: [String: String]) {
        let windows = userInfo["windows"]?.split(separator: ",").map(String.init) ?? []
        let accounts = userInfo["accounts"]?.split(separator: ",").map(String.init) ?? []
        switch action {
        case LocalNotifications.copyBurnItemAction:
            guard let text = userInfo["burnItem"] else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        case LocalNotifications.snoozeAction:
            let until = Date().addingTimeInterval(Self.snoozeDuration)
            for account in accounts { ledger.snoozedUntil[account] = until }
            for window in windows { _ = ledger.windows[window]?.kinds.popLast() }
            saveLedger()
        case LocalNotifications.notThisWeekAction:
            for window in windows { ledger.skippedWindows[window] = ledger.windows[window]?.resetsAt ?? Date().addingTimeInterval(7 * 86_400) }
            saveLedger()
        default:
            break
        }
    }

    private func saveLedger() {
        guard storesChanges else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(ledger), forKey: Self.ledgerKey)
    }

    private func prune(overview: UsageOverview, now: Date) {
        ledger.windows = ledger.windows.filter { $0.value.resetsAt > now }
        ledger.sentAt = ledger.sentAt.filter { now.timeIntervalSince($0) < 7 * 86_400 }
        ledger.snoozedUntil = ledger.snoozedUntil.filter { $0.value > now }
        ledger.skippedWindows = ledger.skippedWindows.filter { $0.value > now }
        var current: [String: Double] = [:]
        for account in overview.accounts {
            guard let snapshot = account.snapshot, snapshot.isCurrent(at: now) else { continue }
            for window in snapshot.currentWindows {
                guard let used = window.utilizationPercent else { continue }
                current[Self.windowKey(account: account, window: window)] = 100 - used
            }
        }
        ledger.runDryEpisodes = ledger.runDryEpisodes.filter { key, alerted in
            guard let left = current[key] else { return Self.resetDate(fromKey: key).map { $0 > now } ?? false }
            return left <= alerted + 1
        }
    }

    private func postNudges(_ nudges: [Nudge], now: Date, calendar: Calendar) {
        let burnItem = burnItem(for: nudges[0].account.profile.provider)
        let title: String
        var lines: [String]
        if nudges.count == 1, let nudge = nudges.first {
            title = "\(Self.name(nudge.account)): ~\(Self.rounded(nudge.leftover)) of the week resets unused \(Self.when(nudge.resetsAt, now: now, calendar: calendar))"
            lines = ["\(RemainingPercentText.format(nudge.percentLeft)) left, resets \(LimitsDigestText.moment(nudge.resetsAt, now: now, calendar: calendar)). "
                     + "At your pace about \(Self.rounded(nudge.leftover)) would go unused."]
        } else {
            title = "\(nudges.count) accounts have weekly quota that would reset unused"
            lines = nudges.map { nudge in
                "\(Self.name(nudge.account)): \(RemainingPercentText.format(nudge.percentLeft)) left, ~\(Self.rounded(nudge.leftover)) unused at your pace, "
                    + "resets \(LimitsDigestText.moment(nudge.resetsAt, now: now, calendar: calendar))"
            }
        }
        if let burnItem { lines.append("Burn list: \"\(burnItem.text)\"") }
        var userInfo = ["windows": nudges.map(\.windowKey).joined(separator: ","),
                        "accounts": nudges.map(\.account.id.uuidString).joined(separator: ",")]
        if let burnItem { userInfo["burnItem"] = burnItem.text }
        Self.logger.notice("Nudge for \(nudges.count) account window(s)")
        Task {
            await notifications.post(identifier: "nudge-\(nudges.map(\.windowKey).joined(separator: "+"))-\(nudges[0].kind.rawValue)",
                                     title: title, body: lines.joined(separator: "\n"),
                                     category: burnItem == nil ? LocalNotifications.nudgeCategory : LocalNotifications.nudgeWithBurnItemCategory,
                                     userInfo: userInfo)
        }
    }

    private func postRunDry(_ alert: RunDry, now: Date, calendar: Calendar) {
        let title = alert.runsOutAt.map { "\(Self.name(alert.account)) runs out around \(LimitsDigestText.moment($0, now: now, calendar: calendar))" }
            ?? "\(Self.name(alert.account)): \(alert.windowName) \(RemainingPercentText.format(alert.percentLeft)) left"
        var body = "\(alert.windowName.prefix(1).uppercased() + alert.windowName.dropFirst()) \(RemainingPercentText.format(alert.percentLeft)) left"
        if let resetsAt = alert.resetsAt { body += ", resets \(LimitsDigestText.moment(resetsAt, now: now, calendar: calendar))" }
        body += ". \(Self.name(alert.alternative)) has \(RemainingPercentText.format(alert.alternativeLeft)) left"
            + (alert.alternativeResetsSooner ? " and resets sooner" : "")
            + ": switch to \(alert.alternative.shortIdentity) today."
        Self.logger.notice("Run-dry alert for one account window")
        Task { await notifications.post(identifier: "run-dry-\(alert.episodeKey)", title: title, body: body) }
    }

    static func nudges(overview: UsageOverview, drains: [UUID: Drain], threshold: Double, ledger: Ledger,
                       now: Date, calendar: Calendar) -> [Nudge] {
        overview.accounts.compactMap { account -> Nudge? in
            guard let snapshot = account.snapshot, snapshot.isCurrent(at: now),
                  AccountUsability(snapshot: snapshot, now: now) == .usable,
                  ledger.snoozedUntil[account.id.uuidString].map({ $0 <= now }) ?? true,
                  let window = snapshot.currentWindows.first(where: { $0.role == .weekly }),
                  let used = window.utilizationPercent, let resetsAt = window.resetsAt, resetsAt > now else { return nil }
            let sessionLeft = snapshot.currentWindows.first { $0.role == .session }?.utilizationPercent.map { 100 - $0 } ?? 100
            guard sessionLeft >= UseNowRule.minimumPercentLeft else { return nil }
            let key = windowKey(account: account, window: window)
            guard ledger.skippedWindows[key] == nil else { return nil }
            let sent = ledger.windows[key]?.kinds ?? []
            let left = 100 - used
            let untilReset = resetsAt.timeIntervalSince(now)
            let drain = drains[account.id]
            let hasHistory = (drain?.historyHours ?? 0) >= minimumHistoryHours
            let leftover = QuotaLevel.projectedLeftover(window: window, left: left, untilReset: untilReset, now: now,
                                                        drainPercentPerHour: hasHistory ? drain?.percentPerHour : nil)
            let finalDue: Bool
            if isQuiet(resetsAt, calendar: calendar), let quietStart = quietStart(before: resetsAt, calendar: calendar) {
                finalDue = now >= quietStart.addingTimeInterval(-5 * 3_600)
            } else {
                finalDue = activeHours(from: now, to: resetsAt, calendar: calendar) <= finalActiveHours
            }
            if finalDue, !sent.contains(.final), leftover >= finalLeftover {
                return Nudge(account: account, windowKey: key, kind: .final, percentLeft: left, leftover: leftover, resetsAt: resetsAt)
            }
            guard sent.isEmpty, untilReset <= firstNudgeHorizon else { return nil }
            let qualifies = hasHistory ? leftover >= threshold
                : left - untilReset / 3_600 / 168 * 100 >= linearShareExcess && leftover >= threshold
            guard qualifies else { return nil }
            return Nudge(account: account, windowKey: key, kind: .first, percentLeft: left, leftover: leftover, resetsAt: resetsAt)
        }
    }

    static func runDryAlerts(overview: UsageOverview, drains: [UUID: Drain], ledger: Ledger, now: Date) -> [RunDry] {
        overview.accounts.compactMap { account -> RunDry? in
            guard let snapshot = account.snapshot, snapshot.isCurrent(at: now),
                  AccountUsability(snapshot: snapshot, now: now) == .usable else { return nil }
            let windows = snapshot.currentWindows
            var candidate: (window: UsageWindow, left: Double, runsOutAt: Date?)?
            if let weekly = windows.first(where: { $0.role == .weekly }), let used = weekly.utilizationPercent,
               let resetsAt = weekly.resetsAt, resetsAt > now, used < 100 {
                let left = 100 - used
                let drain = drains[account.id].flatMap { $0.historyHours >= minimumHistoryHours ? $0.percentPerHour : nil }
                    ?? averagePace(weekly, now: now)
                if let drain, drain > 0 {
                    let runsOutAt = now.addingTimeInterval(left / drain * 3_600)
                    if runsOutAt < resetsAt, runsOutAt.timeIntervalSince(now) <= runDryHorizon {
                        candidate = (weekly, left, runsOutAt)
                    }
                }
            }
            if candidate == nil, let session = windows.first(where: { $0.role == .session }), let used = session.utilizationPercent,
               used < 100, 100 - used <= runDrySessionPercent, session.resetsAt.map({ $0.timeIntervalSince(now) > QuotaLevel.sessionGrace }) ?? true {
                candidate = (session, 100 - used, nil)
            }
            guard let candidate else { return nil }
            let key = windowKey(account: account, window: candidate.window)
            guard ledger.runDryEpisodes[key] == nil else { return nil }
            let others = overview.accounts.filter { $0.profile.provider == account.profile.provider && $0.id != account.id }
            let alternatives = others.compactMap { other -> (account: UsageOverviewAccount, left: Double, resetsAt: Date?)? in
                guard let snapshot = other.snapshot, snapshot.isCurrent(at: now),
                      AccountUsability(snapshot: snapshot, now: now) == .usable,
                      let weekly = snapshot.currentWindows.first(where: { $0.role == .weekly }),
                      let used = weekly.utilizationPercent, 100 - used >= runDryAlternativePercent else { return nil }
                let sessionLeft = snapshot.currentWindows.first { $0.role == .session }?.utilizationPercent.map { 100 - $0 } ?? 100
                guard sessionLeft >= runDrySessionPercent else { return nil }
                return (other, 100 - used, weekly.resetsAt)
            }
            guard let best = alternatives.max(by: { $0.left < $1.left }) else { return nil }
            let candidateReset = candidate.window.resetsAt
            let sooner = best.resetsAt.flatMap { alternative in candidateReset.map { alternative < $0 } } ?? false
            return RunDry(account: account, episodeKey: key, percentLeft: candidate.left,
                          windowName: candidate.window.role == .session ? "5-hour" : "weekly", resetsAt: candidateReset,
                          runsOutAt: candidate.runsOutAt, alternative: best.account, alternativeLeft: best.left,
                          alternativeResetsSooner: sooner)
        }
    }

    private static func averagePace(_ window: UsageWindow, now: Date) -> Double? {
        guard let pace = QuotaPace(window: window, now: now), let minutes = window.durationMinutes else { return nil }
        let elapsedHours = pace.elapsedPercent / 100 * Double(minutes) / 60
        return elapsedHours >= 1 ? pace.usedPercent / elapsedHours : nil
    }

    private static func drains(overview: UsageOverview, database: HistoryDatabase?, now: Date) async -> [UUID: Drain] {
        guard let database else { return [:] }
        let bound = now.addingTimeInterval(-QuotaForecast.drainLookback - 3_600)
        let readings: [QuotaReading]
        do {
            readings = try await Task.detached(priority: .utility) {
                try database.pool.read { try QuotaReading.filter(Column("observedAt") >= bound).fetchAll($0) }
            }.value
        } catch {
            logger.error("Could not read quota history for alerts: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
        var drains: [UUID: Drain] = [:]
        for account in overview.accounts {
            guard let window = account.snapshot?.currentWindows.first(where: { $0.role == .weekly }),
                  let used = window.utilizationPercent else { continue }
            let own = readings.filter { $0.accountID == account.id }
            let weekly = HomeForecastModel.generalWeeklyReadings(own, accounts: [account])
            let counted = [CountedQuota(accountID: account.id, remainingPercent: 100 - used, resetsAt: window.resetsAt)]
            guard let rate = QuotaForecast.drainRate(provider: HomeForecastModel.historyProvider(account.profile.provider),
                                                     history: weekly, counted: counted, now: now) else { continue }
            drains[account.id] = Drain(percentPerHour: rate.percentPerHour, historyHours: rate.lookback / 3_600)
        }
        return drains
    }

    static func windowKey(account: UsageOverviewAccount, window: UsageWindow) -> String {
        let reset = window.resetsAt.map { Int(($0.timeIntervalSince1970 / 600).rounded()) * 600 } ?? 0
        return "\(account.id.uuidString)|\(window.id)|\(reset)"
    }

    private static func resetDate(fromKey key: String) -> Date? {
        key.split(separator: "|").last.flatMap { Double($0) }.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
    }

    static func isQuiet(_ date: Date, calendar: Calendar) -> Bool {
        let hour = calendar.component(.hour, from: date)
        return hour >= quietStartHour || hour < quietEndHour
    }

    private static func quietStart(before date: Date, calendar: Calendar) -> Date? {
        let day = calendar.startOfDay(for: date)
        let sameDay = calendar.date(byAdding: .hour, value: quietStartHour, to: day)
        if let sameDay, sameDay <= date { return sameDay }
        return calendar.date(byAdding: .day, value: -1, to: sameDay ?? day)
    }

    static func activeHours(from start: Date, to end: Date, calendar: Calendar) -> Double {
        var cursor = start
        var active: TimeInterval = 0
        let step: TimeInterval = 300
        while cursor < end {
            let next = min(end, cursor.addingTimeInterval(step))
            if !isQuiet(cursor, calendar: calendar) { active += next.timeIntervalSince(cursor) }
            cursor = next
        }
        return active / 3_600
    }

    private static func name(_ account: UsageOverviewAccount) -> String {
        "\(account.profile.provider.title) \(account.shortIdentity)"
    }

    private static func rounded(_ percent: Double) -> String {
        "\(Int((percent / 5).rounded(.down) * 5))%"
    }

    private static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            return calendar.component(.hour, from: date) >= 18 ? "tonight" : "today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow"
        }
        return "by \(LimitsDigestText.moment(date, now: now, calendar: calendar))"
    }
}
