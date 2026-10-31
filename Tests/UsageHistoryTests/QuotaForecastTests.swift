import Foundation
import Testing
import UsageHistory

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private let accountA = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
private let accountB = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

private func hours(_ value: Double) -> TimeInterval { value * 3_600 }

private func reading(_ account: UUID, hoursAgo: Double, used: Double, resetsAt: Date?,
                     source: QuotaReadingSource = .claudeOAuth, provider: HistoryProvider = .claude) -> QuotaReading {
    QuotaReading(provider: provider, accountID: account, windowID: "seven_day", usedPercent: used, resetsAt: resetsAt,
                 windowDurationMinutes: 10_080, observedAt: now.addingTimeInterval(-hours(hoursAgo)), source: source)
}

private let laterReset = now.addingTimeInterval(hours(100))

private func isClose(_ date: Date?, _ expected: Date) -> Bool {
    date.map { abs($0.timeIntervalSince(expected)) < 1e-3 } ?? false
}

private func isClose(_ value: Double?, _ expected: Double) -> Bool {
    value.map { abs($0 - expected) < 1e-9 } ?? false
}

@Test func drainSkipsThePairAcrossAReset() throws {
    let oldReset = now.addingTimeInterval(-hours(5))
    let history = [
        reading(accountA, hoursAgo: 10, used: 20, resetsAt: oldReset),
        reading(accountA, hoursAgo: 8, used: 90, resetsAt: oldReset),
        reading(accountA, hoursAgo: 4, used: 0, resetsAt: laterReset),
        reading(accountA, hoursAgo: 2, used: 4, resetsAt: laterReset)
    ]
    let drain = try #require(QuotaForecast.drainRate(
        provider: .claude, history: history,
        counted: [CountedQuota(accountID: accountA, remainingPercent: 96, resetsAt: laterReset)], now: now))
    #expect(abs(drain.percentPerHour - 74.0 / 4) < 1e-9)
}

@Test func drainSkipsAPairWhoseEarlierResetPassedEvenWithTheSameResetTime() {
    let passed = now.addingTimeInterval(-hours(3))
    let history = [reading(accountA, hoursAgo: 4, used: 10, resetsAt: passed),
                   reading(accountA, hoursAgo: 2, used: 30, resetsAt: passed)]
    #expect(QuotaForecast.drainRate(
        provider: .claude, history: history,
        counted: [CountedQuota(accountID: accountA, remainingPercent: 70, resetsAt: laterReset)], now: now) == nil)
}

@Test func accountLeavingTheCountedSetIsNotDrain() throws {
    let history = [
        reading(accountA, hoursAgo: 4, used: 10, resetsAt: laterReset),
        reading(accountA, hoursAgo: 2, used: 12, resetsAt: laterReset),
        reading(accountB, hoursAgo: 4, used: 20, resetsAt: laterReset),
        reading(accountB, hoursAgo: 2, used: 60, resetsAt: laterReset)
    ]
    let drain = try #require(QuotaForecast.drainRate(
        provider: .claude, history: history,
        counted: [CountedQuota(accountID: accountA, remainingPercent: 88, resetsAt: laterReset)], now: now))
    #expect(abs(drain.percentPerHour - 1) < 1e-9)
}

@Test func drainSumsPerAccountRatesAndIgnoresTheOtherProvider() throws {
    let history = [
        reading(accountA, hoursAgo: 4, used: 10, resetsAt: laterReset),
        reading(accountA, hoursAgo: 2, used: 12, resetsAt: laterReset),
        reading(accountB, hoursAgo: 1, used: 20, resetsAt: laterReset),
        reading(accountB, hoursAgo: 0, used: 23, resetsAt: laterReset),
        reading(accountA, hoursAgo: 3, used: 0, resetsAt: laterReset, source: .codexAppServer, provider: .codex),
        reading(accountA, hoursAgo: 1, used: 90, resetsAt: laterReset, source: .codexAppServer, provider: .codex)
    ]
    let drain = try #require(QuotaForecast.drainRate(
        provider: .claude, history: history,
        counted: [CountedQuota(accountID: accountA, remainingPercent: 88, resetsAt: laterReset),
                  CountedQuota(accountID: accountB, remainingPercent: 77, resetsAt: laterReset)], now: now))
    #expect(abs(drain.percentPerHour - 4) < 1e-9)
}

@Test func shortHistoryReportsAShortLookbackAndLongHistoryIsCutAt24Hours() throws {
    let counted = [CountedQuota(accountID: accountA, remainingPercent: 80, resetsAt: laterReset)]
    let short = try #require(QuotaForecast.drainRate(
        provider: .claude,
        history: [reading(accountA, hoursAgo: 6, used: 14, resetsAt: laterReset),
                  reading(accountA, hoursAgo: 0, used: 20, resetsAt: laterReset)],
        counted: counted, now: now))
    #expect(short.isShortLookback)
    #expect(short.lookback == hours(6))
    #expect(abs(short.percentPerHour - 1) < 1e-9)

    let full = try #require(QuotaForecast.drainRate(
        provider: .claude,
        history: [reading(accountA, hoursAgo: 30, used: 0, resetsAt: laterReset),
                  reading(accountA, hoursAgo: 0, used: 30, resetsAt: laterReset)],
        counted: counted, now: now))
    #expect(!full.isShortLookback)
    #expect(full.lookback == hours(24))
    #expect(abs(full.percentPerHour - 1) < 1e-9)
}

