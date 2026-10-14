import AppKit
import Testing
import UsageCore
@testable import AIUsageStats

@Test @MainActor
func calendarEventReceivesPointerHitsInItsParentCoordinates() throws {
    _ = NSApplication.shared
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let profile = AccountProfile(provider: .codex, label: "Work", source: .demo)
    let snapshot = AccountSnapshot(profileID: profile.id, fetchedAt: now,
                                   windows: [UsageWindow(id: "primary", title: "5 hours", utilizationPercent: 20,
                                                         resetsAt: now.addingTimeInterval(3_600))], credits: [], state: .available)
    let overview = UsageOverview(profiles: [profile], snapshots: [profile.id: snapshot], now: now)
    let event = try #require(overview.resetEvents.first)
    let calendar = Calendar(identifier: .gregorian)
    let view = UsageCalendarView(frame: NSRect(x: 20, y: 20, width: 1_000, height: 400))
    view.apply(period: UsageCalendarPeriod(mode: .twoWeeks, containing: now, calendar: calendar),
               events: overview.resetEvents, mode: .twoWeeks, anchor: now, now: now, calendar: calendar)
    let button = try #require(view.eventView(for: event.id) as? NSButton)
    #expect(button.frame.origin != .zero)
    let pointInParent = NSPoint(x: button.frame.midX, y: button.frame.midY)
    #expect(button.hitTest(pointInParent) === button)
    #expect(button.hitTest(NSPoint(x: button.frame.maxX + 1, y: button.frame.maxY + 1)) == nil)
    var activated: String?
    view.onActivate = { activated = $0 }
    button.performClick(nil)
    #expect(activated == event.id)
}
