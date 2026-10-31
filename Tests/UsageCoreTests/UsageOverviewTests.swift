import Foundation
import Testing
@testable import UsageCore

@Test func freshKnownWindowsBecomeResetEvents() {
    let profile = overviewProfile("000000000301", email: "person@example.invalid")
    let window = overviewWindow("five_hour", used: 1)
    let result = overview([profile], [overviewSnapshot(profile, windows: [window])])
    #expect(result.accounts.map(\.id) == [profile.id])
    #expect(result.resetEvents.map(\.id) == ["\(profile.id.uuidString)/five_hour"])
    #expect(result.resetEvents.map(\.remainingPercent) == [99.0])
    #expect(result.resetEvents.map(\.resetsAt) == [window.resetsAt])
    #expect(result.resetEvents.map(\.identity) == ["person@example.invalid"])
    #expect(result.resetEvents.map(\.shortIdentity) == ["person"])
    #expect(result.accounts[0].summary == .available(remainingPercent: 99, severity: .normal, windowTitle: "five_hour"))
}

@Test func partialKnownDataKeepsItsKnownEventAndDropsUnknownWindows() {
    let profile = overviewProfile("000000000302", email: "partial@example.invalid")
    let known = overviewWindow("known", used: 25)
    let unknown = overviewWindow("unknown", used: nil)
    let undated = overviewWindow("undated", used: 10, resetAfter: nil)
    let result = overview([profile], [overviewSnapshot(profile, windows: [known, unknown, undated])])
    #expect(result.resetEvents.map(\.window.id) == ["known"])
    #expect(result.resetEvents.map(\.remainingPercent) == [75.0])
    #expect(result.accounts[0].summary == .unknown)
    #expect(result.accounts[0].snapshot?.windows.map(\.utilizationPercent) == [25, nil, 10])
}

@Test func measuredZeroRemainsZeroAndUnknownDoesNotBecomeAnEvent() {
    let zero = overviewProfile("000000000311", email: "zero@example.invalid")
    let missing = overviewProfile("000000000312", email: "missing@example.invalid")
    let invalid = overviewProfile("000000000313", email: "invalid@example.invalid")
    let result = overview([zero, missing, invalid], [
        overviewSnapshot(zero, windows: [overviewWindow("zero", used: 0)]),
        overviewSnapshot(missing, windows: [overviewWindow("missing", used: nil)]),
        overviewSnapshot(invalid, windows: [overviewWindow("invalid", used: .nan)])
    ])
    #expect(result.resetEvents.map(\.accountID) == [zero.id])
    #expect(result.resetEvents.map(\.remainingPercent) == [100.0])
    #expect(result.accounts[1].snapshot?.windows.first?.utilizationPercent == nil)
    #expect(result.accounts[2].snapshot?.windows.first?.utilizationPercent == nil)
    #expect(result.accounts[0].summary == .available(remainingPercent: 100, severity: .normal, windowTitle: "zero"))
    #expect(result.accounts[1].summary == .unknown)
    #expect(result.accounts[2].summary == .unknown)
}

@Test func providerStateAndInactiveWindowsDoNotCreateEvents() {
    let stale = overviewProfile("000000000321", email: "stale@example.invalid")
    let unavailable = overviewProfile("000000000322", email: "unavailable@example.invalid")
    let signedOut = overviewProfile("000000000323", email: "signedout@example.invalid")
    let inactive = overviewProfile("000000000324", email: "inactive@example.invalid")
    let active = overviewProfile("000000000325", email: "active@example.invalid")
    let result = overview([stale, unavailable, signedOut, inactive, active], [
        overviewSnapshot(stale, windows: [overviewWindow("stale", used: 10)], state: .stale),
        overviewSnapshot(unavailable, windows: [overviewWindow("unavailable", used: 10)], state: .unavailable),
        overviewSnapshot(signedOut, windows: [overviewWindow("auth", used: 10)], state: .authenticationRequired),
        overviewSnapshot(inactive, windows: [overviewWindow("retired", used: 90, active: false)]),
        overviewSnapshot(active, windows: [
            overviewWindow("current", used: 10, active: true),
            overviewWindow("retired", used: 100, resetAfter: 0, active: false)
        ])
    ])
    #expect(result.resetEvents.map(\.window.id) == ["current"])
    #expect(result.accounts.map(\.summary) == [
        .stale, .unavailable, .authenticationRequired, .inactive,
        .available(remainingPercent: 90, severity: .normal, windowTitle: "current")
    ])
}