@Test func drainIsUnknownWithoutAUsablePair() {
    let counted = [CountedQuota(accountID: accountA, remainingPercent: 80, resetsAt: laterReset)]
    #expect(QuotaForecast.drainRate(provider: .claude, history: [], counted: counted, now: now) == nil)
    #expect(QuotaForecast.drainRate(
        provider: .claude, history: [reading(accountA, hoursAgo: 1, used: 20, resetsAt: laterReset)],
        counted: counted, now: now) == nil)
    let result = QuotaForecast.forecast(QuotaForecastInput(
        provider: .claude, history: [], counted: counted, now: now, horizon: .sevenDays))
    #expect(result.drain == nil)
    #expect(result.projection == nil)

    let flat = QuotaForecast.drainRate(
        provider: .claude,
        history: [reading(accountA, hoursAgo: 2, used: 20, resetsAt: laterReset),
                  reading(accountA, hoursAgo: 1, used: 20, resetsAt: laterReset)],
        counted: counted, now: now)
    #expect(flat?.percentPerHour == 0)
}

@Test func projectionReachesZeroWithoutAReset() throws {
    let counted = [CountedQuota(accountID: accountA, remainingPercent: 30, resetsAt: nil),
                   CountedQuota(accountID: accountB, remainingPercent: 20, resetsAt: nil)]
    let projection = QuotaForecast.project(counted: counted, percentPerHour: 4, now: now, horizon: .oneDay)
    #expect(projection.capacityPercent == 200)
    #expect(projection.points.count == 25)
    #expect(projection.points.first == QuotaProjectionPoint(date: now, remainingPercent: 50))
    #expect(isClose(projection.points[1].remainingPercent, 46))
    #expect(isClose(projection.reachesZeroAt, now.addingTimeInterval(hours(12.5))))
    #expect(projection.points[13].remainingPercent == 0)
    #expect(projection.points.allSatisfy { $0.remainingPercent >= 0 })
    #expect(projection.resets.isEmpty)
}

@Test func projectionResetDelaysTheZeroCrossing() throws {
    let resetA = now.addingTimeInterval(hours(5.5))
    let counted = [CountedQuota(accountID: accountA, remainingPercent: 10, resetsAt: resetA),
                   CountedQuota(accountID: accountB, remainingPercent: 10, resetsAt: nil)]
    let projection = QuotaForecast.project(counted: counted, percentPerHour: 2, now: now, horizon: .oneDay)
    #expect(projection.resets == [QuotaResetEvent(accountID: accountA, date: resetA, gainPercent: 90)])
    #expect(abs(projection.points[6].remainingPercent - 98) < 1e-9)
    #expect(projection.reachesZeroAt == nil)

    let week = QuotaForecast.project(counted: counted, percentPerHour: 2, now: now, horizon: .sevenDays)
    #expect(week.points.count == 7 * 24 + 1)
    #expect(isClose(week.reachesZeroAt, resetA.addingTimeInterval(hours(49.5))))
}

@Test func projectionReportsTheFirstZeroEvenWhenAResetRefillsLater() {
    let resetA = now.addingTimeInterval(hours(8))
    let counted = [CountedQuota(accountID: accountA, remainingPercent: 0, resetsAt: resetA),
                   CountedQuota(accountID: accountB, remainingPercent: 10, resetsAt: nil)]
    let projection = QuotaForecast.project(counted: counted, percentPerHour: 5, now: now, horizon: .oneDay)
    #expect(isClose(projection.reachesZeroAt, now.addingTimeInterval(hours(2))))
    #expect(projection.points[7].remainingPercent == 0)
    #expect(abs(projection.points[8].remainingPercent - 100) < 1e-9)
    #expect(abs(projection.points[9].remainingPercent - 95) < 1e-9)
}

private func seconds(_ account: UUID, at offset: TimeInterval, used: Double, resetsAt: Date? = laterReset,
                     source: QuotaReadingSource) -> QuotaReading {
    QuotaReading(provider: .claude, accountID: account, windowID: "seven_day", usedPercent: used, resetsAt: resetsAt,
                 windowDurationMinutes: 10_080, observedAt: now.addingTimeInterval(offset), source: source)
}

