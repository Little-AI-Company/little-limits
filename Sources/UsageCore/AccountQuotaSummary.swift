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
}
