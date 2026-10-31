import Foundation

/// What a usage window limits: the account's general 5-hour window, its general weekly window, or anything else
/// (a model-scoped limit, a named meter, or another duration).
public enum UsageWindowRole: Equatable, Sendable {
    case session
    case weekly
    case other
}

extension UsageWindow {
    /// A reported duration decides first; the provider's window identifiers and names decide when none was reported.
    /// Model-scoped and named meters are never the general window.
    public var role: UsageWindowRole {
        if modelScope != nil { return .other }
        if namedMeter != nil, !isOrdinaryCodexMeter { return .other }
        // Claude reports a scoped weekly limit without its model as `limit_<n>_weekly_scoped` titled `7 days`;
        // it limits part of the account, so it is never the general weekly window.
        if id.hasSuffix("_weekly_scoped") { return .other }
        if let minutes = windowDurationMinutes {
            if minutes == 300 { return .session }
            if minutes == 10_080 { return .weekly }
            return .other
        }
        switch id {
        case "five_hour": return .session
        case "seven_day": return .weekly
        default: break
        }
        switch Self.durationMinutes(named: title) {
        case 300: return .session
        case 10_080: return .weekly
        default: return .other
        }
    }

    /// The reported duration, else the duration the provider's identifier or name states. Nil when neither does.
    public var durationMinutes: Int? {
        if let windowDurationMinutes, windowDurationMinutes > 0 { return windowDurationMinutes }
        if id == "five_hour" { return 300 }
        if id == "seven_day" || id.hasPrefix("seven_day_") { return 10_080 }
        let base = modelScope?.base ?? namedMeter?.suffix ?? title
        return Self.durationMinutes(named: base)
    }

    /// The model or meter name of a weekly window other than the account's general one, such as `Fable 5`.
    public var weeklyScopeName: String? {
        guard role == .other, durationMinutes == 10_080 else { return nil }
        return modelScope?.name ?? namedMeter?.prefix
    }

    /// Measured zero use with no reset time: nothing is used, so no reset is pending. A missing time with any
    /// other value stays `Reset time unknown`.
    public var hasNoPendingReset: Bool {
        isActive != false && resetsAt == nil && utilizationPercent == 0
    }

    /// Codex's own 5-hour and weekly meters, which keep a `Codex:` prefix when several meters are reported.
    public var isOrdinaryCodexMeter: Bool { id == "codex_primary" || id == "codex_secondary" }

