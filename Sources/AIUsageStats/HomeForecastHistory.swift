import Foundation
import GRDB
import UsageCore
import UsageHistory
import UsageHistoryStore

/// Recorded quota readings for the Home forecast. The database is observed off the main thread; each committed change
/// delivers a fresh list on the main actor. The demonstration supplies generated readings in memory.
@MainActor
final class HomeForecastHistory {
    enum Source {
        case database(HistoryDatabase)
        case demonstration
        case unavailable(String)
    }

    /// The longest range plus one weekly window and a day: a change-only reading holds its value until its reset,
    /// at most a week later, so a reading that old can still reach into the range.
    nonisolated static let observedSpan: TimeInterval = 15 * 86_400

    var onChange: (() -> Void)?
    private(set) var readings: [QuotaReading] = []
    /// Why history cannot be shown at all, or nil.
    private(set) var unavailableReason: String?
    private let source: Source
    private var observation: AnyDatabaseCancellable?
    private var lowerBound = Date.distantPast

    init(source: Source) {
        self.source = source
        if case .unavailable(let reason) = source { unavailableReason = reason }
    }

    /// Starts the observation, or moves it once its lower bound is a day older than needed. The demonstration
    /// generates its readings once, from the first loaded accounts.
    func observe(now: Date, profiles: [AccountProfile], snapshots: [UUID: AccountSnapshot]) {
        switch source {
        case .database(let database):
            guard observation == nil || now.timeIntervalSince(lowerBound) > Self.observedSpan + 86_400 else { return }
            let bound = now.addingTimeInterval(-Self.observedSpan)
            lowerBound = bound
            observation = ValueObservation
                .tracking { db in try QuotaReading.filter(Column("observedAt") >= bound).fetchAll(db) }
                .start(in: database.pool, onError: { [weak self] error in
                    self?.unavailableReason = "Could not read the quota history: \(error.localizedDescription)"
                    self?.onChange?()
                }, onChange: { [weak self] readings in
                    self?.readings = readings
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
