import Foundation
import Testing
@testable import UsageCore

private let observationDate = Date(timeIntervalSince1970: 1_000)
private let accountID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

private func quotaWindow(_ id: String, used: Double?, active: Bool? = nil, reset: Date? = nil) -> UsageWindow {
    UsageWindow(id: id, title: id, utilizationPercent: used,
                resetsAt: reset ?? observationDate.addingTimeInterval(3_600), isActive: active)
}

private func quotaSnapshot(_ windows: [UsageWindow], state: SnapshotState = .available,
                           fetchedAt: Date? = observationDate, profileID: UUID = accountID,
                           credits: [CreditBalance] = []) -> AccountSnapshot {
    AccountSnapshot(profileID: profileID, fetchedAt: fetchedAt, windows: windows, credits: credits, state: state)
}

private func generalWindow(_ id: String, used: Double?, active: Bool? = nil) -> UsageWindow {
    quotaWindow(id, used: used, active: active)
}

private func modelWindow(used: Double) -> UsageWindow {
    UsageWindow(id: "limit_fable_weekly", title: "7 days (Fable 5)", utilizationPercent: used,
                resetsAt: observationDate.addingTimeInterval(3_600), windowDurationMinutes: 10_080)
}

@Test(arguments: [(79.0, AccountQuotaSummary.Severity.normal), (80.0, .warning),
                  (90.0, .warning), (90.1, .critical), (100.0, .critical), (0.0, .normal)])
func quotaSummaryUsesRemainingThresholds(_ used: Double, _ severity: AccountQuotaSummary.Severity) {
    let summary = AccountQuotaSummary(snapshot: quotaSnapshot([quotaWindow("quota", used: used)]),
                                      accountID: accountID, now: observationDate)
    #expect(summary == .available(remainingPercent: 100 - used, severity: severity, windowTitle: "quota"))
}

@Test func quotaSummaryUsesLowestCurrentRemainingAndExcludesInactiveWindows() {
    let summary = AccountQuotaSummary(snapshot: quotaSnapshot([
        quotaWindow("session", used: 20), quotaWindow("weekly", used: 85, active: true),
        quotaWindow("inactive", used: 100, active: false)
    ]), accountID: accountID, now: observationDate)
    #expect(summary == .available(remainingPercent: 15, severity: .warning, windowTitle: "weekly"))
}

@Test(arguments: [Double?.none, .some(.nan), .some(.infinity)])
func quotaSummaryPreservesUnknownCurrentValues(_ percent: Double?) {
    let summary = AccountQuotaSummary(snapshot: quotaSnapshot([
        quotaWindow("known", used: 20), quotaWindow("unknown", used: percent)
    ]), accountID: accountID, now: observationDate)
    #expect(summary == .unknown)
}

@Test func quotaSummaryDistinguishesMissingUnknownAndInactiveReadings() {
    #expect(AccountQuotaSummary(snapshot: nil, accountID: accountID, now: observationDate) == .unknown)
    #expect(AccountQuotaSummary(snapshot: quotaSnapshot([]), accountID: accountID, now: observationDate) == .unknown)
    #expect(AccountQuotaSummary(snapshot: quotaSnapshot([quotaWindow("inactive", used: 40, active: false)]),
                                accountID: accountID, now: observationDate) == .inactive)
    #expect(AccountQuotaSummary(snapshot: quotaSnapshot([quotaWindow("inactive", used: 40, active: false)], fetchedAt: nil),
                                accountID: accountID, now: observationDate) == .unknown)
    #expect(AccountQuotaSummary(snapshot: quotaSnapshot([quotaWindow("inactive", used: 40, active: false)]),
                                accountID: accountID, now: observationDate.addingTimeInterval(300)) == .stale)
    #expect(AccountQuotaSummary(snapshot: quotaSnapshot([quotaWindow("quota", used: 40)], fetchedAt: nil),
                                accountID: accountID, now: observationDate) == .unknown)
    #expect(AccountQuotaSummary(snapshot: quotaSnapshot([quotaWindow("quota", used: 40)], fetchedAt: observationDate.addingTimeInterval(1)),
                                accountID: accountID, now: observationDate) == .unknown)
}

@Test func quotaSummaryExpiresAtFiveMinutesAndAtReset() {
    let snapshot = quotaSnapshot([quotaWindow("quota", used: 40)])
    #expect(AccountQuotaSummary(snapshot: snapshot, accountID: accountID,
                                now: observationDate.addingTimeInterval(299)) == .available(remainingPercent: 60, severity: .normal, windowTitle: "quota"))
    #expect(AccountQuotaSummary(snapshot: snapshot, accountID: accountID,
                                now: observationDate.addingTimeInterval(300)) == .stale)
    #expect(AccountQuotaSummary(snapshot: quotaSnapshot([quotaWindow("quota", used: 40, reset: observationDate)]),
                                accountID: accountID, now: observationDate) == .stale)
    #expect(AccountQuotaSummary(snapshot: quotaSnapshot([quotaWindow("quota", used: 40),
                                                        quotaWindow("inactive", used: 100, active: false, reset: observationDate)]),
                                accountID: accountID, now: observationDate) == .available(remainingPercent: 60, severity: .normal, windowTitle: "quota"))
}

