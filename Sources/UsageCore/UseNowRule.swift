import Foundation

public struct UseNowPick: Codable, Sendable, Equatable {
    public enum Outcome: String, Codable, Sendable {
        case picked
        case noneUsable = "none_usable"
        case noAccounts = "no_accounts"
    }

    public let provider: Provider
    public let need: UseNowNeed
    public let outcome: Outcome
    public let account: String?
    public let shortLabel: String?
    public let runnerUp: String?
    public let usableAt: Date?
    public let reason: String
}

public enum UseNowNeed: String, Codable, Sendable, CaseIterable {
    case weekly
    case session
}

public enum UseNowRule {
    public static let minimumPercentLeft: Double = 10
    public static let stepAsideSessionPercent: Double = 25

    private struct Member {
        let identity: String
        let shortIdentity: String
        let isCurrent: Bool
        let usability: AccountUsability
        let weeklyLeft: Double?
        let sessionLeft: Double?
        let weeklyResetsAt: Date?
        let earned: Int
        let earnedIsCurrent: Bool
        let earnedExpiries: [Date]

        init(_ account: UsageOverviewAccount, now: Date) {
            let snapshot = account.snapshot
            let windows = snapshot?.currentWindows ?? []
            let weekly = windows.first { $0.role == .weekly }
            identity = account.identity
            shortIdentity = account.shortIdentity
            isCurrent = snapshot?.isCurrent(at: now) == true
            usability = AccountUsability(snapshot: snapshot, now: now)
            weeklyLeft = weekly?.utilizationPercent.map { 100 - $0 }
            sessionLeft = windows.first { $0.role == .session }?.utilizationPercent.map { 100 - $0 }
            weeklyResetsAt = weekly?.resetsAt
            let credits = snapshot?.credits ?? []
            let summary = credits.first { $0.id == "quota_reset_credits" }
            let grants = credits.filter { credit in
                credit.unit == .resets && credit.id != "quota_reset_credits" && credit.status?.lowercased() == "available"
            }
            let observed = summary?.asOf ?? now
            let expiredSinceRead = grants.contains { $0.expiresAt.map { $0 > observed && $0 <= now } == true }
            earned = summary?.amount.map { $0 > 0 ? NSDecimalNumber(decimal: $0).intValue : 0 } ?? 0
            earnedIsCurrent = isCurrent && !expiredSinceRead
            earnedExpiries = grants.compactMap(\.expiresAt).filter { $0 > now }
        }

        init(_ account: LimitsDigest.Account, now: Date) {
            let quota = account.windows.filter { $0.role == .session || $0.role == .weekly }
            let weekly = account.windows.first { $0.role == .weekly }
            identity = account.label
            shortIdentity = account.shortLabel
            isCurrent = account.state == .current
            usability = isCurrent ? AccountUsability(readings: quota.map { (percentLeft: $0.percentLeft, resetsAt: $0.resetsAt) }) : .unknown
            weeklyLeft = weekly?.percentLeft
            sessionLeft = account.windows.first { $0.role == .session }?.percentLeft
            weeklyResetsAt = weekly?.resetsAt
            let resets = account.earnedResets
            earned = resets.status == .supported ? max(0, resets.count ?? 0) : 0
            earnedIsCurrent = account.hasCurrentEarnedResets
            earnedExpiries = (resets.expiresAt ?? resets.nextExpiresAt.map { [$0] } ?? []).filter { $0 > now }
        }
    }

    private struct Candidate {
        let member: Member
        let offset: Int
        let weeklyLeft: Double
        let sessionLeft: Double
        let hoursToWeeklyReset: Double?
        var perHour: Double? { hoursToWeeklyReset.map { weeklyLeft / max($0, 1.0 / 60) } }
    }

    public static func pick(provider: Provider, accounts: [UsageOverviewAccount], now: Date, calendar: Calendar,
                            need: UseNowNeed = .weekly) -> UseNowPick {
        pick(provider: provider, members: accounts.filter { $0.profile.provider == provider }.map { Member($0, now: now) },
             now: now, calendar: calendar, need: need)
    }

    static func pick(provider: Provider, digestAccounts: [LimitsDigest.Account], now: Date, calendar: Calendar,
                     need: UseNowNeed) -> UseNowPick {
        pick(provider: provider, members: digestAccounts.filter { $0.provider == provider }.map { Member($0, now: now) },
             now: now, calendar: calendar, need: need)
    }

