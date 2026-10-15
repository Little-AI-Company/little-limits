import Foundation
import Testing
@testable import UsageCore

private let now = Date(timeIntervalSince1970: 1_000_000)
private let hour: TimeInterval = 3_600
private let day: TimeInterval = 86_400

private func window(_ id: String, title: String? = nil, used: Double?, resetsIn: TimeInterval? = day,
                    minutes: Int? = nil) -> UsageWindow {
    UsageWindow(id: id, title: title ?? id, utilizationPercent: used, resetsAt: resetsIn.map { now.addingTimeInterval($0) },
                windowDurationMinutes: minutes)
}

private func account(_ provider: Provider, _ windows: [UsageWindow]?, state: SnapshotState = .available,
                     readAgo: TimeInterval = 60) -> (AccountProfile, AccountSnapshot?) {
    let profile = AccountProfile(provider: provider, label: "Account", source: .demo)
    let snapshot = windows.map {
        AccountSnapshot(profileID: profile.id, fetchedAt: now.addingTimeInterval(-readAgo), windows: $0, state: state)
    }
    return (profile, snapshot)
}

private func overview(_ entries: [(AccountProfile, AccountSnapshot?)]) -> UsageOverview {
    UsageOverview(profiles: entries.map(\.0),
                  snapshots: Dictionary(uniqueKeysWithValues: entries.compactMap { entry in entry.1.map { (entry.0.id, $0) } }),
                  now: now)
}

@Test func weeklyTotalCountsOnlyCurrentMeasuredReadingsAndKeepsProvidersSeparate() {
    let current = account(.claude, [window("seven_day", used: 10)])
    let exhausted = account(.claude, [window("seven_day", used: 100)])
    let stale = account(.claude, [window("seven_day", used: 0)], readAgo: 600)
    let signedOut = account(.claude, [window("seven_day", used: 0)], state: .authenticationRequired)
    let unmeasured = account(.claude, [window("seven_day", used: nil)])
    let neverRead = account(.claude, nil)
    let codex = account(.codex, [window("codex_secondary", title: "7 days", used: 40, minutes: 10_080)])
    let result = overview([current, exhausted, stale, signedOut, unmeasured, neverRead, codex])

    let claude = result.providers[0].weekly
    #expect(claude.remainingPercent == 90)
    #expect(claude.capacityPercent == 200)
    #expect(claude.countedAccountIDs == [current.0.id, exhausted.0.id])
    #expect(claude.unknownAccountIDs == [stale.0.id, signedOut.0.id, unmeasured.0.id, neverRead.0.id])
    #expect(result.providers[1].weekly.remainingPercent == 60)
    #expect(result.providers[1].weekly.capacityPercent == 100)

    // No current reading is an unknown total, not 0%.
    let unknown = overview([stale, neverRead]).providers[0].weekly
    #expect(unknown.remainingPercent == nil)
    #expect(unknown.unknownAccountIDs.count == 2)
}

@Test func scopedWeeklyTotalCoversOnlyAccountsReportingThatModel() {
    let personal = account(.claude, [window("seven_day", used: 20), window("seven_day_fable_5", title: "7 days (Fable 5)", used: 16)])
    let stale = account(.claude, [window("seven_day", used: 20), window("seven_day_fable_5", title: "7 days (Fable 5)", used: 0)],
                        readAgo: 600)
    let withoutModel = account(.claude, [window("seven_day", used: 20)])
    let pools = overview([personal, stale, withoutModel]).providers[0].scopedWeekly
    #expect(pools.count == 1)
    #expect(pools[0].scopeName == "Fable 5")
    #expect(pools[0].remainingPercent == 84)
    #expect(pools[0].countedAccountIDs == [personal.0.id])
    #expect(pools[0].unknownAccountIDs == [stale.0.id])
}