    /// The window name and model of a model-scoped title: `7 days (Fable 5)` is (`7 days`, `Fable 5`).
    public var modelScope: (base: String, name: String)? {
        guard let open = title.lastIndex(of: "("), let close = title.lastIndex(of: ")"), open < close else { return nil }
        let name = title[title.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        let base = title[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !base.isEmpty else { return nil }
        return (base, name)
    }

    /// The meter name and window of a named meter title: `Spark: 7 days` is (`Spark`, `7 days`).
    public var namedMeter: (prefix: String, suffix: String)? {
        guard let colon = title.firstIndex(of: ":") else { return nil }
        let prefix = title[..<colon].trimmingCharacters(in: .whitespacesAndNewlines)
        let suffix = title[title.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prefix.isEmpty, !suffix.isEmpty else { return nil }
        return (prefix, suffix)
    }

    private static func durationMinutes(named name: String) -> Int? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "5-hour" { return 300 }
        if trimmed == "Weekly" { return 10_080 }
        if trimmed.hasSuffix(" hours"), let hours = Int(trimmed.dropLast(" hours".count)), hours > 0 { return hours * 60 }
        if trimmed.hasSuffix(" days"), let days = Int(trimmed.dropLast(" days".count)), days > 0 { return days * 1_440 }
        return nil
    }
}

extension AccountSnapshot {
    /// A reading that may stand for now: available, observed under five minutes ago and not in the future, with no
    /// current window past its reset. Stale, failed, sign-in-required, and unread accounts are never current.
    public func isCurrent(at now: Date) -> Bool {
        isFresh(at: now) && !currentWindows.contains { $0.resetsAt.map { $0 <= now } == true }
    }

    /// Available and observed under five minutes ago, not in the future. Window resets are not checked, so a caller
    /// can judge each window by its own reset. `.stale` is never fresh: a failed refresh keeps the previous
    /// observation time and marks the reading stale, so the state cannot show that the values were confirmed.
    func isFresh(at now: Date) -> Bool {
        guard state == .available, let fetchedAt else { return false }
        return Self.isObservationCurrent(fetchedAt, now: now)
    }

    public static let freshnessLimit: TimeInterval = 300

    public static func isObservationCurrent(_ observedAt: Date, now: Date) -> Bool {
        observedAt <= now && now.timeIntervalSince(observedAt) < freshnessLimit
    }
}

/// Remaining quota summed over one provider's accounts for one weekly window. Only accounts with a current,
/// measured reading count; every other account that the pool covers is listed as unknown. With no counted
/// account the total is unknown, never 0%.
public struct QuotaPool: Equatable, Sendable {
    public let provider: Provider
    /// Nil for the general weekly window, otherwise the model or meter name.
    public let scopeName: String?
    public let remainingPercent: Double?
    public let countedAccountIDs: [UUID]
    public let unknownAccountIDs: [UUID]
    /// One hundred percent per counted account.
    public var capacityPercent: Double { Double(countedAccountIDs.count) * 100 }
}

/// The earliest weekly reset among counted accounts that returns quota, and the remaining percentage it adds.
public struct QuotaReset: Equatable, Sendable {
    public let resetsAt: Date
    public let gainPercent: Double
    public let accountIDs: [UUID]
}

public enum NextQuotaReset: Equatable, Sendable {
    case reset(QuotaReset)
    /// Every counted account has measured zero use, so no reset returns quota.
    case nonePending
    /// No account is counted, or used quota has no reported reset time.
    case unknown
}

/// Weekly totals and the next reset for one provider. Claude and Codex are never combined.
public struct ProviderQuotaOverview: Equatable, Sendable {
    public let provider: Provider
    public let accountCount: Int
    public let weekly: QuotaPool
    /// Model-scoped and named weekly windows, in the order they first appear in saved account order.
    public let scopedWeekly: [QuotaPool]
    public let nextReset: NextQuotaReset

    public init(provider: Provider, accounts: [UsageOverviewAccount], now: Date) {
        let members = accounts.filter { $0.profile.provider == provider }
        self.provider = provider
        accountCount = members.count
        /// The used percentage of one window when it stands for now: a fresh reading, the window active and measured,
        /// and its own reset not passed. Another window's passed reset does not make this value outdated.
        func currentUsed(_ window: UsageWindow?, in account: UsageOverviewAccount) -> Double? {
            guard let window, account.snapshot?.isFresh(at: now) == true, window.isActive != false,
                  window.resetsAt.map({ $0 <= now }) != true,
                  let used = window.utilizationPercent, used.isFinite else { return nil }
            return used
        }
        var weeklyUsed: [(id: UUID, window: UsageWindow, used: Double)] = []
        var weeklyUnknown: [UUID] = []
        for account in members {
            let window = account.snapshot?.windows.first { $0.isActive != false && $0.role == .weekly }
            if let window, let used = currentUsed(window, in: account) {
                weeklyUsed.append((account.id, window, used))
            } else if window == nil, account.snapshot?.isFresh(at: now) == true {
                // A fresh reading with no active weekly window reports none: outside the total, not unknown.
                continue
            } else {
                weeklyUnknown.append(account.id)
            }
        }
        weekly = QuotaPool(provider: provider, scopeName: nil,
                           remainingPercent: weeklyUsed.isEmpty ? nil : weeklyUsed.reduce(0) { $0 + 100 - $1.used },
                           countedAccountIDs: weeklyUsed.map(\.id), unknownAccountIDs: weeklyUnknown)
        // A scoped pool covers accounts whose latest reading, current or not, reports that window active. An account
        // that never reported it, or reported it inactive, is outside the pool rather than unknown.
        func activeScopedWindow(_ account: UsageOverviewAccount, named name: String) -> UsageWindow? {
            account.snapshot?.windows.first { $0.isActive != false && $0.weeklyScopeName == name }
        }
        var scopeNames: [String] = []
        for account in members {
            let names = (account.snapshot?.windows ?? []).filter { $0.isActive != false }.compactMap(\.weeklyScopeName)
            for name in names where !scopeNames.contains(name) {
                scopeNames.append(name)
            }
        }
        scopedWeekly = scopeNames.map { name in
            var counted: [UUID] = []
            var unknown: [UUID] = []
            var remaining = 0.0
            for account in members {
                guard let window = activeScopedWindow(account, named: name) else { continue }
                if let used = currentUsed(window, in: account) {
                    counted.append(account.id)
                    remaining += 100 - used
                } else {
                    unknown.append(account.id)
                }
            }
            return QuotaPool(provider: provider, scopeName: name, remainingPercent: counted.isEmpty ? nil : remaining,
                             countedAccountIDs: counted, unknownAccountIDs: unknown)
        }
        // Used quota without a future reset time could reset before every known reset, so the next reset is unknown.
        let missingReset = weeklyUsed.contains { $0.used > 0 && $0.window.resetsAt.map { $0 <= now } != false }
        // A reset with nothing used returns nothing, so it is not the next reset of the total.
        let returning = weeklyUsed.compactMap { entry -> (id: UUID, resetsAt: Date, used: Double)? in
            guard entry.used > 0, let resetsAt = entry.window.resetsAt, resetsAt > now else { return nil }
            return (entry.id, resetsAt, entry.used)
        }
        if missingReset {
            nextReset = .unknown
        } else if let earliest = returning.map(\.resetsAt).min() {
            let resetting = returning.filter { $0.resetsAt == earliest }
            nextReset = .reset(QuotaReset(resetsAt: earliest, gainPercent: resetting.reduce(0) { $0 + $1.used },
                                          accountIDs: resetting.map(\.id)))
        } else if !weeklyUsed.isEmpty, weeklyUsed.allSatisfy({ $0.used == 0 }) {
            nextReset = .nonePending
        } else {
            nextReset = .unknown
        }
    }
}

/// Whether an account can take requests now, from its current reading. Only the general 5-hour and weekly
/// windows decide; a model-scoped or named limit restricts that model alone, so it never makes the account
/// exhausted or unknown.
public enum AccountUsability: Equatable, Sendable {
    case usable
    /// A current general window is fully used. The date is the latest reset among the fully used general
    /// windows, or nil when one of them has no reset time or another general window is unmeasured, since that
    /// window may hold the account longer.
    case exhausted(usableAt: Date?)
    /// No current reading, no general window, or a general window without a measured value.
    case unknown

    /// Freshness comes from the reading's state and age; only the general windows' resets can make it outdated,
    /// so a passed model reset leaves the account's general usability current.
    public init(snapshot: AccountSnapshot?, now: Date) {
        guard let snapshot, snapshot.isFresh(at: now) else { self = .unknown; return }
        let windows = snapshot.currentWindows.filter { $0.role == .session || $0.role == .weekly }
        guard !windows.contains(where: { $0.resetsAt.map { $0 <= now } == true }) else { self = .unknown; return }
        let unmeasured = windows.contains { $0.utilizationPercent?.isFinite != true }
        let exhausted = windows.filter { $0.utilizationPercent.map { $0 >= 100 } == true }
        if !exhausted.isEmpty {
            let resets = exhausted.compactMap(\.resetsAt)
            self = .exhausted(usableAt: unmeasured || resets.count != exhausted.count ? nil : resets.max())
            return
        }
        self = windows.isEmpty || unmeasured ? .unknown : .usable
    }
}

/// Use compared with the elapsed share of the window. Within five points either way is on pace.
public struct QuotaPace: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        /// More used than the elapsed share: the quota runs out before the reset at this rate.
        case ahead
        case onPace
        case under
    }