@Test func foreignSnapshotIsNotBound() {
    let profile = overviewProfile("000000000331")
    let foreign = AccountSnapshot(profileID: UUID(), fetchedAt: overviewNow,
                                  windows: [overviewWindow("quota", used: 10)], state: .available)
    let result = UsageOverview(profiles: [profile], snapshots: [profile.id: foreign], now: overviewNow)
    #expect(result.accounts[0].snapshot == nil)
    #expect(result.accounts[0].summary == .unknown)
    #expect(result.resetEvents.isEmpty)
}

@Test func observationAgeAndResetDeadlinesRejectTheWholeAccount() {
    let profile = overviewProfile("000000000341")
    let windows = [overviewWindow("future", used: 15, resetAfter: 7_200), overviewWindow("other", used: 40, resetAfter: 9_000)]
    let fresh = overviewSnapshot(profile, windows: windows)
    #expect(overview([profile], [fresh], now: overviewNow.addingTimeInterval(299)).resetEvents.count == 2)
    let expired = overview([profile], [fresh], now: overviewNow.addingTimeInterval(300))
    #expect(expired.resetEvents.isEmpty)
    #expect(expired.accounts[0].summary == .stale)
    let missing = overview([profile], [overviewSnapshot(profile, windows: windows, fetchedAt: nil)])
    #expect(missing.resetEvents.isEmpty)
    #expect(missing.accounts[0].summary == .unknown)
    let future = overview([profile], [overviewSnapshot(profile, windows: windows, fetchedAt: overviewNow.addingTimeInterval(1))])
    #expect(future.resetEvents.isEmpty)
    #expect(future.accounts[0].summary == .unknown)
    let passed = overview([profile], [overviewSnapshot(profile, windows: [
        overviewWindow("future", used: 15, resetAfter: 7_200),
        overviewWindow("due", used: 40, resetAfter: 0)
    ])])
    #expect(passed.resetEvents.isEmpty)
    #expect(passed.accounts[0].summary == .stale)
}

@Test func creditExpiryDoesNotCreateEvents() {
    let profile = overviewProfile("000000000351")
    let expiry = overviewNow.addingTimeInterval(86_400)
    let credit = CreditBalance(id: "quota_reset_credits", title: "Earned resets", amount: 2, unit: .resets,
                               expiresAt: expiry, asOf: overviewNow)
    let result = overview([profile], [overviewSnapshot(profile, windows: [overviewWindow("quota", used: 10)], credits: [credit])])
    #expect(result.resetEvents.map(\.window.id) == ["quota"])
    #expect(result.resetEvents.map(\.resetsAt) == [overviewNow.addingTimeInterval(3_600)])
    #expect(result.resetEvents.contains { $0.resetsAt == expiry } == false)
}

