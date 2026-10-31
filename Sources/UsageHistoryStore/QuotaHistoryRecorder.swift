import Foundation
import GRDB
import UsageHistory

extension HistoryDatabase {
    @discardableResult
    public func recordQuotaReadings(_ readings: [QuotaReading]) throws -> Int {
        guard !readings.isEmpty else { return 0 }
        return try pool.write { db in
            var latest: [QuotaReadingOwner: Date?] = [:]
            var added = 0
            for reading in readings {
                let owner = QuotaReadingOwner(accountID: reading.accountID, source: reading.source)
                if latest[owner] == nil {
                    latest[owner] = try Date.fetchOne(db, sql: """
                        SELECT MAX(observedAt) FROM quotaReading WHERE accountID = ? AND source = ?
                        """, arguments: [reading.accountID, reading.source.rawValue])
                }
                if let previous = latest[owner] ?? nil, reading.observedAt <= previous { continue }
                try reading.insert(db)
                added += db.changesCount
            }
            return added
        }
    }
}

private struct QuotaReadingOwner: Hashable {
    let accountID: UUID
    let source: QuotaReadingSource
}
