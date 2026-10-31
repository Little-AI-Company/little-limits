import Foundation

public enum ForecastHorizon: Int, Sendable, CaseIterable {
    case oneDay = 1
    case sevenDays = 7

    public var duration: TimeInterval { TimeInterval(rawValue) * 86_400 }
}

public struct CountedQuota: Sendable, Equatable {
    public let accountID: UUID
    public let remainingPercent: Double
    public let resetsAt: Date?

    public init(accountID: UUID, remainingPercent: Double, resetsAt: Date?) {
        self.accountID = accountID
        self.remainingPercent = remainingPercent
        self.resetsAt = resetsAt
    }

    public var usedPercent: Double { 100 - min(100, max(0, remainingPercent)) }
}

public struct QuotaForecastInput: Sendable {
    public let provider: HistoryProvider
    public let history: [QuotaReading]
    public let counted: [CountedQuota]
    public let now: Date
    public let horizon: ForecastHorizon

    public init(provider: HistoryProvider, history: [QuotaReading], counted: [CountedQuota], now: Date,
                horizon: ForecastHorizon) {
        self.provider = provider
        self.history = history
        self.counted = counted
        self.now = now
        self.horizon = horizon
    }
}

public struct QuotaDrainRate: Sendable, Equatable {
    public let percentPerHour: Double
    public let lookback: TimeInterval
    public var isShortLookback: Bool { lookback < QuotaForecast.drainLookback }

    public init(percentPerHour: Double, lookback: TimeInterval) {
        self.percentPerHour = percentPerHour
        self.lookback = lookback
    }
}

public struct QuotaProjectionPoint: Sendable, Equatable {
    public let date: Date
    public let remainingPercent: Double

    public init(date: Date, remainingPercent: Double) {
        self.date = date
        self.remainingPercent = remainingPercent
    }
}

public struct QuotaResetEvent: Sendable, Equatable {
    public let accountID: UUID
    public let date: Date
    public let gainPercent: Double

    public init(accountID: UUID, date: Date, gainPercent: Double) {
        self.accountID = accountID
        self.date = date
        self.gainPercent = gainPercent
    }
}

public struct QuotaProjection: Sendable, Equatable {
    public let points: [QuotaProjectionPoint]
    public let resets: [QuotaResetEvent]
    public let reachesZeroAt: Date?
    public let capacityPercent: Double
}

public struct QuotaForecastResult: Sendable, Equatable {
    public let provider: HistoryProvider
    public let drain: QuotaDrainRate?
    public let projection: QuotaProjection?
}

public struct QuotaHistoryPoint: Sendable, Equatable {
    public let date: Date
    public let remainingPercent: Double

    public init(date: Date, remainingPercent: Double) {
        self.date = date
        self.remainingPercent = remainingPercent
    }
}

public struct QuotaHistorySegment: Sendable, Equatable {
    public let accountID: UUID
    public let points: [QuotaHistoryPoint]
    public let containsChangeOnlyReadings: Bool

    public init(accountID: UUID, points: [QuotaHistoryPoint], containsChangeOnlyReadings: Bool) {
        self.accountID = accountID
        self.points = points
        self.containsChangeOnlyReadings = containsChangeOnlyReadings
    }
}

extension QuotaReadingSource {
    public var recordsOnlyChanges: Bool {
        switch self {
        case .claudeOAuth, .codexAppServer: false
        case .claudeStatusLine, .codexLogBackfill: true
        }
    }
}

public enum QuotaForecast {
    public static let drainLookback: TimeInterval = 86_400
    public static let polledRefreshInterval: TimeInterval = 300
    public static let polledGapLimit: TimeInterval = polledRefreshInterval * 1.5
    public static let resetTolerance: TimeInterval = 60

    public static func isSameReset(_ first: Date?, _ second: Date?) -> Bool {
        switch (first, second) {
        case (nil, nil): true
        case let (first?, second?): abs(first.timeIntervalSince(second)) < resetTolerance
        default: false
        }
    }

    public static func forecast(_ input: QuotaForecastInput) -> QuotaForecastResult {
        let drain = drainRate(provider: input.provider, history: input.history, counted: input.counted, now: input.now)
        let projection = drain.flatMap { drain in
            input.counted.isEmpty ? nil : project(counted: input.counted, percentPerHour: drain.percentPerHour,
                                                  now: input.now, horizon: input.horizon)
        }
        return QuotaForecastResult(provider: input.provider, drain: drain, projection: projection)
    }