@Test func equalResetTimesKeepProfileOrderThenWindowOrder() {
    let first = overviewProfile("000000000361", email: "first@example.invalid")
    let second = overviewProfile("000000000362", email: "second@example.invalid")
    let third = overviewProfile("000000000363", email: "third@example.invalid")
    let snapshots = [
        overviewSnapshot(first, windows: [overviewWindow("w1", used: 10, resetAfter: 4_000), overviewWindow("w2", used: 20, resetAfter: 4_000)]),
        overviewSnapshot(second, windows: [overviewWindow("w1", used: 30, resetAfter: 4_000)]),
        overviewSnapshot(third, windows: [overviewWindow("early", used: 5, resetAfter: 1_000)])
    ]
    let forward = overview([first, second, third], snapshots)
    #expect(forward.resetEvents.map(\.accountID) == [third.id, first.id, first.id, second.id])
    #expect(forward.resetEvents.map(\.window.id) == ["early", "w1", "w2", "w1"])
    let reversed = overview([second, first, third], snapshots)
    #expect(reversed.resetEvents.map(\.accountID) == [third.id, second.id, first.id, first.id])
    #expect(reversed.resetEvents.map(\.window.id) == ["early", "w1", "w1", "w2"])
}

@Test func duplicateProviderIdentitiesGetDistinctShortLabelsThatStayStable() {
    let sharedLower = overviewProfile("0000000000a1", provider: .claude, label: "Personal", email: "personal@example.invalid")
    let sharedHigher = overviewProfile("0000000000a2", provider: .claude, label: "Other", email: "personal@example.invalid")
    let savedLower = overviewProfile("0000000000b1", provider: .claude, label: "Shared")
    let savedHigher = overviewProfile("0000000000b2", provider: .claude, label: "Shared")
    let blankLower = overviewProfile("0000000000c1", provider: .claude, label: "")
    let blankHigher = overviewProfile("0000000000c2", provider: .claude, label: "")
    let unverified = overviewProfile("0000000000d1", provider: .claude, label: "Example unverified", email: "   ")
    let aliceA = overviewProfile("0000000000e1", provider: .claude, label: "Alice", email: "alice@a.example")
    let aliceB = overviewProfile("0000000000e2", provider: .claude, label: "Alice", email: "alice@b.example")
    let studio = overviewProfile("0000000000f1", provider: .claude, label: "Studio", email: "studio@example.invalid")
    let codexPersonal = overviewProfile("0000000000a3", provider: .codex, label: "Personal", email: "personal@example.invalid")
    let codexShared = overviewProfile("0000000000b3", provider: .codex, label: "Shared")
    let profiles = [sharedHigher, savedHigher, studio, sharedLower, aliceB, blankHigher, codexPersonal, unverified, aliceA, blankLower, savedLower, codexShared]
    let forward = UsageOverview(profiles: profiles, snapshots: [:], now: overviewNow)
    let refreshed = UsageOverview(profiles: profiles.reversed(), snapshots: [:], now: overviewNow.addingTimeInterval(30))
    let expected = [
        sharedLower.id: "personal 1", sharedHigher.id: "personal 2",
        savedLower.id: "Shared 1", savedHigher.id: "Shared 2",
        blankLower.id: "Account 1", blankHigher.id: "Account 2",
        unverified.id: "Example unverified",
        aliceA.id: "alice@a.example", aliceB.id: "alice@b.example",
        studio.id: "studio", codexPersonal.id: "personal", codexShared.id: "Shared"
    ]
    #expect(shortLabels(forward) == expected)
    #expect(shortLabels(refreshed) == expected)
    #expect(forward.accounts.first { $0.id == sharedHigher.id }?.identity == "personal@example.invalid")
    #expect(forward.accounts.first { $0.id == savedLower.id }?.identity == "Shared")
    #expect(forward.accounts.first { $0.id == savedLower.id }?.profile.providerEmail == nil)
    #expect(forward.accounts.first { $0.id == blankLower.id }?.identity == "Claude Account")
    let numbered = overviewProfile("0000000000a0", provider: .claude, label: "personal 1")
    let crowded = profiles + [numbered]
    let firstCrowd = UsageOverview(profiles: crowded, snapshots: [:], now: overviewNow)
    let secondCrowd = UsageOverview(profiles: crowded.reversed(), snapshots: [:], now: overviewNow.addingTimeInterval(5))
    let claudeLabels = firstCrowd.accounts.filter { $0.profile.provider == .claude }.map(\.shortIdentity)
    #expect(Set(claudeLabels).count == claudeLabels.count)
    #expect(shortLabels(firstCrowd) == shortLabels(secondCrowd))
    #expect(firstCrowd.accounts.first { $0.id == sharedLower.id }?.identity == "personal@example.invalid")
    #expect(firstCrowd.accounts.first { $0.id == numbered.id }?.identity == "personal 1")
}

