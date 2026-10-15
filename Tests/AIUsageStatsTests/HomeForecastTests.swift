import Foundation
import Testing
import UsageCore
import UsageHistory
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

/// A gap in either account is a gap in the pooled line, never a drop to one account's value or a joined line.
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
    // An account with no history at all leaves no pooled line.
    #expect(HomeForecastModel.pooledHistory(Array(segments.prefix(1)), accounts: [firstAccount, secondAccount],
                                            from: forecastNow.addingTimeInterval(-7_200), to: forecastNow).isEmpty)
}

/// Only each account's general weekly window joins the forecast, decided by UsageCore's window rules.
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

/// The demonstration renders a separate forecast for each provider; with no history each provider says so in one line.
@Test @MainActor
func demonstrationForecastKeepsProvidersApartAndExplainsMissingHistory() throws {
    let snapshots = Dictionary(uniqueKeysWithValues: DemoFixtures.homeSnapshots.map { ($0.profileID, $0) })
    let now = try #require(snapshots.values.first?.fetchedAt)
    let overview = UsageOverview(profiles: DemoFixtures.homeProfiles, snapshots: snapshots, now: now)

    let empty = HomeForecastModel.providers(overview: overview, readings: [], range: .nextWeek, now: now, calendar: .current)
    #expect(empty.map(\.provider) == [.claude, .codex])
    #expect(empty.allSatisfy { $0.chart == nil && $0.lines.isEmpty && $0.notice != nil })

    let readings = HomeForecastDemonstration.readings(profiles: DemoFixtures.homeProfiles, snapshots: snapshots, now: now)
    let forecasts = HomeForecastModel.providers(overview: overview, readings: readings, range: .nextWeek, now: now,
                                                calendar: .current)
    #expect(forecasts.map(\.provider) == [.claude, .codex])
    for forecast in forecasts {
        let chart = try #require(forecast.chart)
        #expect(chart.capacityPercent == 200)
        // The demonstration closes the app for eight hours, so history has a gap.
        #expect(chart.history.count == 2)
        #expect(chart.history.joined().allSatisfy { $0.remainingPercent <= 200 && $0.date <= now })
        #expect(forecast.lines.first?.value.hasPrefix("About ") == true)
        #expect(forecast.lines.filter { $0.label == "Last seen" }.count == 2)
    }
    #expect(forecasts[0].lines[1].value == "Not in the next 7 days")
    #expect(forecasts[1].lines[1].value != "Not in the next 7 days")
    #expect(forecasts[1].lines[1].value != "Unknown")
}

private extension UsageOverviewAccount {
    static func forecastAccount(_ id: UUID, provider: Provider, windows: [UsageWindow]) -> UsageOverviewAccount {
        let profile = AccountProfile(id: id, provider: provider, label: "Test", source: .demo)
        let snapshot = AccountSnapshot(profileID: id, fetchedAt: forecastNow, windows: windows, state: .available)
        return UsageOverview(profiles: [profile], snapshots: [id: snapshot], now: forecastNow).accounts[0]
    }
}
