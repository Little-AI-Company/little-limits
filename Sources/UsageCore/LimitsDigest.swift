import Foundation

public struct LimitsDigest: Codable, Sendable, Equatable {
    public static let currentVersion = 1
    public static let outdatedAge: TimeInterval = 600

    public let version: Int
    public let asOf: Date
    public let timeZone: String
    public let accounts: [Account]
    public let useNow: [UseNowPick]

    public enum AccountState: String, Codable, Sendable {
        case current
        case stale
        case unknown
        case inactive
        case signInNeeded = "sign_in_needed"
        case failed
    }

    public enum WindowRole: String, Codable, Sendable {
        case session
        case weekly
        case other
    }

    public struct Window: Codable, Sendable, Equatable {
        public let kind: String
        public let role: WindowRole
        public let percentLeft: Double?
        public let lastKnownPercentLeft: Double?
        public let resetsAt: Date?
        public let resetsDisplay: String
        public let level: QuotaLevel?

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(role, forKey: .role)
            try container.encode(percentLeft, forKey: .percentLeft)
            try container.encode(lastKnownPercentLeft, forKey: .lastKnownPercentLeft)
            try container.encode(resetsAt, forKey: .resetsAt)
            try container.encode(resetsDisplay, forKey: .resetsDisplay)
            try container.encode(level, forKey: .level)
        }
    }

    public enum EarnedResetsStatus: String, Codable, Sendable {
        case supported
        case notSupported = "not_supported"
        case unknown
    }

    public struct EarnedResets: Codable, Sendable, Equatable {
        public let status: EarnedResetsStatus
        public let count: Int?
        public let nextExpiresAt: Date?
        public let observedAt: Date?

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(status, forKey: .status)
            try container.encode(count, forKey: .count)
            try container.encode(nextExpiresAt, forKey: .nextExpiresAt)
            try container.encode(observedAt, forKey: .observedAt)
        }
    }

    public enum CreditKind: String, Codable, Sendable {
        case purchased
        case monthlyGrant = "monthly_grant"
        case promotional
        case other
    }

    public struct APICredit: Codable, Sendable, Equatable {
        public let title: String
        public let kind: CreditKind
        public let amount: Decimal?
        public let currency: String?
        public let asOf: Date?
        public let expiresAt: Date?
        public let source: CreditSource
        public let status: String?
        public let experimental: Bool
    }

    public struct CurrencyAmount: Codable, Sendable, Equatable {
        public let currency: String
        public let amount: Decimal
    }

    public struct Account: Codable, Sendable, Equatable {
        public let label: String
        public let shortLabel: String
        public let provider: Provider
        public let plan: String?
        public let state: AccountState
        public let observedAt: Date?
        public let weeklyPercentLeft: Double?
        public let windows: [Window]
        public let earnedResets: EarnedResets
        public let apiCredits: [APICredit]
        public let apiUsable: [CurrencyAmount]

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(label, forKey: .label)
            try container.encode(shortLabel, forKey: .shortLabel)
            try container.encode(provider, forKey: .provider)
            try container.encode(plan, forKey: .plan)
            try container.encode(state, forKey: .state)
            try container.encode(observedAt, forKey: .observedAt)
            try container.encode(weeklyPercentLeft, forKey: .weeklyPercentLeft)
            try container.encode(windows, forKey: .windows)
            try container.encode(earnedResets, forKey: .earnedResets)
            try container.encode(apiCredits, forKey: .apiCredits)
            try container.encode(apiUsable, forKey: .apiUsable)
        }
    }

    public init(overview: UsageOverview, now: Date, calendar: Calendar) {
        version = Self.currentVersion
        asOf = now
        timeZone = calendar.timeZone.identifier
        accounts = overview.accounts.map { Self.account($0, now: now, calendar: calendar) }
        useNow = overview.providers.flatMap { provider in
            UseNowNeed.allCases.map { UseNowRule.pick(provider: provider.provider, accounts: overview.accounts, now: now, calendar: calendar, need: $0) }
        }
    }

    public func age(at now: Date) -> TimeInterval { max(0, now.timeIntervalSince(asOf)) }

    public func isOutdated(at now: Date) -> Bool { age(at: now) > Self.outdatedAge }

    public static var fileURL: URL { UsagePaths.applicationSupport.appendingPathComponent("limits-digest.json") }

    public func write(to url: URL = Self.fileURL) throws {
        try UsagePaths.writePrivate(encoded(), to: url)
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    public static func read(from url: URL = Self.fileURL) throws -> LimitsDigest {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(LimitsDigest.self, from: Data(contentsOf: url))
    }

    static func sanitizedLabel(_ label: String) -> String {
        let flattened = label.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) || CharacterSet.newlines.contains($0) ? " " : String($0) }
            .joined().replacingOccurrences(of: "|", with: "/").trimmingCharacters(in: .whitespaces)
        return flattened.count > 80 ? String(flattened.prefix(79)) + "…" : flattened
    }

    private static func state(_ snapshot: AccountSnapshot?, now: Date) -> AccountState {
        guard let snapshot else { return .unknown }
        switch snapshot.state {
        case .authenticationRequired: return .signInNeeded
        case .unavailable: return snapshot.windows.isEmpty ? .unknown : .failed
        case .stale: return .stale
        case .available:
            guard snapshot.fetchedAt != nil, !snapshot.windows.isEmpty else { return .unknown }
            guard snapshot.isCurrent(at: now) else { return .stale }
            return snapshot.currentWindows.isEmpty ? .inactive : .current
        }
    }

    private static func account(_ account: UsageOverviewAccount, now: Date, calendar: Calendar) -> Account {
        let snapshot = account.snapshot
        let state = state(snapshot, now: now)
        let current = state == .current
        let windows = (snapshot?.currentWindows ?? []).map { window -> Window in
            let left = window.utilizationPercent.map { 100 - $0 }
            return Window(kind: kind(window), role: role(window), percentLeft: current ? left : nil,
                          lastKnownPercentLeft: current ? nil : left, resetsAt: window.resetsAt,
                          resetsDisplay: resetsDisplay(window, now: now, calendar: calendar),
                          level: current ? QuotaLevel(window: window, now: now) : nil)
        }
        let credits = apiCredits(snapshot?.credits ?? [])
        return Account(label: sanitizedLabel(account.identity),
                       shortLabel: sanitizedLabel(account.shortIdentity),
                       provider: account.profile.provider, plan: snapshot?.planName.map(sanitizedLabel), state: state,
                       observedAt: snapshot?.fetchedAt,
                       weeklyPercentLeft: windows.first { $0.role == .weekly }?.percentLeft,
                       windows: windows, earnedResets: earnedResets(account, now: now),
                       apiCredits: credits, apiUsable: apiUsable(credits, now: now))
    }

    private static func role(_ window: UsageWindow) -> WindowRole {
        switch window.role {
        case .session: .session
        case .weekly: .weekly
        case .other: .other
        }
    }

    private static func kind(_ window: UsageWindow) -> String {
        switch window.role {
        case .session: return "5-hour"
        case .weekly: return "weekly"
        case .other:
            if let scope = window.weeklyScopeName { return "weekly · \(sanitizedLabel(scope))" }
            return sanitizedLabel(window.title)
        }
    }

    private static func resetsDisplay(_ window: UsageWindow, now: Date, calendar: Calendar) -> String {
        guard let resetsAt = window.resetsAt else {
            return window.hasNoPendingReset ? "no reset pending" : "reset time unknown"
        }
        guard resetsAt > now else { return "reset passed" }
        return LimitsDigestText.moment(resetsAt, now: now, calendar: calendar)
    }

    private static func earnedResets(_ account: UsageOverviewAccount, now: Date) -> EarnedResets {
        let credits = account.snapshot?.credits.filter { $0.unit == .resets } ?? []
        guard !credits.isEmpty else {
            return EarnedResets(status: account.profile.provider == .claude ? .notSupported : .unknown,
                                count: nil, nextExpiresAt: nil, observedAt: nil)
        }
        guard let summary = credits.first(where: { $0.id == "quota_reset_credits" }), let amount = summary.amount,
              amount >= 0 else {
            return EarnedResets(status: .unknown, count: nil, nextExpiresAt: nil, observedAt: nil)
        }
        let next = credits.filter { $0.id != "quota_reset_credits" && $0.status?.lowercased() == "available" }
            .compactMap(\.expiresAt).filter { $0 > now }.min()
        return EarnedResets(status: .supported, count: NSDecimalNumber(decimal: amount).intValue,
                            nextExpiresAt: next, observedAt: summary.asOf)
    }

    private static func apiCredits(_ credits: [CreditBalance]) -> [APICredit] {
        credits.compactMap { credit in
            guard credit.unit == .usd || credit.unit == .currency else { return nil }
            guard credit.amount != nil || credit.status != nil || credit.asOf != nil || credit.source == .manual else { return nil }
            let kind: CreditKind
            if credit.id.hasPrefix("api_balance") { kind = .purchased }
            else if credit.id.hasPrefix("monthly_grant") { kind = .monthlyGrant }
            else if credit.id.hasPrefix("console_grant") { kind = .promotional }
            else { kind = .other }
            return APICredit(title: sanitizedLabel(credit.title), kind: kind, amount: credit.amount,
                             currency: credit.unit == .usd ? "USD" : credit.currencyCode,
                             asOf: credit.asOf, expiresAt: credit.expiresAt, source: credit.source,
                             status: credit.status.map(sanitizedLabel), experimental: credit.source == .provider)
        }
    }

    private static func apiUsable(_ credits: [APICredit], now: Date) -> [CurrencyAmount] {
        var totals: [String: Decimal] = [:]
        var order: [String] = []
        for credit in credits where credit.kind != .other && credit.status != "Stale" {
            guard let amount = credit.amount, let currency = credit.currency,
                  credit.expiresAt.map({ $0 > now }) ?? true else { continue }
            if totals[currency] == nil { order.append(currency) }
            totals[currency, default: 0] += amount
        }
        return order.map { CurrencyAmount(currency: $0, amount: totals[$0] ?? 0) }
    }
}

