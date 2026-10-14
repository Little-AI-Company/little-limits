import Foundation

public enum Provider: String, Codable, Sendable, CaseIterable {
    case claude
    case codex

    public var title: String { self == .claude ? "Claude" : "Codex" }
}

public enum AccountSource: String, Codable, Sendable {
    case claudeCLI
    case claudeOAuth
    case codexCLI
    case manual
    case demo
}

public struct AccountProfile: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let provider: Provider
    public var label: String
    public let source: AccountSource
    public let providerAccountID: String?
    public let providerEmail: String?
    public let sourcePath: String?

    public init(id: UUID = UUID(), provider: Provider, label: String, source: AccountSource,
                providerAccountID: String? = nil, providerEmail: String? = nil, sourcePath: String? = nil) {
        self.id = id
        self.provider = provider
        self.label = label
        self.source = source
        self.providerAccountID = providerAccountID
        self.providerEmail = providerEmail
        self.sourcePath = sourcePath
    }
}

public enum SnapshotState: String, Codable, Sendable {
    case available
    case unavailable
    case stale
    case authenticationRequired
}

public struct UsageWindow: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let utilizationPercent: Double?
    public let resetsAt: Date?
    public let isActive: Bool?
    public let windowDurationMinutes: Int?

    public init(id: String, title: String, utilizationPercent: Double?, resetsAt: Date?, isActive: Bool? = nil,
                windowDurationMinutes: Int? = nil) {
        self.id = id
        self.title = title
        self.utilizationPercent = utilizationPercent.flatMap { $0.isFinite ? min(100, max(0, $0)) : nil }
        self.resetsAt = resetsAt
        self.isActive = isActive
        self.windowDurationMinutes = windowDurationMinutes
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, utilizationPercent, resetsAt, isActive, windowDurationMinutes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try values.decode(String.self, forKey: .id),
                  title: try values.decode(String.self, forKey: .title),
                  utilizationPercent: try values.decodeIfPresent(Double.self, forKey: .utilizationPercent),
                  resetsAt: try values.decodeIfPresent(Date.self, forKey: .resetsAt),
                  isActive: try values.decodeIfPresent(Bool.self, forKey: .isActive),
                  windowDurationMinutes: try values.decodeIfPresent(Int.self, forKey: .windowDurationMinutes))
    }

    public func secondsUntilReset(at date: Date = Date()) -> TimeInterval? {
        resetsAt.map { max(0, $0.timeIntervalSince(date)) }
    }
}

public enum CreditUnit: String, Codable, Sendable {
    case usd
    case currency
    case credits
    case resets
}

public enum CreditSource: String, Codable, Sendable {
    case provider
    case manual
}

public struct CreditBalance: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let amount: Decimal?
    public let unit: CreditUnit
    public let expiresAt: Date?
    public let source: CreditSource
    public let asOf: Date?
    public let detail: String?
    public let isUnlimited: Bool
    public let status: String?
    public let doesNotExpire: Bool
    public let currencyCode: String?
    public let originalAmount: Decimal?

    public init(id: String, title: String, amount: Decimal?, unit: CreditUnit = .usd,
                expiresAt: Date? = nil, source: CreditSource = .provider,
                asOf: Date? = nil, detail: String? = nil, isUnlimited: Bool = false, status: String? = nil,
                doesNotExpire: Bool = false, currencyCode: String? = nil, originalAmount: Decimal? = nil) {
        self.id = id
        self.title = title
        self.amount = amount
        self.unit = unit
        self.expiresAt = expiresAt
        self.source = source
        self.asOf = asOf
        self.detail = detail
        self.isUnlimited = isUnlimited
        self.status = status
        self.doesNotExpire = doesNotExpire
        self.currencyCode = currencyCode
        self.originalAmount = originalAmount
    }

    public static func dollars(fromCents cents: Decimal) -> Decimal { cents / 100 }
}

public struct AccountSnapshot: Codable, Sendable, Equatable {
    public let profileID: UUID
    public let fetchedAt: Date?
    public let windows: [UsageWindow]
    public let credits: [CreditBalance]
    public let state: SnapshotState
    public let detail: String?
    public let planName: String?
    public var currentWindows: [UsageWindow] { windows.filter { $0.isActive != false } }

    public init(profileID: UUID, fetchedAt: Date? = nil, windows: [UsageWindow] = [],
                credits: [CreditBalance] = [], state: SnapshotState, detail: String? = nil,
                planName: String? = nil) {
        self.profileID = profileID
        self.fetchedAt = fetchedAt
        self.windows = windows
        self.credits = credits
        self.state = state
        self.detail = detail
        self.planName = planName.flatMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    private enum CodingKeys: String, CodingKey {
        case profileID, fetchedAt, windows, credits, state, detail, planName
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(profileID: try values.decode(UUID.self, forKey: .profileID),
                  fetchedAt: try values.decodeIfPresent(Date.self, forKey: .fetchedAt),
                  windows: try values.decode([UsageWindow].self, forKey: .windows),
                  credits: try values.decode([CreditBalance].self, forKey: .credits),
                  state: try values.decode(SnapshotState.self, forKey: .state),
                  detail: try values.decodeIfPresent(String.self, forKey: .detail),
                  planName: try values.decodeIfPresent(String.self, forKey: .planName))
    }
}

public enum UsageFormatting {
    public static func percentage(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "Unavailable" }
        return String(format: "%.0f%%", min(100, max(0, value)))
    }

    public static func countdown(to date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Reset unavailable" }
        let seconds = max(0, date.timeIntervalSince(now))
        guard seconds > 0 else { return "Reset due" }
        let minutes = Int(ceil(seconds / 60))
        let days = minutes / 1_440
        let hours = minutes % 1_440 / 60
        let remainingMinutes = minutes % 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(remainingMinutes)m" }
        return "\(remainingMinutes)m"
    }
}