@Test(arguments: [(SnapshotState.stale, AccountQuotaSummary.stale), (.unavailable, .unavailable),
                  (.authenticationRequired, .authenticationRequired)])
func quotaSummaryDoesNotPresentRetainedFailedReadings(_ state: SnapshotState, _ expected: AccountQuotaSummary) {
    #expect(AccountQuotaSummary(snapshot: quotaSnapshot([quotaWindow("quota", used: 100)], state: state),
                                accountID: accountID, now: observationDate) == expected)
}

@Test func quotaSummaryRejectsAnotherAccountSnapshot() {
    #expect(AccountQuotaSummary(snapshot: quotaSnapshot([quotaWindow("quota", used: 100)], profileID: UUID()),
                                accountID: accountID, now: observationDate) == .unknown)
}

@Test func quotaSummaryIgnoresCreditBalances() {
    let snapshot = quotaSnapshot([quotaWindow("quota", used: 10)], credits: [
        CreditBalance(id: "expired", title: "API credits", amount: 0, expiresAt: observationDate),
        CreditBalance(id: "grant", title: "Monthly grant", amount: 0)
    ])
    #expect(AccountQuotaSummary(snapshot: snapshot, accountID: accountID, now: observationDate)
            == .available(remainingPercent: 90, severity: .normal, windowTitle: "quota"))
}

@Test func lowestCurrentExcludesStaleAndSignInRequiredReadings() {
    let current = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    let stale = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    let signedOut = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    let snapshots = [
        current: quotaSnapshot([generalWindow("five_hour", used: 37), generalWindow("seven_day", used: 83)], profileID: current),
        stale: quotaSnapshot([generalWindow("five_hour", used: 100)], state: .stale, profileID: stale),
        signedOut: quotaSnapshot([generalWindow("five_hour", used: 100)], state: .authenticationRequired, profileID: signedOut)
    ]
    let lowest = AccountQuotaSummary.lowestCurrent(accountIDs: [stale, signedOut, current], snapshots: snapshots, now: observationDate)
    #expect(lowest?.accountID == current)
    #expect(lowest?.remainingPercent == 17)
    #expect(lowest?.windowTitle == "seven_day")
    #expect(AccountQuotaSummary.lowestCurrent(accountIDs: [stale, signedOut], snapshots: snapshots, now: observationDate) == nil)
}

/// MENU-12: with no current reading, the status item falls back to the lowest last known value; `?` remains only
/// for a provider that was never measured or has no trustworthy observation time.
@Test func lowestLastKnownUsesOutdatedReadingsAndSkipsUnmeasuredOnes() {
    let stale = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
    let signedOut = UUID(uuidString: "00000000-0000-0000-0000-000000000004")!
    let untimed = UUID(uuidString: "00000000-0000-0000-0000-000000000005")!
    let snapshots = [
        stale: quotaSnapshot([generalWindow("five_hour", used: 37)], state: .stale, profileID: stale),
        signedOut: quotaSnapshot([generalWindow("seven_day", used: 70), generalWindow("five_hour", used: 99, active: false)],
                                 state: .authenticationRequired, profileID: signedOut),
        untimed: quotaSnapshot([generalWindow("five_hour", used: 100)], fetchedAt: nil, profileID: untimed)
    ]
    let lowest = AccountQuotaSummary.lowestLastKnown(accountIDs: [stale, signedOut, untimed], snapshots: snapshots,
                                                     now: observationDate)
    #expect(lowest?.accountID == signedOut)
    #expect(lowest?.remainingPercent == 30)
    #expect(lowest?.windowTitle == "seven_day")
    #expect(AccountQuotaSummary.lowestLastKnown(accountIDs: [untimed], snapshots: snapshots, now: observationDate) == nil)
    #expect(AccountQuotaSummary.lowestLastKnown(accountIDs: [UUID()], snapshots: snapshots, now: observationDate) == nil)
}

/// MENU-16: a model-scoped limit restricts only that model, so it never drives the status item number.
@Test func lowestReadingsIgnoreModelScopedWindows() {
    let snapshots = [accountID: quotaSnapshot([
        generalWindow("five_hour", used: 1), generalWindow("seven_day", used: 25), modelWindow(used: 49)
    ])]
    let current = AccountQuotaSummary.lowestCurrent(accountIDs: [accountID], snapshots: snapshots, now: observationDate)
    #expect(current?.remainingPercent == 75)
    #expect(current?.windowTitle == "seven_day")
    let lastKnown = AccountQuotaSummary.lowestLastKnown(accountIDs: [accountID], snapshots: snapshots,
                                                        now: observationDate.addingTimeInterval(600))
    #expect(lastKnown?.remainingPercent == 75)
    let modelOnly = [accountID: quotaSnapshot([modelWindow(used: 49)])]
    #expect(AccountQuotaSummary.lowestCurrent(accountIDs: [accountID], snapshots: modelOnly, now: observationDate) == nil)
    #expect(AccountQuotaSummary.lowestLastKnown(accountIDs: [accountID], snapshots: modelOnly, now: observationDate) == nil)
}