@Test func polledLineBreaksBeyond450Seconds() {
    let joined = QuotaForecast.historySegments(readings: [
        seconds(accountA, at: -1_000, used: 10, source: .claudeOAuth),
        seconds(accountA, at: -551, used: 11, source: .claudeOAuth)
    ], now: now)
    #expect(joined.count == 1)
    #expect(joined.first?.points.map(\.remainingPercent) == [90, 89])
    #expect(joined.first?.containsChangeOnlyReadings == false)

    let broken = QuotaForecast.historySegments(readings: [
        seconds(accountA, at: -1_000, used: 10, source: .codexAppServer),
        seconds(accountA, at: -549, used: 11, source: .codexAppServer)
    ], now: now)
    #expect(broken.count == 2)
    #expect(broken.map { $0.points.count } == [1, 1])
}

@Test func historySegmentsKeepAccountsApart() {
    let segments = QuotaForecast.historySegments(readings: [
        seconds(accountB, at: -600, used: 50, source: .codexLogBackfill),
        seconds(accountA, at: -300, used: 10, source: .claudeOAuth),
        seconds(accountB, at: -100, used: 55, source: .codexLogBackfill)
    ], now: now)
    #expect(segments.map(\.accountID) == [accountB, accountA])
    #expect(segments[0].points.map(\.remainingPercent) == [50, 50, 45, 45])
    #expect(segments[1].points.map(\.remainingPercent) == [90])
}

@Test func drainKeepsAPairWhoseResetTimesDifferOnlyInPrecision() throws {
    let whole = Date(timeIntervalSince1970: laterReset.timeIntervalSince1970.rounded())
    let fractional = whole.addingTimeInterval(0.734)
    let history = [reading(accountA, hoursAgo: 4, used: 10, resetsAt: whole),
                   reading(accountA, hoursAgo: 2, used: 30, resetsAt: fractional, source: .claudeStatusLine)]
    let drain = try #require(QuotaForecast.drainRate(
        provider: .claude, history: history,
        counted: [CountedQuota(accountID: accountA, remainingPercent: 70, resetsAt: whole)], now: now))
    #expect(isClose(drain.percentPerHour, 10))

    let moved = [history[0], reading(accountA, hoursAgo: 2, used: 30, resetsAt: whole.addingTimeInterval(60))]
    #expect(QuotaForecast.drainRate(
        provider: .claude, history: moved,
        counted: [CountedQuota(accountID: accountA, remainingPercent: 70, resetsAt: whole)], now: now) == nil)
}

@Test func longOvernightPairCountsIncludingIdleTime() throws {
    let history = [
        reading(accountA, hoursAgo: 20, used: 10, resetsAt: laterReset),
        reading(accountA, hoursAgo: 11, used: 10, resetsAt: laterReset),
        reading(accountA, hoursAgo: 10, used: 22, resetsAt: laterReset)
    ]
    let drain = try #require(QuotaForecast.drainRate(
        provider: .claude, history: history,
        counted: [CountedQuota(accountID: accountA, remainingPercent: 78, resetsAt: laterReset)], now: now))
    #expect(abs(drain.percentPerHour - 12.0 / 10) < 1e-9)
}

@Test func changeOnlyValueIsHeldThenBrokenAtItsReset() {
    let reset = now.addingTimeInterval(-hours(5))
    let segments = QuotaForecast.historySegments(readings: [
        seconds(accountA, at: -hours(10), used: 20, resetsAt: reset, source: .claudeStatusLine),
        seconds(accountA, at: -hours(8), used: 30, resetsAt: reset, source: .claudeStatusLine),
        seconds(accountA, at: -hours(2), used: 1, resetsAt: laterReset, source: .claudeStatusLine)
    ], now: now)
    #expect(segments.count == 2)
    #expect(segments[0].containsChangeOnlyReadings)
    #expect(segments[0].points == [
        QuotaHistoryPoint(date: now.addingTimeInterval(-hours(10)), remainingPercent: 80),
        QuotaHistoryPoint(date: now.addingTimeInterval(-hours(8)), remainingPercent: 80),
        QuotaHistoryPoint(date: now.addingTimeInterval(-hours(8)), remainingPercent: 70),
        QuotaHistoryPoint(date: reset, remainingPercent: 70)
    ])
    #expect(segments[1].points == [
        QuotaHistoryPoint(date: now.addingTimeInterval(-hours(2)), remainingPercent: 99),
        QuotaHistoryPoint(date: now, remainingPercent: 99)
    ])
}

@Test func changeOnlyLineBreaksWhenTheNextReadingLandsExactlyAtTheReset() {
    let reset = now.addingTimeInterval(-hours(5))
    let segments = QuotaForecast.historySegments(readings: [
        seconds(accountA, at: -hours(8), used: 30, resetsAt: reset, source: .claudeStatusLine),
        seconds(accountA, at: -hours(5), used: 0, resetsAt: laterReset, source: .claudeStatusLine)
    ], now: now)
    #expect(segments.count == 2)
    #expect(segments[0].points == [
        QuotaHistoryPoint(date: now.addingTimeInterval(-hours(8)), remainingPercent: 70),
        QuotaHistoryPoint(date: reset, remainingPercent: 70)
    ])
    #expect(segments[1].points.first == QuotaHistoryPoint(date: reset, remainingPercent: 100))
}