    public static func drainRate(provider: HistoryProvider, history: [QuotaReading], counted: [CountedQuota],
                                 now: Date) -> QuotaDrainRate? {
        let countedIDs = Set(counted.map(\.accountID))
        let start = now.addingTimeInterval(-drainLookback)
        let byAccount = Dictionary(grouping: history.filter {
            $0.provider == provider && countedIDs.contains($0.accountID) && $0.observedAt <= now
        }, by: \.accountID)

        var total = 0.0
        var earliestUsed: Date?
        for readings in byAccount.values {
            let sorted = readings.sorted { $0.observedAt < $1.observedAt }
            var increase = 0.0
            var covered: TimeInterval = 0
            for (earlier, later) in zip(sorted, sorted.dropFirst()) where later.observedAt > start {
                guard isSameReset(earlier.resetsAt, later.resetsAt),
                      earlier.resetsAt.map({ $0 > later.observedAt }) ?? true else { continue }
                let span = later.observedAt.timeIntervalSince(earlier.observedAt)
                guard span > 0 else { continue }
                let from = max(earlier.observedAt, start)
                let inWindow = later.observedAt.timeIntervalSince(from)
                increase += (later.usedPercent - earlier.usedPercent) * inWindow / span
                covered += inWindow
                earliestUsed = min(earliestUsed ?? from, from)
            }
            if covered > 0 { total += max(0, increase) / (covered / 3_600) }
        }
        guard let earliestUsed else { return nil }
        return QuotaDrainRate(percentPerHour: total, lookback: now.timeIntervalSince(earliestUsed))
    }

    public static func project(counted: [CountedQuota], percentPerHour: Double, now: Date,
                               horizon: ForecastHorizon) -> QuotaProjection {
        let capacity = Double(counted.count) * 100
        let end = now.addingTimeInterval(horizon.duration)
        let resets = counted.compactMap { account -> QuotaResetEvent? in
            guard let reset = account.resetsAt, reset > now, reset <= end else { return nil }
            return QuotaResetEvent(accountID: account.accountID, date: reset, gainPercent: account.usedPercent)
        }.sorted { $0.date < $1.date }

        let perSecond = percentPerHour / 3_600
        var remaining = min(capacity, max(0, counted.reduce(0) { $0 + min(100, max(0, $1.remainingPercent)) }))
        var time = now
        var reachesZeroAt: Date? = remaining <= 0 ? now : nil
        var pendingResets = resets[...]

        func drain(until target: Date) {
            let elapsed = target.timeIntervalSince(time)
            guard elapsed > 0 else { return }
            if remaining > 0, perSecond > 0, remaining <= perSecond * elapsed, reachesZeroAt == nil {
                reachesZeroAt = time.addingTimeInterval(remaining / perSecond)
            }
            remaining = max(0, remaining - perSecond * elapsed)
            time = target
        }

        var points = [QuotaProjectionPoint(date: now, remainingPercent: remaining)]
        for hour in 1...(horizon.rawValue * 24) {
            let step = now.addingTimeInterval(TimeInterval(hour) * 3_600)
            while let reset = pendingResets.first, reset.date <= step {
                drain(until: reset.date)
                remaining = min(capacity, remaining + reset.gainPercent)
                pendingResets = pendingResets.dropFirst()
            }
            drain(until: step)
            points.append(QuotaProjectionPoint(date: step, remainingPercent: remaining))
        }
        return QuotaProjection(points: points, resets: resets, reachesZeroAt: reachesZeroAt,
                               capacityPercent: capacity)
    }

    public static func historySegments(readings: [QuotaReading], now: Date) -> [QuotaHistorySegment] {
        var order: [UUID] = []
        var byAccount: [UUID: [QuotaReading]] = [:]
        for reading in readings where reading.observedAt <= now {
            if byAccount[reading.accountID] == nil { order.append(reading.accountID) }
            byAccount[reading.accountID, default: []].append(reading)
        }

        var segments: [QuotaHistorySegment] = []
        for accountID in order {
            let sorted = byAccount[accountID, default: []].sorted { $0.observedAt < $1.observedAt }
            var points: [QuotaHistoryPoint] = []
            var changeOnly = false
            func close() {
                if !points.isEmpty {
                    segments.append(QuotaHistorySegment(accountID: accountID, points: points,
                                                        containsChangeOnlyReadings: changeOnly))
                }
                points = []
                changeOnly = false
            }

            for (index, reading) in sorted.enumerated() {
                let remaining = 100 - reading.usedPercent
                points.append(QuotaHistoryPoint(date: reading.observedAt, remainingPercent: remaining))
                let next = sorted.indices.contains(index + 1) ? sorted[index + 1] : nil
                if reading.source.recordsOnlyChanges {
                    changeOnly = true
                    let holdEnd = min(next?.observedAt ?? now, reading.resetsAt ?? .distantFuture)
                    if holdEnd > reading.observedAt {
                        points.append(QuotaHistoryPoint(date: holdEnd, remainingPercent: remaining))
                    }
                    if let next, let reset = reading.resetsAt, reset <= next.observedAt { close() }
                } else if let next, next.observedAt.timeIntervalSince(reading.observedAt) > polledGapLimit {
                    close()
                }
            }
            close()
        }
        return segments
    }
}