@Test func nextResetIsTheEarliestResetThatReturnsQuota() {
    let unused = account(.claude, [window("seven_day", used: 0, resetsIn: hour)])
    let later = account(.claude, [window("seven_day", used: 76, resetsIn: 2 * day)])
    let first = account(.claude, [window("seven_day", used: 24, resetsIn: day)])
    let sameTime = account(.claude, [window("seven_day", used: 10, resetsIn: day)])
    let stale = account(.claude, [window("seven_day", used: 90, resetsIn: hour)], readAgo: 600)
    let reset = overview([unused, later, first, sameTime, stale]).providers[0].nextReset
    #expect(reset == .reset(QuotaReset(resetsAt: now.addingTimeInterval(day), gainPercent: 34,
                                       accountIDs: [first.0.id, sameTime.0.id])))
    #expect(overview([unused]).providers[0].nextReset == .nonePending)
    #expect(overview([account(.claude, [window("seven_day", used: 30, resetsIn: nil)])]).providers[0].nextReset == .unknown)
    #expect(overview([stale]).providers[0].nextReset == .unknown)
}

@Test func exhaustedAccountIsUsableAtTheLatestResetOfItsFullWindows() {
    func usability(_ windows: [UsageWindow], readAgo: TimeInterval = 60) -> AccountUsability {
        AccountUsability(snapshot: account(.claude, windows, readAgo: readAgo).1, now: now)
    }
    #expect(usability([window("five_hour", used: 100, resetsIn: hour), window("seven_day", used: 100, resetsIn: 3 * day),
                       window("seven_day_fable_5", title: "7 days (Fable 5)", used: 50, resetsIn: 5 * day)])
            == .exhausted(usableAt: now.addingTimeInterval(3 * day)))
    #expect(usability([window("five_hour", used: 100, resetsIn: nil), window("seven_day", used: 100)]) == .exhausted(usableAt: nil))
    #expect(usability([window("five_hour", used: 99), window("seven_day", used: 40)]) == .usable)
    #expect(usability([window("five_hour", used: 100)], readAgo: 600) == .unknown)
}

@Test func paceComparesUseWithTheElapsedShareOfTheWindow() {
    // Half of a 7-day window has elapsed. Claude's `seven_day` reports no duration; its identifier establishes it.
    let halfway = 3.5 * day
    #expect(QuotaPace(window: window("seven_day", used: 70, resetsIn: halfway), now: now)?.verdict == .ahead)
    #expect(QuotaPace(window: window("seven_day", used: 52, resetsIn: halfway), now: now)?.verdict == .onPace)
    #expect(QuotaPace(window: window("seven_day", used: 20, resetsIn: halfway), now: now)?.verdict == .under)
    #expect(QuotaPace(window: window("codex_secondary", title: "7 days", used: 50, resetsIn: halfway, minutes: 10_080),
                      now: now)?.elapsedPercent == 50)
    // Unknown length, unknown reset, and a reset beyond the window length have no pace.
    #expect(QuotaPace(window: window("limit_0_custom", title: "custom", used: 50, resetsIn: halfway), now: now) == nil)
    #expect(QuotaPace(window: window("seven_day", used: 50, resetsIn: nil), now: now) == nil)
    #expect(QuotaPace(window: window("five_hour", used: 50, resetsIn: 6 * hour), now: now) == nil)
}

@Test func soonestUsableOrderKeepsSavedOrderForTies() {
    let first = account(.claude, [window("seven_day", used: 10)])
    let exhaustedLater = account(.claude, [window("seven_day", used: 100, resetsIn: 2 * day)])
    let unknown = account(.claude, nil)
    let exhaustedSooner = account(.codex, [window("primary", title: "5 hours", used: 100, resetsIn: hour, minutes: 300)])
    let second = account(.codex, [window("primary", title: "5 hours", used: 90, resetsIn: hour, minutes: 300)])
    let accounts = overview([first, exhaustedLater, unknown, exhaustedSooner, second]).accounts
    #expect(AccountSortOrder.soonestUsable.sorted(accounts, now: now).map(\.id)
            == [first.0.id, second.0.id, exhaustedSooner.0.id, exhaustedLater.0.id, unknown.0.id])
    #expect(AccountSortOrder.mostRemaining.sorted(accounts, now: now).map(\.id)
            == [first.0.id, second.0.id, exhaustedLater.0.id, exhaustedSooner.0.id, unknown.0.id])
}