    public let usedPercent: Double
    public let elapsedPercent: Double

    /// Nil when the window is inactive, unmeasured, has no future reset, has no known length, or reports a reset
    /// further away than its length.
    public init?(window: UsageWindow, now: Date) {
        guard window.isActive != false, let used = window.utilizationPercent, used.isFinite,
              let resetsAt = window.resetsAt, resetsAt > now,
              let minutes = window.durationMinutes else { return nil }
        let length = TimeInterval(minutes) * 60
        let untilReset = resetsAt.timeIntervalSince(now)
        guard untilReset <= length else { return nil }
        usedPercent = used
        elapsedPercent = (length - untilReset) / length * 100
    }

    public var verdict: Verdict {
        let difference = usedPercent - elapsedPercent
        if difference > 5 { return .ahead }
        if difference < -5 { return .under }
        return .onPace
    }
}

/// Home's account table order. Ties and accounts without a current reading keep saved order, so a refresh with
/// unchanged readings never moves a row.
public enum AccountSortOrder: String, CaseIterable, Sendable {
    case saved
    /// Highest current remaining quota first, using each account's limiting window.
    case mostRemaining
    /// Usable now first, then exhausted accounts by the time they become usable.
    case soonestUsable

    public func sorted(_ accounts: [UsageOverviewAccount], now: Date) -> [UsageOverviewAccount] {
        guard self != .saved else { return accounts }
        let keyed = accounts.enumerated().map { offset, account -> (offset: Int, account: UsageOverviewAccount, key: (Int, Double)) in
            (offset, account, key(account, now: now))
        }
        return keyed.sorted { lhs, rhs in
            if lhs.key.0 != rhs.key.0 { return lhs.key.0 < rhs.key.0 }
            if lhs.key.1 != rhs.key.1 { return lhs.key.1 < rhs.key.1 }
            return lhs.offset < rhs.offset
        }.map(\.account)
    }

    /// A rank group, then an ascending value within it.
    private func key(_ account: UsageOverviewAccount, now: Date) -> (Int, Double) {
        switch self {
        case .saved:
            return (0, 0)
        case .mostRemaining:
            guard case let .available(remaining, _, _) = account.summary else { return (1, 0) }
            return (0, -remaining)
        case .soonestUsable:
            switch AccountUsability(snapshot: account.snapshot, now: now) {
            case .usable: return (0, 0)
            case .exhausted(let date?): return (1, date.timeIntervalSince(now))
            case .exhausted(nil): return (2, 0)
            case .unknown: return (3, 0)
            }
        }
    }
}
