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

/// ACCOUNT-05: a sign-in failure shows the last known value without its timing, as the status menu does, and an
/// account with no reading says `Unavailable` in every cell instead of four different names.
@Test @MainActor
func outdatedAndMissingReadingsUseOneWording() {
    let signIn = homeRow(windows: [homeWindow(used: 20)], state: .authenticationRequired)
    let line = homeLines(signIn.session)[0]
    #expect(line.preface == ["Last known"])
    #expect(line.primary == "80% left")
    #expect(line.secondary == nil)
    #expect(signIn.status == "Sign-in required")
    // HOME-30: the last read time stays, so the age of the last known values is visible.
    #expect(signIn.updatedPrimary == homeReadingNow.formatted(.dateTime.hour().minute()))
    #expect(signIn.updatedSecondary == "Not refreshed")
    // A Claude account never reports earned resets, in any reading state.
    let claude = AccountProfile(provider: .claude, label: "Studio", source: .demo, providerEmail: "studio@example.invalid")
    let claudeSignIn = AccountSnapshot(profileID: claude.id, fetchedAt: homeReadingNow, windows: [homeWindow(used: 20)],
                                       credits: [], state: .authenticationRequired)
    let overview = UsageOverview(profiles: [claude], snapshots: [claude.id: claudeSignIn], now: homeReadingNow)
    let claudeRow = HomeInterfaceFormatting.rows(for: overview.accounts, now: homeReadingNow, calendar: .current)[0]
    #expect(homeLines(claudeRow.earned).map(\.primary) == ["Not supported"])

    let empty = homeRow(windows: [], observed: nil)
    #expect([empty.session, empty.weekly, empty.other].allSatisfy { homeLines($0).map(\.primary) == ["Unavailable"] })
    #expect(empty.status == "Unavailable")
    #expect(empty.updatedPrimary == "Unavailable")
}

@Test @MainActor
func ordinaryCodexWindowsKeepTheirColumnsWithAdditionalMeters() {
    let windows = [
        UsageWindow(id: "codex_primary", title: "Codex: 5 hours", utilizationPercent: 20,
                    resetsAt: homeReadingNow.addingTimeInterval(3_600),
                    windowDurationMinutes: 300),
        UsageWindow(id: "codex_secondary", title: "Codex: 7 days", utilizationPercent: 40,
                    resetsAt: homeReadingNow.addingTimeInterval(86_400),
                    windowDurationMinutes: 10_080),
        UsageWindow(id: "spark_primary", title: "Spark: 5 hours", utilizationPercent: 60,
                    resetsAt: homeReadingNow.addingTimeInterval(3_600),
                    windowDurationMinutes: 300)
    ]
    let row = homeRow(windows: windows)
    #expect(homeLines(row.session)[0].primary == "80% left")
    #expect(homeLines(row.weekly)[0].primary == "60% left")
    #expect(homeLines(row.other)[0].primary == "40% left")
    #expect(homeHeadings(windows: windows) == HomeColumnHeadings(session: "5-hour", weekly: "Weekly", other: "5-hour · Spark"))
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

@Test @MainActor
func inactiveQuotasDoNotRequestRecovery() {
    let inactive = UsageWindow(id: "inactive", title: "Weekly", utilizationPercent: nil,
                               resetsAt: nil, isActive: false)
    for state in [SnapshotState.available, .authenticationRequired] {
        let snapshot = AccountSnapshot(profileID: homeReadingProfile.id, fetchedAt: homeReadingNow,
                                       windows: [inactive], credits: [], state: state)
        let overview = UsageOverview(profiles: [homeReadingProfile],
                                     snapshots: [homeReadingProfile.id: snapshot], now: homeReadingNow)
        let items = HomeInterfaceFormatting.attentionItems(overview.accounts, now: homeReadingNow)
        #expect(items.isEmpty == (state != .authenticationRequired))
        #expect(items.allSatisfy { $0.text == "Codex work: Sign-in required. Choose Reconnect…" && $0.showsReconnect })
    }
}

@Test @MainActor
func calendarEventsLeadWithTheResetTimeAndShowTheModelOfAScopedWindow() throws {
    let profile = AccountProfile(provider: .claude, label: "Personal", source: .demo, providerEmail: "personal@example.invalid")
    let resetsAt = homeReadingNow.addingTimeInterval(3_600)
    let window = UsageWindow(id: "seven_day_fable", title: "7 days (Fable 5)", utilizationPercent: 83,
                             resetsAt: resetsAt, windowDurationMinutes: 10_080)
    let snapshot = AccountSnapshot(profileID: profile.id, fetchedAt: homeReadingNow, windows: [window], credits: [], state: .available)
    let overview = UsageOverview(profiles: [profile], snapshots: [profile.id: snapshot], now: homeReadingNow)
    let days = UsageCalendarPeriod(mode: .twoWeeks, containing: homeReadingNow).days
    let event = try #require(HomeInterfaceFormatting.calendarEvents(overview.resetEvents, days: days, now: homeReadingNow,
                                                                   calendar: .current).first)
    #expect(event.timeText == resetsAt.formatted(.dateTime.hour().minute()))
    // The model alone stays visible in a narrow day column; the label keeps the full scope.
    #expect(event.scopeText == "Fable 5")
    #expect(event.remainingText == "17% left")
    #expect(event.tone == .warning)
    #expect(event.accessibilityLabel.hasPrefix("Weekly · Fable 5 resets"))
    #expect(event.accessibilityLabel.contains("17% left, Low now"))

    let content = HomeInterfaceFormatting.detailContent(account: overview.accounts[0], now: homeReadingNow, calendar: .current)
    #expect(!content.rows.contains { $0.label == "Earned resets" })
    let row = HomeInterfaceFormatting.rows(for: overview.accounts, now: homeReadingNow, calendar: .current)[0]
    #expect(homeLines(row.earned) == [homeLines(row.earned)[0]])
    #expect(homeLines(row.earned)[0].isQuiet)
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

@MainActor
private func homeHeadings(windows: [UsageWindow]) -> HomeColumnHeadings {
    let snapshot = AccountSnapshot(profileID: homeReadingProfile.id, fetchedAt: homeReadingNow,
                                   windows: windows, credits: [], state: .available)
    let overview = UsageOverview(profiles: [homeReadingProfile],
                                 snapshots: [homeReadingProfile.id: snapshot], now: homeReadingNow)
    return HomeInterfaceFormatting.headings(for: overview.accounts)
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