@Test func calendarPeriodsUseMondayFirstWeeksAndLocalDaylightSavingDays() throws {
    let calendar = pacificCalendar()
    func day(_ year: Int, _ month: Int, _ date: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: date))!
    }
    let octoberWeek = UsageCalendarPeriod(mode: .twoWeeks, containing: day(2026, 10, 13), calendar: calendar)
    #expect(octoberWeek.days.count == 14)
    #expect(octoberWeek.start == day(2026, 10, 12))
    #expect(octoberWeek.days.last == day(2026, 10, 25))
    #expect(octoberWeek.end == day(2026, 10, 26))
    #expect(calendar.component(.weekday, from: octoberWeek.start) == 2)
    let octoberWeekEnd = try #require(octoberWeek.days.last)
    #expect(calendar.component(.weekday, from: octoberWeekEnd) == 1)
    let nextWeek = UsageCalendarPeriod(mode: .twoWeeks, containing: day(2026, 10, 20), calendar: calendar)
    #expect(nextWeek.start == day(2026, 10, 19))
    #expect(octoberWeek.days.allSatisfy { calendar.startOfDay(for: $0) == $0 })
    #expect(try dayInterval(octoberWeek, from: day(2026, 10, 12), calendar: calendar) == 86_400)

    let january = UsageCalendarPeriod(mode: .month, containing: day(2026, 1, 1), calendar: calendar)
    #expect(january.start == day(2025, 12, 29))
    #expect(january.days.last == day(2026, 2, 1))
    #expect(january.end == day(2026, 2, 2))
    #expect(january.days.count == 35)
    let october = UsageCalendarPeriod(mode: .month, containing: day(2026, 10, 1), calendar: calendar)
    #expect(october.start == day(2026, 9, 28))
    #expect(october.days.last == day(2026, 11, 1))
    #expect(october.end == day(2026, 11, 2))
    let september = UsageCalendarPeriod(mode: .month, containing: day(2026, 9, 28), calendar: calendar)
    #expect(september.start == day(2026, 8, 31))
    #expect(september.end == day(2026, 10, 5))
    #expect(september.start != october.start)

    let march = UsageCalendarPeriod(mode: .month, containing: day(2026, 3, 15), calendar: calendar)
    #expect(march.start == day(2026, 2, 23))
    #expect(try dayInterval(march, from: day(2026, 3, 7), calendar: calendar) == 86_400)
    #expect(try dayInterval(march, from: day(2026, 3, 8), calendar: calendar) == 23 * 3_600)
    #expect(try dayInterval(march, from: day(2026, 3, 9), calendar: calendar) == 86_400)
    let november = UsageCalendarPeriod(mode: .month, containing: day(2026, 11, 15), calendar: calendar)
    #expect(try dayInterval(november, from: day(2026, 11, 1), calendar: calendar) == 25 * 3_600)
    let springWeeks = UsageCalendarPeriod(mode: .twoWeeks, containing: day(2026, 3, 8), calendar: calendar)
    #expect(springWeeks.start == day(2026, 3, 2))
    #expect(try dayInterval(springWeeks, from: day(2026, 3, 8), calendar: calendar) == 23 * 3_600)
}

