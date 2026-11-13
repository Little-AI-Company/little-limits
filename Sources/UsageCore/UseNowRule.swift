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

    private struct Candidate {
        let account: UsageOverviewAccount
        let offset: Int
        let weeklyLeft: Double
        let sessionLeft: Double
        let hoursToWeeklyReset: Double?
        var perHour: Double? { hoursToWeeklyReset.map { weeklyLeft / max($0, 1.0 / 60) } }
    }

    public static func pick(provider: Provider, accounts: [UsageOverviewAccount], now: Date, calendar: Calendar,
                            need: UseNowNeed = .weekly) -> UseNowPick {
        let members = accounts.filter { $0.profile.provider == provider }
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
        let runnerUp = steppedAside ?? ranked.first { $0.account.id != chosen.account.id }
        let reason: String
        if let steppedAside {
            reason = "\(steppedAside.account.shortIdentity) goes first for the week, but its 5-hour window has "
                + "\(percent(steppedAside.sessionLeft)) left, so use \(chosen.account.shortIdentity) "
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
        return UseNowPick(provider: provider, need: need, outcome: .picked, account: LimitsDigest.sanitizedLabel(chosen.account.identity),
                          shortLabel: LimitsDigest.sanitizedLabel(chosen.account.shortIdentity),
                          runnerUp: runnerUp.map { LimitsDigest.sanitizedLabel($0.account.shortIdentity) },
                          usableAt: nil, reason: reason)
    }

    private static func candidate(_ account: UsageOverviewAccount, offset: Int, now: Date) -> Candidate? {
        guard let snapshot = account.snapshot, snapshot.isCurrent(at: now),
              AccountUsability(snapshot: snapshot, now: now) == .usable else { return nil }
        let windows = snapshot.currentWindows
        guard let weekly = windows.first(where: { $0.role == .weekly }), let weeklyUsed = weekly.utilizationPercent else { return nil }
        let weeklyLeft = 100 - weeklyUsed
        let sessionLeft = windows.first { $0.role == .session }?.utilizationPercent.map { 100 - $0 } ?? 100
        guard weeklyLeft >= minimumPercentLeft, sessionLeft >= minimumPercentLeft else { return nil }
        let hours = weekly.resetsAt.flatMap { $0 > now ? $0.timeIntervalSince(now) / 3_600 : nil }
        return Candidate(account: account, offset: offset, weeklyLeft: weeklyLeft, sessionLeft: sessionLeft,
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

    private static func noneUsable(provider: Provider, need: UseNowNeed, members: [UsageOverviewAccount], now: Date, calendar: Calendar) -> UseNowPick {
        let soonest = members.compactMap { account -> (account: UsageOverviewAccount, date: Date)? in
            guard case .exhausted(let date?) = AccountUsability(snapshot: account.snapshot, now: now), date > now else { return nil }
            return (account, date)
        }.min { $0.date < $1.date }
        let earned = members.compactMap { account -> Int? in
            guard let summary = account.snapshot?.credits.first(where: { $0.id == "quota_reset_credits" }),
                  let amount = summary.amount, amount > 0 else { return nil }
            return NSDecimalNumber(decimal: amount).intValue
        }.reduce(0, +)
        let resetGrants: [CreditBalance] = members.flatMap { account -> [CreditBalance] in
            (account.snapshot?.credits ?? []).filter { credit in
                credit.unit == .resets && credit.id != "quota_reset_credits" && credit.status?.lowercased() == "available"
            }
        }
        let firstExpiry: Date? = resetGrants.compactMap(\.expiresAt).filter { $0 > now }.min()
        var reason = "No current \(provider.title) account has at least \(Int(minimumPercentLeft))% of its week and 5-hour window left."
        if let soonest {
            reason += " \(soonest.account.shortIdentity) is usable \(LimitsDigestText.moment(soonest.date, now: now, calendar: calendar))."
        }
        let notCurrent = members.filter { $0.snapshot?.isCurrent(at: now) != true }.count
        if notCurrent > 0 {
            reason += " \(notCurrent) account\(notCurrent == 1 ? " has" : "s have") no current reading."
        }
        if earned > 0 {
            reason += " \(earned) earned reset\(earned == 1 ? "" : "s") available"
            if let firstExpiry { reason += ", first expires \(LimitsDigestText.moment(firstExpiry, now: now, calendar: calendar))" }
            reason += "."
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
