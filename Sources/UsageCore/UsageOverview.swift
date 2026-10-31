import Foundation

public struct UsageOverview: Equatable, Sendable {
    public let accounts: [UsageOverviewAccount]
    public let resetEvents: [UsageResetEvent]
    public let providers: [ProviderQuotaOverview]

    public init(profiles: [AccountProfile], snapshots: [UUID: AccountSnapshot], now: Date = Date()) {
        let identities = Self.identities(for: profiles)
        var accounts: [UsageOverviewAccount] = []
        var events: [UsageResetEvent] = []
        accounts.reserveCapacity(profiles.count)
        for profile in profiles {
            let stored = snapshots[profile.id]
            let snapshot = stored?.profileID == profile.id ? stored : nil
            let names = identities[profile.id] ?? (identity: profile.label, shortIdentity: profile.label)
            let account = UsageOverviewAccount(profile: profile, snapshot: snapshot,
                                               summary: AccountQuotaSummary(snapshot: snapshot, accountID: profile.id, now: now),
                                               identity: names.identity, shortIdentity: names.shortIdentity)
            accounts.append(account)
            guard let snapshot, snapshot.isCurrent(at: now) else { continue }
            for window in snapshot.windows {
                guard let event = Self.resetEvent(account: account, window: window, now: now) else { continue }
                events.append(event)
            }
        }
        self.accounts = accounts
        self.providers = Provider.allCases.filter { provider in accounts.contains { $0.profile.provider == provider } }
            .map { ProviderQuotaOverview(provider: $0, accounts: accounts, now: now) }
        self.resetEvents = events.enumerated().sorted { lhs, rhs in
            if lhs.element.resetsAt != rhs.element.resetsAt { return lhs.element.resetsAt < rhs.element.resetsAt }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private static func resetEvent(account: UsageOverviewAccount, window: UsageWindow, now: Date) -> UsageResetEvent? {
        guard window.isActive != false else { return nil }
        guard let used = window.utilizationPercent, used.isFinite else { return nil }
        guard let resetsAt = window.resetsAt, resetsAt > now else { return nil }
        return UsageResetEvent(id: "\(account.id.uuidString)/\(window.id)", accountID: account.id, provider: account.profile.provider,
                               identity: account.identity, shortIdentity: account.shortIdentity, window: window,
                               remainingPercent: 100 - used, resetsAt: resetsAt)
    }

    private static func identities(for profiles: [AccountProfile]) -> [UUID: (identity: String, shortIdentity: String)] {
        struct Draft {
            let id: UUID
            let provider: Provider
            let identity: String
            let proposed: String
        }
        let drafts = profiles.map { profile in
            let email = profile.providerEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
            let verified = email?.isEmpty == false ? email : nil
            let localPart = verified.flatMap { email -> String? in
                guard let separator = email.firstIndex(of: "@") else { return nil }
                let part = String(email[..<separator])
                return part.isEmpty ? nil : part
            }
            let savedLabel = profile.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let identity = verified ?? (savedLabel.isEmpty ? "\(profile.provider.title) Account" : savedLabel)
            let proposed = localPart ?? (savedLabel.isEmpty && verified == nil ? "Account" : identity)
            return Draft(id: profile.id, provider: profile.provider, identity: identity, proposed: proposed)
        }
        var proposedCounts: [Provider: [String: Int]] = [:]
        var identityCounts: [Provider: [String: Int]] = [:]
        for draft in drafts {
            var proposed = proposedCounts[draft.provider] ?? [:]
            proposed[draft.proposed, default: 0] += 1
            proposedCounts[draft.provider] = proposed
            var identities = identityCounts[draft.provider] ?? [:]
            identities[draft.identity, default: 0] += 1
            identityCounts[draft.provider] = identities
        }
        var collisionGroups: [Provider: [String: [Draft]]] = [:]
        for draft in drafts {
            guard (proposedCounts[draft.provider]?[draft.proposed] ?? 0) > 1,
                  (identityCounts[draft.provider]?[draft.identity] ?? 0) > 1 else { continue }
            var providerGroups = collisionGroups[draft.provider] ?? [:]
            providerGroups[draft.identity, default: []].append(draft)
            collisionGroups[draft.provider] = providerGroups
        }
        var ordinalByID: [UUID: Int] = [:]
        for providerGroups in collisionGroups.values {
            for members in providerGroups.values {
                let ordered = members.sorted { $0.id.uuidString < $1.id.uuidString }
                for (offset, member) in ordered.enumerated() {
                    ordinalByID[member.id] = offset + 1
                }
            }
        }
        struct Named { let draft: Draft; let label: String }
        let named: [Named] = drafts.map { draft in
            let proposedCount = proposedCounts[draft.provider]?[draft.proposed] ?? 0
            let identityCount = identityCounts[draft.provider]?[draft.identity] ?? 0
            let label: String
            if proposedCount <= 1 {
                label = draft.proposed
            } else if identityCount <= 1 {
                label = draft.identity
            } else {
                let stem = draft.proposed.trimmingCharacters(in: .whitespacesAndNewlines)
                let base = stem.isEmpty ? "Account" : draft.proposed
                label = "\(base) \(ordinalByID[draft.id] ?? 1)"
            }
            return Named(draft: draft, label: label)
        }
        var shortByID: [UUID: String] = [:]
        for provider in Set(drafts.map(\.provider)) {
            var used = Set<String>()
            let members = named.filter { $0.draft.provider == provider }.sorted { $0.draft.id.uuidString < $1.draft.id.uuidString }
            for member in members {
                var label = member.label
                if used.contains(label) {
                    var ordinal = 2
                    while used.contains("\(member.label) \(ordinal)") { ordinal += 1 }
                    label = "\(member.label) \(ordinal)"
                }
                used.insert(label)
                shortByID[member.draft.id] = label
            }
        }
        var result: [UUID: (identity: String, shortIdentity: String)] = [:]
        for draft in drafts {
            result[draft.id] = (draft.identity, shortByID[draft.id] ?? draft.identity)
        }
        return result
    }
}

public struct UsageOverviewAccount: Identifiable, Equatable, Sendable {
    public let profile: AccountProfile
    public let snapshot: AccountSnapshot?
    public let summary: AccountQuotaSummary
    public let identity: String
    public let shortIdentity: String
    public var id: UUID { profile.id }

    public init(profile: AccountProfile, snapshot: AccountSnapshot?, summary: AccountQuotaSummary, identity: String, shortIdentity: String) {
        self.profile = profile
        self.snapshot = snapshot
        self.summary = summary
        self.identity = identity
        self.shortIdentity = shortIdentity
    }
}

public struct UsageResetEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public let accountID: UUID
    public let provider: Provider
    public let identity: String
    public let shortIdentity: String
    public let window: UsageWindow
    public let remainingPercent: Double
    public let resetsAt: Date

    public init(id: String, accountID: UUID, provider: Provider, identity: String, shortIdentity: String,
                window: UsageWindow, remainingPercent: Double, resetsAt: Date) {
        self.id = id
        self.accountID = accountID
        self.provider = provider
        self.identity = identity
        self.shortIdentity = shortIdentity
        self.window = window
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }
}

public enum UsageCalendarMode: String, CaseIterable, Sendable {
    case twoWeeks
    case month
}

public struct UsageCalendarPeriod: Equatable, Sendable {
    public let days: [Date]
    public let start: Date
    public let end: Date

