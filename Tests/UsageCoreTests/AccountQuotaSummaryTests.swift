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
        current: quotaSnapshot([quotaWindow("session", used: 37), quotaWindow("weekly", used: 83)], profileID: current),
        stale: quotaSnapshot([quotaWindow("session", used: 100)], state: .stale, profileID: stale),
        signedOut: quotaSnapshot([quotaWindow("session", used: 100)], state: .authenticationRequired, profileID: signedOut)
    ]
    let lowest = AccountQuotaSummary.lowestCurrent(accountIDs: [stale, signedOut, current], snapshots: snapshots, now: observationDate)
    #expect(lowest?.accountID == current)
    #expect(lowest?.remainingPercent == 17)
    #expect(lowest?.windowTitle == "weekly")
    #expect(AccountQuotaSummary.lowestCurrent(accountIDs: [stale, signedOut], snapshots: snapshots, now: observationDate) == nil)
}
