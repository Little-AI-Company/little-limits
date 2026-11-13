import Foundation
import UsageCore

@MainActor
final class MorningDigest {
    struct Preferences: Equatable {
        var isEnabled = false
        var minutesAfterMidnight = 8 * 60
        var weekdaysOnly = false
    }

    static let catchUpWindow: TimeInterval = 4 * 3_600
    static let refreshTimeout: Duration = .seconds(60)
    private static let enabledKey = "MorningDigestEnabled"
    private static let minutesKey = "MorningDigestMinutes"
    private static let weekdaysKey = "MorningDigestWeekdaysOnly"
    private static let lastDayKey = "MorningDigestLastDay"

    private let model: ApplicationModel
    private let notifications: LocalNotifications
    private let defaults: UserDefaults?
    private var lastDay: String?
    private var timer: Timer?
    private var isPosting = false
    var onPermissionChange: (() -> Void)?
    private(set) var preferences: Preferences
    var permission: LocalNotifications.Permission { notifications.permission }

    init(model: ApplicationModel, notifications: LocalNotifications) {
        self.model = model
        self.notifications = notifications
        defaults = model.isDemo ? nil : .standard
        var preferences = Preferences()
        if let defaults {
            preferences.isEnabled = defaults.bool(forKey: Self.enabledKey)
            if let minutes = defaults.object(forKey: Self.minutesKey) as? Int, (0..<1_440).contains(minutes) {
                preferences.minutesAfterMidnight = minutes
            }
            preferences.weekdaysOnly = defaults.bool(forKey: Self.weekdaysKey)
            lastDay = defaults.string(forKey: Self.lastDayKey)
        }
        self.preferences = preferences
    }

    func update(_ preferences: Preferences) {
        let enabling = preferences.isEnabled && !self.preferences.isEnabled
        self.preferences = preferences
        defaults?.set(preferences.isEnabled, forKey: Self.enabledKey)
        defaults?.set(preferences.minutesAfterMidnight, forKey: Self.minutesKey)
        defaults?.set(preferences.weekdaysOnly, forKey: Self.weekdaysKey)
        if enabling { Task { _ = await notifications.requestPermission(); onPermissionChange?() } }
        check()
    }

    func check(now: Date = Date(), calendar: Calendar = .current) {
        timer?.invalidate()
        timer = nil
        guard preferences.isEnabled else { return }
        if !isPosting, let due = dueTime(on: now, calendar: calendar), now >= due,
           now < due.addingTimeInterval(Self.catchUpWindow), lastDay != Self.dayKey(now, calendar: calendar) {
            post(due: due, now: now, calendar: calendar)
        }
        guard let next = nextDue(after: now, calendar: calendar) else { return }
        let timer = Timer(fire: next, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func post(due: Date, now: Date, calendar: Calendar) {
        isPosting = true
        let day = Self.dayKey(now, calendar: calendar)
        let missed = now.timeIntervalSince(due) > 10 * 60 ? due : nil
        Task {
            await model.refreshAndWait(timeout: Self.refreshTimeout)
            let sent = Date()
            let digest = LimitsDigest(overview: UsageOverview(profiles: model.profiles, snapshots: model.snapshots, now: sent),
                                      now: sent, calendar: calendar)
            let notice = LimitsDigestText.morningDigest(digest, now: sent, calendar: calendar, missed: missed)
            if await notifications.post(identifier: "morning-digest-\(Self.dayKey(sent, calendar: calendar))",
                                        title: notice.title, body: notice.body) {
                lastDay = day
                defaults?.set(day, forKey: Self.lastDayKey)
            }
            isPosting = false
        }
    }

    private func dueTime(on date: Date, calendar: Calendar) -> Date? {
        if preferences.weekdaysOnly, calendar.isDateInWeekend(date) { return nil }
        return calendar.date(byAdding: .minute, value: preferences.minutesAfterMidnight, to: calendar.startOfDay(for: date))
    }

    private func nextDue(after now: Date, calendar: Calendar) -> Date? {
        for offset in 0..<8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let due = dueTime(on: day, calendar: calendar), due > now,
                  lastDay != Self.dayKey(due, calendar: calendar) else { continue }
            return due
        }
        return nil
    }

    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