@Test func olderSnapshotsDecodeWithoutNewFieldsAndStillRequireArrays() throws {
    let identifier = "00000000-0000-0000-0000-000000000001"
    let older = """
    {"profileID":"\(identifier)","fetchedAt":1000,"windows":[{"id":"five_hour","title":"5 hours","utilizationPercent":1,"resetsAt":2000}],"credits":[],"state":"available"}
    """
    let decoded = try JSONDecoder().decode(AccountSnapshot.self, from: Data(older.utf8))
    #expect(decoded.planName == nil)
    #expect(decoded.fetchedAt == Date(timeIntervalSinceReferenceDate: 1_000))
    #expect(decoded.windows.first?.windowDurationMinutes == nil)
    #expect(decoded.windows.first?.resetsAt == Date(timeIntervalSinceReferenceDate: 2_000))
    let blankPlan = """
    {"profileID":"\(identifier)","windows":[{"id":"five_hour","title":"5 hours","windowDurationMinutes":300}],"credits":[],"state":"available","planName":"   "}
    """
    let blank = try JSONDecoder().decode(AccountSnapshot.self, from: Data(blankPlan.utf8))
    #expect(blank.planName == nil)
    #expect(blank.windows.first?.windowDurationMinutes == 300)
    let named = AccountSnapshot(profileID: decoded.profileID, fetchedAt: decoded.fetchedAt, windows: [
        UsageWindow(id: "five_hour", title: "5 hours", utilizationPercent: 1, resetsAt: decoded.windows.first?.resetsAt, windowDurationMinutes: 300)
    ], credits: [], state: .available, planName: " Plus ")
    #expect(named.planName == "Plus")
    let restored = try JSONDecoder().decode(AccountSnapshot.self, from: JSONEncoder().encode(named))
    #expect(restored.planName == "Plus")
    #expect(restored.windows.map(\.windowDurationMinutes) == [300])
    let missingWindows = #"{"profileID":"\#(identifier)","credits":[],"state":"available","planName":"Plus"}"#
    let missingCredits = #"{"profileID":"\#(identifier)","windows":[],"state":"available"}"#
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(AccountSnapshot.self, from: Data(missingWindows.utf8)) }
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(AccountSnapshot.self, from: Data(missingCredits.utf8)) }
}

private let overviewNow = Date(timeIntervalSince1970: 1_700_000_000)

private func overviewProfile(_ suffix: String, provider: Provider = .claude, label: String = "Example", email: String? = nil) -> AccountProfile {
    AccountProfile(id: UUID(uuidString: "00000000-0000-0000-0000-\(suffix)")!, provider: provider,
                   label: label, source: .demo, providerEmail: email)
}

private func overviewWindow(_ id: String, used: Double?, resetAfter: TimeInterval? = 3_600, active: Bool? = nil) -> UsageWindow {
    UsageWindow(id: id, title: id, utilizationPercent: used,
                resetsAt: resetAfter.map { overviewNow.addingTimeInterval($0) }, isActive: active)
}

private func overviewSnapshot(_ profile: AccountProfile, windows: [UsageWindow], state: SnapshotState = .available,
                              fetchedAt: Date? = overviewNow, credits: [CreditBalance] = []) -> AccountSnapshot {
    AccountSnapshot(profileID: profile.id, fetchedAt: fetchedAt, windows: windows, credits: credits, state: state)
}

private func overview(_ profiles: [AccountProfile], _ snapshots: [AccountSnapshot], now: Date = overviewNow) -> UsageOverview {
    UsageOverview(profiles: profiles, snapshots: Dictionary(uniqueKeysWithValues: snapshots.map { ($0.profileID, $0) }), now: now)
}

private func shortLabels(_ overview: UsageOverview) -> [UUID: String] {
    Dictionary(uniqueKeysWithValues: overview.accounts.map { ($0.id, $0.shortIdentity) })
}

private func pacificCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.firstWeekday = 1
    return calendar
}

private func dayInterval(_ period: UsageCalendarPeriod, from day: Date, calendar: Calendar) throws -> TimeInterval {
    let start = calendar.startOfDay(for: day)
    let index = try #require(period.days.firstIndex(of: start))
    try #require(index + 1 < period.days.count)
    return period.days[index + 1].timeIntervalSince(period.days[index])
}
