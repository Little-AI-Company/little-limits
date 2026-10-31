import Foundation

public enum UsageWindowRole: Equatable, Sendable {
    case session
    case weekly
    case other
}

extension UsageWindow {
    public var role: UsageWindowRole {
        if modelScope != nil { return .other }
        if namedMeter != nil, !isOrdinaryCodexMeter { return .other }
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

    public var durationMinutes: Int? {
        if let windowDurationMinutes, windowDurationMinutes > 0 { return windowDurationMinutes }
        if id == "five_hour" { return 300 }
        if id == "seven_day" || id.hasPrefix("seven_day_") { return 10_080 }
        let base = modelScope?.base ?? namedMeter?.suffix ?? title
        return Self.durationMinutes(named: base)
    }

    public var weeklyScopeName: String? {
        guard role == .other, durationMinutes == 10_080 else { return nil }
        return modelScope?.name ?? namedMeter?.prefix
    }

    public var hasNoPendingReset: Bool {
        isActive != false && resetsAt == nil && utilizationPercent == 0
    }

    public var isOrdinaryCodexMeter: Bool { id == "codex_primary" || id == "codex_secondary" }

    public var modelScope: (base: String, name: String)? {
        guard let open = title.lastIndex(of: "("), let close = title.lastIndex(of: ")"), open < close else { return nil }
        let name = title[title.index(after: open)..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        let base = title[..<open].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !base.isEmpty else { return nil }
        return (base, name)
    }

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
    public func isCurrent(at now: Date) -> Bool {
        isFresh(at: now) && !currentWindows.contains { $0.resetsAt.map { $0 <= now } == true }
    }

    func isFresh(at now: Date) -> Bool {
        guard state == .available, let fetchedAt else { return false }
        return Self.isObservationCurrent(fetchedAt, now: now)
    }

    public static let freshnessLimit: TimeInterval = 300

    public static func isObservationCurrent(_ observedAt: Date, now: Date) -> Bool {
        observedAt <= now && now.timeIntervalSince(observedAt) < freshnessLimit
    }
}

public struct QuotaPool: Equatable, Sendable {
    public let provider: Provider
    public let scopeName: String?
    public let remainingPercent: Double?
    public let countedAccountIDs: [UUID]
    public let unknownAccountIDs: [UUID]
    public var capacityPercent: Double { Double(countedAccountIDs.count) * 100 }
}

public struct QuotaReset: Equatable, Sendable {
    public let resetsAt: Date
    public let gainPercent: Double
    public let accountIDs: [UUID]
}

public enum NextQuotaReset: Equatable, Sendable {
    case reset(QuotaReset)
    case nonePending
    case unknown
}

public struct ProviderQuotaOverview: Equatable, Sendable {
    public let provider: Provider
    public let accountCount: Int
    public let weekly: QuotaPool
    public let scopedWeekly: [QuotaPool]
    public let nextReset: NextQuotaReset

    public init(provider: Provider, accounts: [UsageOverviewAccount], now: Date) {
        let members = accounts.filter { $0.profile.provider == provider }
        self.provider = provider
        accountCount = members.count
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
                continue
            } else {
                weeklyUnknown.append(account.id)
            }
        }
        weekly = QuotaPool(provider: provider, scopeName: nil,
                           remainingPercent: weeklyUsed.isEmpty ? nil : weeklyUsed.reduce(0) { $0 + 100 - $1.used },
                           countedAccountIDs: weeklyUsed.map(\.id), unknownAccountIDs: weeklyUnknown)
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
        let missingReset = weeklyUsed.contains { $0.used > 0 && $0.window.resetsAt.map { $0 <= now } != false }
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

public enum AccountUsability: Equatable, Sendable {
    case usable
    case exhausted(usableAt: Date?)
    case unknown

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

public struct QuotaPace: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        case ahead
        case onPace
        case under
    }

    public let usedPercent: Double
    public let elapsedPercent: Double

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

public enum AccountSortOrder: String, CaseIterable, Sendable {
    case saved
    case mostRemaining
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
