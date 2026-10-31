import Foundation
import Testing
import UsageCore
@testable import AIUsageStats

@Test @MainActor
func missingObservationDoesNotPresentRetainedPercentagesAsHistory() {
    for observed in [Optional<Date>.none, homeReadingNow.addingTimeInterval(1)] {
        let row = homeRow(windows: [homeWindow(used: 30)], observed: observed)
        let line = homeLines(row.session)[0]
        #expect(line.primary.hasPrefix("Unknown"))
        #expect(!line.primary.contains("70%"))
        #expect(!line.primary.contains("Last known"))
        #expect(row.updatedPrimary == "Unavailable")
        #expect(row.status == "Observation time unknown")
    }
}

@Test @MainActor
func partialQuotaKeepsKnownValuesAndIndependentEarnedResets() {
    let row = homeRow(windows: [homeWindow(used: 37),
                               UsageWindow(id: "weekly", title: "7 days", utilizationPercent: nil,
                                           resetsAt: homeReadingNow.addingTimeInterval(7_200), windowDurationMinutes: 10_080)],
                      credits: [homeResetCount(2)])
    #expect(homeLines(row.session)[0].primary == "63% left")
    #expect(homeLines(row.weekly)[0].primary == "Unknown")
    #expect(homeLines(row.earned)[0].primary == "2 available")
    #expect(row.updatedPrimary != "Unavailable")
    #expect(row.status == "Some usage unknown")
}

@Test @MainActor
func tinyPositiveQuotaIsDifferentFromMeasuredExhaustion() {
    let small = homeRow(windows: [homeWindow(used: 99.99)])
    #expect(homeLines(small.session)[0].tone == .warning)
    #expect(homeLines(small.session)[0].accessibilityLabel.contains("left, Low"))
    #expect(!homeLines(small.session)[0].primary.hasPrefix("0%"))
    let zero = homeRow(windows: [homeWindow(used: 100)])
    // The table draws the state word on its own line; the spoken label keeps the whole phrase.
    #expect(homeLines(zero.session)[0].primary == "0% left")
    #expect(homeLines(zero.session)[0].tone == .critical)
    #expect(homeLines(zero.session)[0].accessibilityLabel.contains("0% left, Limit reached"))
}

@Test @MainActor
func earnedExpiryUsesOnlyAvailableKnownGrants() {
    let expiry = homeReadingNow.addingTimeInterval(86_400)
    let row = homeRow(windows: [homeWindow(used: 20)], credits: [
        homeResetCount(3),
        homeGrant("expired", status: "expired", expires: homeReadingNow.addingTimeInterval(-1)),
        homeGrant("used", status: "consumed", expires: homeReadingNow.addingTimeInterval(60)),
        homeGrant("unknown", status: nil, expires: homeReadingNow.addingTimeInterval(120)),
        homeGrant("available", status: "available", expires: expiry)
    ])
    let line = homeLines(row.earned)[0]
    #expect(line.primary == "3 available")
    #expect(line.secondary?.hasPrefix("Next expires") == true)
    #expect(line.toolTip.contains(InterfaceFormatting.exactDate(expiry)))
    #expect(!line.toolTip.contains(InterfaceFormatting.exactDate(homeReadingNow.addingTimeInterval(60))))
}

@Test @MainActor
func oneNonexpiringGrantDoesNotHideUnknownExpiry() {
    let row = homeRow(windows: [homeWindow(used: 20)], credits: [
        homeResetCount(2),
        homeGrant("permanent", status: "available", expires: nil, doesNotExpire: true),
        homeGrant("undated", status: "available", expires: nil)
    ])
    #expect(homeLines(row.earned)[0].secondary == "Expiry unavailable")
}

@Test @MainActor
func earnedCountHasItsOwnObservationTime() {
    let old = homeReadingNow.addingTimeInterval(-1_080)
    let currentQuota = homeRow(windows: [homeWindow(used: 20)], credits: [homeResetCount(2, observed: old)])
    #expect(homeLines(currentQuota.session)[0].primary == "80% left")
    #expect(homeLines(currentQuota.earned)[0].preface == ["Last known"])
    #expect(homeLines(currentQuota.earned)[0].primary == "2 available")
    #expect(homeLines(currentQuota.earned)[0].tertiary?.hasPrefix("Last read") == true)

    let oldQuota = homeRow(windows: [homeWindow(used: 20)], observed: old,
                           state: .stale, credits: [homeResetCount(2)])
    #expect(homeLines(oldQuota.session)[0].preface == ["Last known"])
    #expect(homeLines(oldQuota.session)[0].primary == "80% left")
    #expect(homeLines(oldQuota.earned)[0].primary == "2 available")

    let unknownCount = homeRow(windows: [homeWindow(used: 20)],
                               credits: [homeResetCount(2, observed: nil)])
    #expect(homeLines(unknownCount.earned)[0].primary == "Unknown")
}

