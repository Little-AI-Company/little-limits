import Foundation
import UsageCore
import UsageHistory

enum HomeForecastDemonstration {
    static func readings(profiles: [AccountProfile], snapshots: [UUID: AccountSnapshot], now: Date,
                         calendar: Calendar = .current) -> [QuotaReading] {
        let step = QuotaForecast.polledRefreshInterval
        let week: TimeInterval = 7 * 86_400
        let latest = now.addingTimeInterval(-60)
        let closed = now.addingTimeInterval(-30 * 3_600)...now.addingTimeInterval(-22 * 3_600)
        let count = Int(8 * 86_400 / step)
        let dates = (0...count).reversed().map { latest.addingTimeInterval(-Double($0) * step) }
        var active: [Double] = []
        var total = 0.0
        for (index, date) in dates.enumerated() {
            if index > 0, (9..<23).contains(calendar.component(.hour, from: date)) { total += step / 3_600 }
            active.append(total)
        }
        func activeHours(at date: Date) -> Double {
            let index = Int((date.timeIntervalSince(dates[0]) / step).rounded())
            return active[min(active.count - 1, max(0, index))]
        }

        var readings: [QuotaReading] = []
        for profile in profiles {
            guard let snapshot = snapshots[profile.id],
                  let window = snapshot.windows.first(where: { $0.isActive != false && $0.role == .weekly }),
                  let used = window.utilizationPercent, let resetsAt = window.resetsAt else { continue }
            let provider: HistoryProvider = profile.provider == .claude ? .claude : .codex
            let source: QuotaReadingSource = profile.provider == .claude ? .claudeOAuth : .codexAppServer
            let start = resetsAt.addingTimeInterval(-week)
            let atStart = activeHours(at: start)
            let currentSpan = activeHours(at: latest) - atStart
            for date in dates where !closed.contains(date) {
                let inCurrent = date >= start
                let value = inCurrent
                    ? (currentSpan > 0 ? used * (activeHours(at: date) - atStart) / currentSpan : used)
                    : (atStart > 0 ? 70 * activeHours(at: date) / atStart : 70)
                readings.append(QuotaReading(provider: provider, accountID: profile.id, windowID: window.id,
                                             usedPercent: min(100, max(0, value)), resetsAt: inCurrent ? resetsAt : start,
                                             windowDurationMinutes: window.windowDurationMinutes,
                                             observedAt: date, source: source))
            }
        }
        return readings
    }
}