    public init(mode: UsageCalendarMode, containing date: Date, calendar: Calendar = .current) {
        var calendar = calendar
        calendar.firstWeekday = 2
        let day = calendar.startOfDay(for: date)
        let gridStart: Date
        let gridEnd: Date
        switch mode {
        case .twoWeeks:
            gridStart = Self.weekStart(containing: day, calendar: calendar)
            gridEnd = Self.addingDays(14, to: gridStart, calendar: calendar)
        case .month:
            let first = Self.monthStart(containing: day, calendar: calendar)
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: first) ?? Self.addingDays(28, to: first, calendar: calendar)
            let last = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: nextMonth)) ?? first
            gridStart = Self.weekStart(containing: first, calendar: calendar)
            gridEnd = Self.addingDays(7, to: Self.weekStart(containing: last, calendar: calendar), calendar: calendar)
        }
        let days = Self.days(from: gridStart, until: gridEnd, calendar: calendar)
        let resolved = days.isEmpty ? [gridStart] : days
        self.days = resolved
        self.start = resolved[0]
        self.end = calendar.date(byAdding: .day, value: 1, to: resolved[resolved.count - 1]) ?? gridEnd
    }

    private static func addingDays(_ count: Int, to date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: count, to: start) ?? start
    }

    private static func weekStart(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        if let interval = calendar.dateInterval(of: .weekOfYear, for: day) {
            let start = calendar.startOfDay(for: interval.start)
            if calendar.component(.weekday, from: start) == 2,
               let next = calendar.date(byAdding: .day, value: 7, to: start), start <= day, day < next {
                return start
            }
        }
        let weekday = calendar.component(.weekday, from: day)
        let daysSinceMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysSinceMonday, to: day) ?? day
    }

    private static func monthStart(containing date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        if let interval = calendar.dateInterval(of: .month, for: day) {
            return calendar.startOfDay(for: interval.start)
        }
        let parts = calendar.dateComponents([.year, .month], from: day)
        return calendar.date(from: parts).map { calendar.startOfDay(for: $0) } ?? day
    }

    private static func days(from start: Date, until end: Date, calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let limit = calendar.startOfDay(for: end)
        while cursor < limit {
            days.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            let startOfNext = calendar.startOfDay(for: next)
            if startOfNext <= cursor { break }
            cursor = startOfNext
        }
        return days
    }
}
