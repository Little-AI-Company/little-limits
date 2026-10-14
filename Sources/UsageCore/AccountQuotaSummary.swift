import Foundation

public enum AccountQuotaSummary: Sendable, Equatable {
    public enum Severity: Sendable, Equatable { case normal, warning, critical }

    case available(remainingPercent: Double, severity: Severity, windowTitle: String)
    case unknown
    case inactive
    case stale
    case unavailable
    case authenticationRequired

    public init(snapshot: AccountSnapshot?, accountID: UUID, now: Date = Date()) {
        guard let snapshot, snapshot.profileID == accountID else { self = .unknown; return }
        switch snapshot.state {
        case .stale: self = .stale; return
        case .unavailable: self = .unavailable; return
        case .authenticationRequired: self = .authenticationRequired; return
        case .available: break
        }
        let windows = snapshot.currentWindows
        guard !snapshot.windows.isEmpty else { self = .unknown; return }
        guard let fetchedAt = snapshot.fetchedAt, fetchedAt <= now else { self = .unknown; return }
        // Match the five-minute freshness limit in the account detail and refresh checks.
        guard now.timeIntervalSince(fetchedAt) < 300,
              !windows.contains(where: { $0.resetsAt.map { $0 <= now } == true }) else { self = .stale; return }
        guard !windows.isEmpty else { self = .inactive; return }
        guard windows.allSatisfy({ $0.utilizationPercent?.isFinite == true }),
              let limiting = windows.max(by: { ($0.utilizationPercent ?? 0) < ($1.utilizationPercent ?? 0) }),
              let used = limiting.utilizationPercent else { self = .unknown; return }
        let remaining = 100 - used
        self = .available(remainingPercent: remaining,
                          severity: remaining > 20 ? .normal : remaining >= 10 ? .warning : .critical,
                          windowTitle: limiting.title)
    }

    /// The account and window with the lowest remaining quota among current readings, in stored account order
    /// for ties. Stale, sign-in-required, unavailable, inactive, and unknown readings are excluded, so an old
    /// value never stands for the provider. Nil when no account has a current reading.
    public static func lowestCurrent(accountIDs: [UUID], snapshots: [UUID: AccountSnapshot], now: Date = Date())
        -> (accountID: UUID, remainingPercent: Double, windowTitle: String)? {
        var lowest: (accountID: UUID, remainingPercent: Double, windowTitle: String)?
        for id in accountIDs {
            guard case let .available(remaining, _, title) = AccountQuotaSummary(snapshot: snapshots[id], accountID: id, now: now),
                  remaining < lowest?.remainingPercent ?? .infinity else { continue }
            lowest = (id, remaining, title)
        }
        return lowest
    }

    /// The account and window with the lowest last known remaining quota, from any reading with a trustworthy
    /// observation time: stale, sign-in required, older than five minutes, or past a reset. The status item shows
    /// it, with its stale mark, only when `lowestCurrent` is nil. Nil when no account was ever measured.
    public static func lowestLastKnown(accountIDs: [UUID], snapshots: [UUID: AccountSnapshot], now: Date = Date())
        -> (accountID: UUID, remainingPercent: Double, windowTitle: String)? {
        var lowest: (accountID: UUID, remainingPercent: Double, windowTitle: String)?
        for id in accountIDs {
            guard let snapshot = snapshots[id], snapshot.profileID == id,
                  let fetchedAt = snapshot.fetchedAt, fetchedAt <= now else { continue }
            for window in snapshot.windows where window.isActive != false {
                guard let used = window.utilizationPercent, used.isFinite,
                      100 - used < lowest?.remainingPercent ?? .infinity else { continue }
                lowest = (id, 100 - used, window.title)
            }
        }
        return lowest
    }
}
