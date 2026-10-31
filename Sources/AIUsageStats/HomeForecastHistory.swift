import Foundation
import GRDB
import UsageCore
import UsageHistory
import UsageHistoryStore

@MainActor
final class HomeForecastHistory {
    enum Source {
        case database(HistoryDatabase)
        case demonstration
        case unavailable(String)
    }

    nonisolated static let observedSpan: TimeInterval = 15 * 86_400

    var onChange: (() -> Void)?
    private(set) var readings: [QuotaReading] = []
    private(set) var latestReadings: [QuotaReading] = []
    private(set) var unavailableReason: String?
    private let source: Source
    private var observation: AnyDatabaseCancellable?
    private var lowerBound = Date.distantPast

    init(source: Source) {
        self.source = source
        if case .unavailable(let reason) = source { unavailableReason = reason }
    }

    func observe(now: Date, profiles: [AccountProfile], snapshots: [UUID: AccountSnapshot]) {
        switch source {
        case .database(let database):
            guard observation == nil || now.timeIntervalSince(lowerBound) > Self.observedSpan + 86_400 else { return }
            let bound = now.addingTimeInterval(-Self.observedSpan)
            lowerBound = bound
            observation = ValueObservation
                .tracking { db in
                    ObservedHistory(
                        readings: try QuotaReading.filter(Column("observedAt") >= bound).fetchAll(db),
                        latestReadings: try QuotaReading.fetchAll(db, sql: """
                            SELECT provider, accountID, windowID, usedPercent, resetsAt, windowDurationMinutes,
                                   MAX(observedAt) AS observedAt, source
                            FROM quotaReading GROUP BY accountID
                            """))
                }
                .start(in: database.pool, onError: { [weak self] error in
                    self?.unavailableReason = "Could not read the quota history: \(error.localizedDescription)"
                    self?.onChange?()
                }, onChange: { [weak self] observed in
                    self?.readings = observed.readings
                    self?.latestReadings = observed.latestReadings
                    self?.unavailableReason = nil
                    self?.onChange?()
                })
        case .demonstration:
            guard readings.isEmpty, !snapshots.isEmpty else { return }
            readings = HomeForecastDemonstration.readings(profiles: profiles, snapshots: snapshots, now: now)
        case .unavailable:
            break
        }
    }
}

private struct ObservedHistory: Sendable {
    let readings: [QuotaReading]
    let latestReadings: [QuotaReading]
}
