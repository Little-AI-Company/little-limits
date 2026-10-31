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
        guard AccountSnapshot.isObservationCurrent(fetchedAt, now: now),
              !windows.contains(where: { $0.resetsAt.map { $0 <= now } == true }) else { self = .stale; return }
        guard !windows.isEmpty else { self = .inactive; return }
        guard windows.allSatisfy({ $0.utilizationPercent?.isFinite == true }),
              let limiting = windows.max(by: { ($0.utilizationPercent ?? 0) < ($1.utilizationPercent ?? 0) }),
              let used = limiting.utilizationPercent else { self = .unknown; return }
        let remaining = 100 - used
        self = .available(remainingPercent: remaining,
                          severity: remaining > RemainingPercentText.lowRemainingThreshold ? .normal : remaining >= 10 ? .warning : .critical,
                          windowTitle: limiting.title)
    }

    private static func generalMeasuredWindows(_ snapshot: AccountSnapshot) -> [(remainingPercent: Double, title: String)] {
        snapshot.currentWindows.compactMap { window in
            guard window.role == .session || window.role == .weekly,
                  let used = window.utilizationPercent, used.isFinite else { return nil }
            return (100 - used, window.title)
        }
    }

    public static func lowestCurrent(accountIDs: [UUID], snapshots: [UUID: AccountSnapshot], now: Date = Date())
        -> (accountID: UUID, remainingPercent: Double, windowTitle: String)? {
        var lowest: (accountID: UUID, remainingPercent: Double, windowTitle: String)?
        for id in accountIDs {
            guard let snapshot = snapshots[id] else { continue }
            guard case .available = AccountQuotaSummary(snapshot: snapshot.generalWindowsOnly, accountID: id, now: now) else { continue }
            for window in generalMeasuredWindows(snapshot) where window.remainingPercent < lowest?.remainingPercent ?? .infinity {
                lowest = (id, window.remainingPercent, window.title)
            }
        }
        return lowest
    }

    public static func lowestLastKnown(accountIDs: [UUID], snapshots: [UUID: AccountSnapshot], now: Date = Date())
        -> (accountID: UUID, remainingPercent: Double, windowTitle: String)? {
        var lowest: (accountID: UUID, remainingPercent: Double, windowTitle: String)?
        for id in accountIDs {
            guard let snapshot = snapshots[id], snapshot.profileID == id,
                  let fetchedAt = snapshot.fetchedAt, fetchedAt <= now else { continue }
            for window in generalMeasuredWindows(snapshot) where window.remainingPercent < lowest?.remainingPercent ?? .infinity {
                lowest = (id, window.remainingPercent, window.title)
            }
        }
        return lowest
    }
}

extension AccountSnapshot {
    public var generalWindowsOnly: AccountSnapshot {
        AccountSnapshot(profileID: profileID, fetchedAt: fetchedAt,
                        windows: windows.filter { $0.role == .session || $0.role == .weekly }, state: state)
    }
}