    private static func pick(provider: Provider, members: [Member], now: Date, calendar: Calendar, need: UseNowNeed) -> UseNowPick {
        let name = provider.title
        guard !members.isEmpty else {
            return UseNowPick(provider: provider, need: need, outcome: .noAccounts, account: nil, shortLabel: nil, runnerUp: nil,
                              usableAt: nil, reason: "No \(name) accounts are set up.")
        }
        let candidates = members.enumerated().compactMap { candidate($0.element, offset: $0.offset, now: now) }
        guard !candidates.isEmpty else { return noneUsable(provider: provider, need: need, members: members, now: now, calendar: calendar) }
        let ranked = candidates.sorted { better($0, $1, need: need) }
        var chosen = ranked[0]
        var steppedAside: Candidate?
        if need == .weekly, chosen.sessionLeft < stepAsideSessionPercent,
           let replacement = ranked.dropFirst().first(where: { $0.sessionLeft >= stepAsideSessionPercent }) {
            steppedAside = chosen
            chosen = replacement
        }
        let runnerUp = steppedAside ?? ranked.first { $0.offset != chosen.offset }
        let reason: String
        if let steppedAside {
            reason = "\(steppedAside.member.shortIdentity) goes first for the week, but its 5-hour window has "
                + "\(percent(steppedAside.sessionLeft)) left, so use \(chosen.member.shortIdentity) "
                + "(\(percent(chosen.sessionLeft)) of its 5-hour left) for the next session."
        } else if candidates.count == 1 {
            reason = "\(percent(chosen.weeklyLeft)) of the week left. The only current \(name) account with room."
        } else if need == .session {
            reason = "\(percent(chosen.sessionLeft)) of its 5-hour window left, the most of any current \(name) account."
        } else if let hours = chosen.hoursToWeeklyReset {
            reason = "\(percent(chosen.weeklyLeft)) left and it resets in \(duration(hours: hours)), so that quota goes first."
        } else {
            reason = "\(percent(chosen.weeklyLeft)) of the week left, the most of any current \(name) account. Its reset time is unknown."
        }
        return UseNowPick(provider: provider, need: need, outcome: .picked, account: LimitsDigest.sanitizedLabel(chosen.member.identity),
                          shortLabel: LimitsDigest.sanitizedLabel(chosen.member.shortIdentity),
                          runnerUp: runnerUp.map { LimitsDigest.sanitizedLabel($0.member.shortIdentity) },
                          usableAt: nil, reason: reason)
    }

    private static func candidate(_ member: Member, offset: Int, now: Date) -> Candidate? {
        guard member.isCurrent, member.usability == .usable, let weeklyLeft = member.weeklyLeft else { return nil }
        let sessionLeft = member.sessionLeft ?? 100
        guard weeklyLeft >= minimumPercentLeft, sessionLeft >= minimumPercentLeft else { return nil }
        let hours = member.weeklyResetsAt.flatMap { $0 > now ? $0.timeIntervalSince(now) / 3_600 : nil }
        return Candidate(member: member, offset: offset, weeklyLeft: weeklyLeft, sessionLeft: sessionLeft,
                         hoursToWeeklyReset: hours)
    }

    private static func better(_ lhs: Candidate, _ rhs: Candidate, need: UseNowNeed) -> Bool {
        if need == .session, lhs.sessionLeft != rhs.sessionLeft { return lhs.sessionLeft > rhs.sessionLeft }
        switch (lhs.perHour, rhs.perHour) {
        case let (left?, right?) where left != right: return left > right
        case (.some, nil): return true
        case (nil, .some): return false
        default: break
        }
        if lhs.weeklyLeft != rhs.weeklyLeft { return lhs.weeklyLeft > rhs.weeklyLeft }
        if lhs.sessionLeft != rhs.sessionLeft { return lhs.sessionLeft > rhs.sessionLeft }
        return lhs.offset < rhs.offset
    }

    private static func noneUsable(provider: Provider, need: UseNowNeed, members: [Member], now: Date, calendar: Calendar) -> UseNowPick {
        let soonest = members.compactMap { member -> (member: Member, date: Date)? in
            guard case .exhausted(let date?) = member.usability, date > now else { return nil }
            return (member, date)
        }.min { $0.date < $1.date }
        let current = members.filter { $0.earnedIsCurrent }
        let earned = current.map(\.earned).reduce(0, +)
        let lastKnownEarned = members.filter { !$0.earnedIsCurrent }.map(\.earned).reduce(0, +)
        let firstExpiry = current.filter { $0.earned > 0 }.flatMap(\.earnedExpiries).min()
        var reason = "No current \(provider.title) account has at least \(Int(minimumPercentLeft))% of its week and 5-hour window left."
        if let soonest {
            reason += " \(soonest.member.shortIdentity) is usable \(LimitsDigestText.moment(soonest.date, now: now, calendar: calendar))."
        }
        let notCurrent = members.filter { !$0.isCurrent }.count
        if notCurrent > 0 {
            reason += " \(notCurrent) account\(notCurrent == 1 ? " has" : "s have") no current reading."
        }
        if earned > 0 {
            reason += " \(earned) earned reset\(earned == 1 ? "" : "s") available"
            if let firstExpiry { reason += ", first expires \(LimitsDigestText.moment(firstExpiry, now: now, calendar: calendar))" }
            reason += "."
        }
        if lastKnownEarned > 0 {
            reason += " Last known \(lastKnownEarned) earned reset\(lastKnownEarned == 1 ? "" : "s") from an older reading."
        }
        return UseNowPick(provider: provider, need: need, outcome: .noneUsable, account: nil, shortLabel: nil, runnerUp: nil,
                          usableAt: soonest?.date,
                          reason: reason)
    }

    static func percent(_ value: Double) -> String { "\(RemainingPercentText.format(value))" }

    static func duration(hours: Double) -> String {
        if hours < 1 { return "\(max(1, Int((hours * 60).rounded()))) minutes" }
        if hours < 48 { let whole = Int(hours.rounded()); return "\(whole) hour\(whole == 1 ? "" : "s")" }
        return "\(Int((hours / 24).rounded())) days"
    }
}
