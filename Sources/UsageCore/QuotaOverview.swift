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
        if Self.modelScope(in: title) != nil { return .other }
        if Self.namedMeter(in: title) != nil, !isOrdinaryCodexMeter { return .other }
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
        let base = Self.modelScope(in: title)?.base ?? Self.namedMeter(in: title)?.suffix ?? title
        return Self.durationMinutes(named: base)
    }

    /// The model or meter name of a weekly window other than the account's general one, such as `Fable 5`.
    public var weeklyScopeName: String? {
        guard role == .other, durationMinutes == 10_080 else { return nil }
        return Self.modelScope(in: title)?.name ?? Self.namedMeter(in: title)?.prefix
    }

    /// Measured zero use with no reset time: nothing is used, so no reset is pending. A missing time with any
    /// other value stays `Reset time unknown`.
    public var hasNoPendingReset: Bool {
        isActive != false && resetsAt == nil && utilizationPercent == 0
    }

    private var isOrdinaryCodexMeter: Bool { id == "codex_primary" || id == "codex_secondary" }

    private static func modelScope(in title: String) -> (base: String, name: String)? {
        guard let open = title.lastIndex(of: "("), let close = title.lastIndex(of: ")"), open < close else { return nil }
        let name = title[title.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        let base = title[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !base.isEmpty else { return nil }
        return (base, name)
    }

    private static func namedMeter(in title: String) -> (prefix: String, suffix: String)? {
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
        guard state == .available, let fetchedAt, fetchedAt <= now, now.timeIntervalSince(fetchedAt) < 300 else { return false }
        return !currentWindows.contains { $0.resetsAt.map { $0 <= now } == true }
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
        func measured(_ window: UsageWindow) -> Double? {
            guard window.isActive != false, let used = window.utilizationPercent, used.isFinite else { return nil }
            return used
        }
        var weeklyUsed: [(id: UUID, window: UsageWindow, used: Double)] = []
        var weeklyUnknown: [UUID] = []
        for account in members {
            let snapshot = account.snapshot.flatMap { $0.isCurrent(at: now) ? $0 : nil }
            if let window = snapshot?.windows.first(where: { $0.role == .weekly }), let used = measured(window) {
                weeklyUsed.append((account.id, window, used))
            } else {
                weeklyUnknown.append(account.id)
            }
        }
        weekly = QuotaPool(provider: provider, scopeName: nil,
                           remainingPercent: weeklyUsed.isEmpty ? nil : weeklyUsed.reduce(0) { $0 + 100 - $1.used },
                           countedAccountIDs: weeklyUsed.map(\.id), unknownAccountIDs: weeklyUnknown)
        // A scoped pool covers only accounts whose reading, current or not, has that window.
        var scopeNames: [String] = []
        for account in members {
            for name in (account.snapshot?.windows ?? []).compactMap(\.weeklyScopeName) where !scopeNames.contains(name) {
                scopeNames.append(name)
            }
        }
        scopedWeekly = scopeNames.map { name in
            var counted: [UUID] = []
            var unknown: [UUID] = []
            var remaining = 0.0
            for account in members {
                guard let window = account.snapshot?.windows.first(where: { $0.weeklyScopeName == name }) else { continue }
                if account.snapshot?.isCurrent(at: now) == true, let used = measured(window) {
                    counted.append(account.id)
                    remaining += 100 - used
                } else {
                    unknown.append(account.id)
                }
            }
            return QuotaPool(provider: provider, scopeName: name, remainingPercent: counted.isEmpty ? nil : remaining,
                             countedAccountIDs: counted, unknownAccountIDs: unknown)
        }
        // A reset with nothing used returns nothing, so it is not the next reset of the total.
        let returning = weeklyUsed.compactMap { entry -> (id: UUID, resetsAt: Date, used: Double)? in
            guard entry.used > 0, let resetsAt = entry.window.resetsAt, resetsAt > now else { return nil }
            return (entry.id, resetsAt, entry.used)
        }
        if let earliest = returning.map(\.resetsAt).min() {
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
    /// windows, or nil when one of them has no reset time.
    case exhausted(usableAt: Date?)
    /// No current reading, no general window, or a general window without a measured value.
    case unknown

    public init(snapshot: AccountSnapshot?, now: Date) {
        guard let snapshot, snapshot.isCurrent(at: now) else { self = .unknown; return }
        let windows = snapshot.currentWindows.filter { $0.role == .session || $0.role == .weekly }
        let exhausted = windows.filter { $0.utilizationPercent.map { $0 >= 100 } == true }
        if !exhausted.isEmpty {
            let resets = exhausted.compactMap(\.resetsAt)
            self = .exhausted(usableAt: resets.count == exhausted.count ? resets.max() : nil)
            return
        }
        self = windows.isEmpty || windows.contains { $0.utilizationPercent?.isFinite != true } ? .unknown : .usable
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