public enum QuotaLevel: String, Codable, Sendable {
    case useSoon = "use_soon"
    case low
    case almostOut = "almost_out"
    case limitReached = "limit_reached"

    public static let almostOutThreshold: Double = 5
    public static let useSoonLeftover: Double = 25
    public static let useSoonHorizon: TimeInterval = 36 * 3_600
    public static let weeklyGrace: TimeInterval = 12 * 3_600
    public static let sessionGrace: TimeInterval = 30 * 60

    public init?(percentLeft: Double) {
        guard percentLeft.isFinite else { return nil }
        if percentLeft <= 0 { self = .limitReached }
        else if percentLeft <= Self.almostOutThreshold { self = .almostOut }
        else if percentLeft <= RemainingPercentText.lowRemainingThreshold { self = .low }
        else { return nil }
    }

    public init?(window: UsageWindow, now: Date, drainPercentPerHour: Double? = nil) {
        guard window.isActive != false, let used = window.utilizationPercent, used.isFinite else { return nil }
        let left = 100 - used
        if left <= 0 { self = .limitReached; return }
        let untilReset = window.resetsAt.map { $0.timeIntervalSince(now) }
        if window.role == .weekly, let untilReset, untilReset > 0, untilReset <= Self.useSoonHorizon,
           Self.projectedLeftover(window: window, left: left, untilReset: untilReset, now: now,
                                  drainPercentPerHour: drainPercentPerHour) >= Self.useSoonLeftover {
            self = .useSoon
            return
        }
        let grace = window.role == .session ? Self.sessionGrace : Self.weeklyGrace
        if let untilReset, untilReset > 0, untilReset <= grace { return nil }
        guard let level = QuotaLevel(percentLeft: left) else { return nil }
        self = level
    }

    public static func projectedLeftover(window: UsageWindow, left: Double, untilReset: TimeInterval, now: Date,
                                         drainPercentPerHour: Double?) -> Double {
        let hours = untilReset / 3_600
        if let drainPercentPerHour, drainPercentPerHour.isFinite, drainPercentPerHour >= 0 {
            return max(0, left - drainPercentPerHour * hours)
        }
        guard let pace = QuotaPace(window: window, now: now), let minutes = window.durationMinutes else { return left }
        let elapsedHours = pace.elapsedPercent / 100 * Double(minutes) / 60
        guard elapsedHours >= 1 else { return left }
        return max(0, left - pace.usedPercent / elapsedHours * hours)
    }

    public var word: String {
        switch self {
        case .useSoon: "Use soon"
        case .low: "Low"
        case .almostOut: "Almost out"
        case .limitReached: "Limit reached"
        }
    }
}