@Test @MainActor
func passedEarnedResetExpiryMakesTheCountHistorical() {
    let observed = homeReadingNow.addingTimeInterval(-120)
    let expiry = homeReadingNow.addingTimeInterval(-60)
    let grant = CreditBalance(id: "quota_reset_available", title: "Earned reset", amount: nil,
                              unit: .resets, expiresAt: expiry, asOf: observed, status: "available")
    let row = homeRow(windows: [homeWindow(used: 20)],
                      credits: [homeResetCount(1, observed: observed), grant])
    let line = homeLines(row.earned)[0]
    #expect(line.preface == ["Last known"])
    #expect(line.primary == "1 available")
    #expect(line.secondary?.hasPrefix("Expired") == true)
    #expect(line.toolTip.contains(InterfaceFormatting.exactDate(expiry)))
    #expect(line.toolTip.contains("Refresh to check current availability"))
    #expect(homeLines(row.session)[0].primary == "80% left")
}

@Test(arguments: [(0.0, "0%", HomeReadingTone.critical), (0.04, "<0.1%", .warning), (0.4, "0.4%", .warning),
                  (19.96, "20%", .warning), (20.0, "20%", .warning), (20.04, ">20%", .neutral), (100.0, "100%", .neutral),
                  (Double.nan, "Unknown", .neutral)])
func remainingPercentTextNeverRoundsAcrossZeroOrTheLowThreshold(_ remaining: Double, _ text: String, _ tone: HomeReadingTone) {
    #expect(RemainingPercentText.format(remaining) == text)
    #expect(HomeInterfaceFormatting.tone(for: remaining) == tone)
}

@Test(arguments: [(299.0, false), (300.0, true)])
func readingIsOutdatedFromTheFreshnessLimit(_ age: TimeInterval, _ outdated: Bool) {
    let snapshot = AccountSnapshot(profileID: homeReadingProfile.id, fetchedAt: homeReadingNow.addingTimeInterval(-age),
                                   windows: [homeWindow(used: 30)], state: .available)
    #expect(InterfaceFormatting.isOutdated(snapshot, now: homeReadingNow) == outdated)
}

private let homeReadingNow = Date(timeIntervalSince1970: 1_700_000_000)
private let homeReadingProfile = AccountProfile(provider: .codex, label: "Work", source: .demo,
                                                providerEmail: "work@example.invalid")

private func homeWindow(used: Double?) -> UsageWindow {
    UsageWindow(id: "session", title: "5 hours", utilizationPercent: used,
                resetsAt: homeReadingNow.addingTimeInterval(3_600), windowDurationMinutes: 300)
}

@MainActor
private func homeRow(windows: [UsageWindow], observed: Date? = homeReadingNow,
                     state: SnapshotState = .available, credits: [CreditBalance] = []) -> HomeAccountRow {
    let snapshot = AccountSnapshot(profileID: homeReadingProfile.id, fetchedAt: observed,
                                   windows: windows, credits: credits, state: state)
    let overview = UsageOverview(profiles: [homeReadingProfile],
                                 snapshots: [homeReadingProfile.id: snapshot], now: homeReadingNow)
    return HomeInterfaceFormatting.rows(for: overview.accounts, now: homeReadingNow, calendar: .current)[0]
}

private func homeLines(_ cell: HomeMeterCell) -> [HomeReadingLine] {
    switch cell {
    case .message(let line): [line]
    case .meters(let lines): lines
    }
}

private func homeResetCount(_ count: Int, observed: Date? = homeReadingNow) -> CreditBalance {
    CreditBalance(id: "quota_reset_credits", title: "Earned resets", amount: Decimal(count),
                  unit: .resets, asOf: observed)
}

private func homeGrant(_ name: String, status: String?, expires: Date?, doesNotExpire: Bool = false) -> CreditBalance {
    CreditBalance(id: "quota_reset_" + name, title: "Earned reset", amount: nil, unit: .resets,
                  expiresAt: expires, asOf: homeReadingNow, status: status, doesNotExpire: doesNotExpire)
}
