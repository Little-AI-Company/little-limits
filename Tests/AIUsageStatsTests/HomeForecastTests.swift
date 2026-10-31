import Foundation
import Testing
import UsageCore
import UsageHistory
import UsageHistoryStore
@testable import AIUsageStats

private let forecastNow = Date(timeIntervalSince1970: 1_800_000_000)
private let firstAccount = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let secondAccount = UUID(uuidString: "00000000-0000-0000-0000-0000000000A2")!

private func segment(_ account: UUID, from start: TimeInterval, to end: TimeInterval, remaining: Double) -> QuotaHistorySegment {
    QuotaHistorySegment(accountID: account, points: [
        QuotaHistoryPoint(date: forecastNow.addingTimeInterval(start), remainingPercent: remaining),
        QuotaHistoryPoint(date: forecastNow.addingTimeInterval(end), remainingPercent: remaining)
    ], containsChangeOnlyReadings: false)
}

@Test func pooledHistorySumsAccountsAndKeepsEachAccountsGap() {
    let segments = [
        segment(firstAccount, from: -7_200, to: 0, remaining: 60),
        segment(secondAccount, from: -7_200, to: -4_800, remaining: 30),
        segment(secondAccount, from: -3_600, to: 0, remaining: 20)
    ]
    let runs = HomeForecastModel.pooledHistory(segments, accounts: [firstAccount, secondAccount],
                                               from: forecastNow.addingTimeInterval(-7_200), to: forecastNow)
    #expect(runs.count == 2)
    #expect(runs.first?.allSatisfy { $0.remainingPercent == 90 } == true)
    #expect(runs.last?.allSatisfy { $0.remainingPercent == 80 } == true)
    #expect(runs.first?.last?.date == forecastNow.addingTimeInterval(-4_800))
    #expect(runs.last?.first?.date == forecastNow.addingTimeInterval(-3_600))
    #expect(HomeForecastModel.pooledHistory(Array(segments.prefix(1)), accounts: [firstAccount, secondAccount],
                                            from: forecastNow.addingTimeInterval(-7_200), to: forecastNow).isEmpty)
}

@Test func forecastReadsOnlyTheGeneralWeeklyWindow() {
    let claude = UsageOverviewAccount.forecastAccount(firstAccount, provider: .claude, windows: [
        UsageWindow(id: "seven_day", title: "7 days", utilizationPercent: 10, resetsAt: nil),
        UsageWindow(id: "seven_day_fable_5", title: "7 days (Fable 5)", utilizationPercent: 10, resetsAt: nil)
    ])
    let codex = UsageOverviewAccount.forecastAccount(secondAccount, provider: .codex, windows: [
        UsageWindow(id: "codex_secondary", title: "7 days", utilizationPercent: 10, resetsAt: nil, windowDurationMinutes: 10_080),
        UsageWindow(id: "spark_secondary", title: "Spark: 7 days", utilizationPercent: 10, resetsAt: nil, windowDurationMinutes: 10_080),
        UsageWindow(id: "codex_primary", title: "5 hours", utilizationPercent: 10, resetsAt: nil, windowDurationMinutes: 300)
    ])
    func reading(_ account: UUID, _ provider: HistoryProvider, _ id: String, minutes: Int?) -> QuotaReading {
        QuotaReading(provider: provider, accountID: account, windowID: id, usedPercent: 10, resetsAt: nil,
                     windowDurationMinutes: minutes, observedAt: forecastNow, source: .claudeOAuth)
    }
    let kept = HomeForecastModel.generalWeeklyReadings([
        reading(firstAccount, .claude, "seven_day", minutes: nil),
        reading(firstAccount, .claude, "seven_day_fable_5", minutes: nil),
        reading(secondAccount, .codex, "codex_secondary", minutes: 10_080),
        reading(secondAccount, .codex, "spark_secondary", minutes: 10_080),
        reading(secondAccount, .codex, "codex_primary", minutes: 300)
    ], accounts: [claude, codex])
    #expect(kept.map(\.windowID) == ["seven_day", "codex_secondary"])
}

private extension UsageOverviewAccount {
    static func forecastAccount(_ id: UUID, provider: Provider, windows: [UsageWindow]) -> UsageOverviewAccount {
        let profile = AccountProfile(id: id, provider: provider, label: "Test", source: .demo)
        let snapshot = AccountSnapshot(profileID: id, fetchedAt: forecastNow, windows: windows, state: .available)
        return UsageOverview(profiles: [profile], snapshots: [id: snapshot], now: forecastNow).accounts[0]
    }
}

@Test @MainActor
func databaseHistoryKeepsTheLatestReadingOfAnyAge() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let database = try HistoryDatabase(url: directory.appendingPathComponent("history.sqlite"))
    let now = Date()
    func reading(_ account: UUID, daysAgo: Double, used: Double) -> QuotaReading {
        QuotaReading(provider: .claude, accountID: account, windowID: "seven_day", usedPercent: used, resetsAt: nil,
                     windowDurationMinutes: nil, observedAt: now.addingTimeInterval(-daysAgo * 86_400), source: .claudeOAuth)
    }
    try database.recordQuotaReadings([reading(firstAccount, daysAgo: 30, used: 10), reading(firstAccount, daysAgo: 20, used: 20),
                                      reading(secondAccount, daysAgo: 1, used: 5)])
    let history = HomeForecastHistory(source: .database(database))
    await withCheckedContinuation { continuation in
        history.onChange = { continuation.resume() }
        history.observe(now: now, profiles: [], snapshots: [:])
    }
    #expect(history.readings.map(\.accountID) == [secondAccount])
    let latest = Dictionary(uniqueKeysWithValues: history.latestReadings.map { ($0.accountID, $0) })
    #expect(latest[firstAccount]?.usedPercent == 20)
    #expect(latest[secondAccount]?.usedPercent == 5)
}

@Test func changeOnlyReadingBeforeTheRangeHoldsIntoIt() throws {
    let reset = forecastNow.addingTimeInterval(3 * 86_400)
    let account = UsageOverviewAccount.forecastAccount(firstAccount, provider: .claude, windows: [
        UsageWindow(id: "seven_day", title: "7 days", utilizationPercent: 42, resetsAt: reset)
    ])
    let overview = UsageOverview(profiles: [account.profile], snapshots: [firstAccount: try #require(account.snapshot)],
                                 now: forecastNow)
    let readings = [(-2 * 86_400.0, 40.0), (-3_600, 42)].map { offset, used in
        QuotaReading(provider: .claude, accountID: firstAccount, windowID: "seven_day", usedPercent: used, resetsAt: reset,
                     windowDurationMinutes: nil, observedAt: forecastNow.addingTimeInterval(offset), source: .claudeStatusLine)
    }
    let forecast = try #require(HomeForecastModel.providers(overview: overview, readings: readings, range: .nextDay,
                                                            now: forecastNow, calendar: .current).first)
    let history = try #require(forecast.chart?.history)
    #expect(history.count == 1)
    #expect(history.first?.first == QuotaHistoryPoint(date: forecastNow.addingTimeInterval(-86_400), remainingPercent: 60))
    #expect(history.first?.last?.remainingPercent == 58)
}
