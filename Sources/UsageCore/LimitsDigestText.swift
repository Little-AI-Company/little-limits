import Foundation

public enum LimitsDigestText {
    public static func overview(_ digest: LimitsDigest, now: Date, provider: Provider? = nil) -> String {
        let calendar = calendar(for: digest)
        let accounts = digest.accounts.filter { provider == nil || $0.provider == provider }
        var lines = [heading(digest, now: now, calendar: calendar), ""]
        if accounts.isEmpty {
            lines.append(provider.map { "No \($0.title) accounts are set up in Little Limits." } ?? "No accounts are set up in Little Limits.")
            return lines.joined(separator: "\n")
        }
        let header = ["Account", "Weekly left", "Resets", "5-hour left", "Resets", "Note"]
        let rows = accounts.map { row($0, now: now, calendar: calendar) }
        lines += table([header] + rows)
        lines.append("")
        lines += footer(digest, accounts: accounts, now: now, calendar: calendar, provider: provider)
        return lines.joined(separator: "\n")
    }

    public static func heading(_ digest: LimitsDigest, now: Date, calendar: Calendar) -> String {
        let age = digest.age(at: now)
        let zone = calendar.timeZone.abbreviation(for: digest.asOf) ?? calendar.timeZone.identifier
        var text = "Little Limits, as of \(moment(digest.asOf, now: now, calendar: calendar)) (\(ageText(age))), times in \(zone)"
        if digest.isOutdated(at: now) {
            text += ". Not current: Little Limits last wrote this \(ageText(age)). Open it to read again: \(digest.openCommand)"
        }
        return text
    }

    public static func footer(_ digest: LimitsDigest, accounts: [LimitsDigest.Account], now: Date, calendar: Calendar,
                              provider: Provider?) -> [String] {
        var lines: [String] = []
        if let earned = earnedResetsLine(accounts, now: now, calendar: calendar) { lines.append(earned) }
        lines += apiCreditLines(accounts, now: now, calendar: calendar)
        lines += codexCreditLines(accounts, now: now, calendar: calendar)
        for pick in digest.useNow where pick.need == .weekly && (provider == nil || pick.provider == provider) {
            lines.append(useNowLine(pick))
        }
        return lines
    }

    public static func useNowLine(_ pick: UseNowPick) -> String {
        "Use now, \(pick.provider.title): \(pick.shortLabel ?? "none"). \(pick.reason)"
    }

    public static func accountName(_ account: LimitsDigest.Account) -> String {
        "\(account.label) (\(account.provider.title))"
    }

    public static func windowValue(_ window: LimitsDigest.Window?) -> String {
        guard let window else { return "none" }
        if let left = window.percentLeft {
            return "\(UseNowRule.percent(left))" + (window.level.map { ", \($0.word)" } ?? "")
        }
        if let left = window.lastKnownPercentLeft { return "Last known \(UseNowRule.percent(left))" }
        return "unknown"
    }

    public static func resetValue(_ window: LimitsDigest.Window?, now: Date, calendar: Calendar) -> String {
        guard let window else { return "" }
        guard let resetsAt = window.resetsAt else { return window.resetsDisplay }
        return resetsAt > now ? moment(resetsAt, now: now, calendar: calendar) : "reset passed"
    }

    public static func stateNote(_ account: LimitsDigest.Account, now: Date) -> String? {
        let read = account.observedAt.map { ", read \(ageText(max(0, now.timeIntervalSince($0))))" } ?? ""
        switch account.state {
        case .current: return nil
        case .stale: return "Stale" + read
        case .signInNeeded: return "Sign-in required" + read
        case .failed: return "Unavailable" + read
        case .unknown: return "No reading yet"
        case .inactive: return "No active usage window"
        }
    }

    private static func row(_ account: LimitsDigest.Account, now: Date, calendar: Calendar) -> [String] {
        let weekly = account.windows.first { $0.role == .weekly }
        let session = account.windows.first { $0.role == .session }
        var notes = [stateNote(account, now: now)].compactMap { $0 }
        for window in account.windows where window.role == .other {
            notes.append("\(window.kind) \(windowValue(window))")
        }
        return [accountName(account), windowValue(weekly), resetValue(weekly, now: now, calendar: calendar),
                session == nil && account.state == .current ? "no 5-hour window" : windowValue(session),
                resetValue(session, now: now, calendar: calendar), notes.joined(separator: "; ")]
    }

    private static func table(_ rows: [[String]]) -> [String] {
        let columns = rows.map(\.count).max() ?? 0
        let widths = (0..<columns).map { column in rows.map { column < $0.count ? $0[column].count : 0 }.max() ?? 0 }
        return rows.map { row in
            row.enumerated().map { index, cell in
                index == row.count - 1 ? cell : cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "  ").trimmingCharacters(in: .whitespaces)
        }
    }

    public static func earnedResetsLine(_ accounts: [LimitsDigest.Account], now: Date, calendar: Calendar) -> String? {
        var parts: [String] = []
        for account in accounts where account.provider == .codex {
            let earned = account.earnedResets
            switch earned.status {
            case .supported:
                let count = earned.count ?? 0
                var text = "\(account.shortLabel) (Codex) \(count) left"
                if count > 0, let expiries = expiriesText(earned, now: now, calendar: calendar) { text += ", \(expiries)" }
                if account.state != .current { text = "\(account.shortLabel) (Codex) last known \(count) left" }
                parts.append(text)
            case .unknown, .notSupported:
                parts.append("\(account.shortLabel) (Codex) unknown")
            }
        }
        if accounts.contains(where: { $0.provider == .claude }) { parts.append("Claude limit resets: not read yet") }
        return parts.isEmpty ? nil : "Earned resets: " + parts.joined(separator: ". ") + "."
    }

    public static func expiriesText(_ earned: LimitsDigest.EarnedResets, now: Date, calendar: Calendar) -> String? {
        let dates = (earned.expiresAt ?? earned.nextExpiresAt.map { [$0] } ?? []).filter { $0 > now }
        guard !dates.isEmpty else { return nil }
        let list = dates.map { moment($0, now: now, calendar: calendar) }.joined(separator: ", ")
        return earned.expiresAt == nil ? "first expires \(list)" : "expiring \(list)"
    }

    public static func codexCreditLines(_ accounts: [LimitsDigest.Account], now: Date, calendar: Calendar) -> [String] {
        accounts.filter { $0.provider == .codex }.compactMap { account -> String? in
            guard let credits = account.credits else { return nil }
            let amount: String = credits.unlimited ? "unlimited" : (credits.amount.map(creditCount) ?? "unknown")
            let qualifier = account.state == .current ? "" : "last known "
            var text = "Codex credits, \(account.shortLabel): \(qualifier)\(amount)"
            if let asOf = credits.asOf { text += " (as of \(moment(asOf, now: now, calendar: calendar)))" }
            return text + "."
        }
    }

    public static func creditCount(_ amount: Decimal) -> String {
        amount.formatted(.number.precision(.fractionLength(0)).locale(Locale(identifier: "en_US")))
    }

    public static func apiCreditLines(_ accounts: [LimitsDigest.Account], now: Date, calendar: Calendar) -> [String] {
        let claude = accounts.filter { $0.provider == .claude }
        guard !claude.isEmpty else { return [] }
        let connected = claude.filter { !$0.apiCredits.isEmpty }
        guard !connected.isEmpty else { return ["Claude API credits: not connected. Connect API Credits in Little Limits to read them."] }
        return connected.map { account in
            let parts = account.apiCredits.map { creditText($0, now: now, calendar: calendar) }
            let experimental = account.apiCredits.contains { $0.experimental } ? " (experimental)" : ""
            return "Claude API credits\(experimental), \(account.shortLabel): " + parts.joined(separator: " ")
        }
    }

    public static func creditText(_ credit: LimitsDigest.APICredit, now: Date, calendar: Calendar) -> String {
        let amount = credit.amount.map { money($0, currency: credit.currency) } ?? (credit.status ?? "unknown")
        var text: String
        switch credit.kind {
        case .purchased: text = "\(amount) purchased"
        case .monthlyGrant: text = "Current monthly grant: \(amount) left"
        case .promotional: text = "Promotional grant: \(amount) left"
        case .other: text = "\(credit.title): \(amount)"
        }
        if let expires = credit.expiresAt {
            text += expires > now ? ", current grant expires \(moment(expires, now: now, calendar: calendar))" : ", expired"
            if credit.kind != .monthlyGrant { text = text.replacingOccurrences(of: "current grant expires", with: "expires") }
        } else if credit.kind == .monthlyGrant {
            text += ", expiry unknown"
        }
        if credit.source == .manual { text += ", entered by hand" }
        if let asOf = credit.asOf { text += ", as of \(moment(asOf, now: now, calendar: calendar))" }
        if credit.status == "Stale" { text += ", stale" }
        return text + "."
    }

    public static func money(_ amount: Decimal, currency: String?) -> String {
        guard let currency else { return "\(NSDecimalNumber(decimal: amount).stringValue) (currency unknown)" }
        return amount.formatted(.currency(code: currency).locale(Locale(identifier: "en_US")))
    }

    public static func ageText(_ age: TimeInterval) -> String {
        let minutes = Int(age / 60)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) min ago" }
        let hours = minutes / 60
        if hours < 48 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }

    public static func calendar(for digest: LimitsDigest) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(identifier: digest.timeZone) ?? .current
        return calendar
    }

    public static func moment(_ date: Date, now: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        formatter.dateFormat = calendar.component(.minute, from: date) == 0 ? "ha" : "h:mma"
        let time = formatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return time }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? .max
        if abs(days) < 7 {
            formatter.dateFormat = "EEE"
            return "\(formatter.string(from: date)) \(time)"
        }
        formatter.dateFormat = calendar.component(.year, from: date) == calendar.component(.year, from: now) ? "MMM d" : "MMM d, yyyy"
        return "\(formatter.string(from: date)) \(time)"
    }
}

public struct MorningDigestNotice: Equatable, Sendable {
    public let title: String
    public let body: String
}

extension LimitsDigestText {
    public static func morningDigest(_ digest: LimitsDigest, now: Date, calendar: Calendar, missed: Date?) -> MorningDigestNotice {
        var title = "Usage · \(weekdayMoment(now, calendar: calendar))"
        if let missed { title += ", late for \(moment(missed, now: now, calendar: calendar))" }
        var lines: [String] = []
        let picks = digest.useNow.filter { $0.need == .weekly && $0.outcome == .picked }
        if !picks.isEmpty {
            lines.append("Use first: " + picks.map { pick in
                let account = digest.accounts.first { $0.provider == pick.provider && $0.shortLabel == pick.shortLabel }
                let weekly = account?.windows.first { $0.role == .weekly }
                let detail = weekly.flatMap { window in
                    window.percentLeft.map { "(\(UseNowRule.percent($0)), resets \(resetValue(window, now: now, calendar: calendar)))" }
                }
                return ["\(pick.provider.title) \(pick.shortLabel ?? "")", detail].compactMap { $0 }.joined(separator: " ")
            }.joined(separator: " · "))
        }
        for account in digest.accounts {
            let window = account.windows.first { $0.role == .weekly } ?? account.windows.first { $0.role == .session }
            var parts = ["\(account.provider.title) \(account.shortLabel)"]
            switch account.state {
            case .current:
                if let window {
                    let left = window.percentLeft.map { "\(UseNowRule.percent($0)) left" } ?? "unknown"
                    parts.append(left + (window.level.map { ", \($0.word)" } ?? ""))
                    parts.append("resets \(resetValue(window, now: now, calendar: calendar))")
                } else {
                    parts.append("no usage window")
                }
            default:
                if let left = window?.lastKnownPercentLeft { parts.append("Last known \(UseNowRule.percent(left)) left") }
                parts.append(stateNote(account, now: now) ?? "Unavailable")
            }
            lines.append(parts.joined(separator: " · "))
        }
        for account in digest.accounts where account.provider == .codex && account.earnedResets.status == .supported {
            guard let count = account.earnedResets.count, count > 0 else { continue }
            var text = "\(account.provider.title) \(account.shortLabel): \(count) earned reset\(count == 1 ? "" : "s")"
            if let expiries = expiriesText(account.earnedResets, now: now, calendar: calendar) { text += ", \(expiries)" }
            lines.append(text)
        }
        for account in digest.accounts where !account.apiUsable.isEmpty {
            let amounts = account.apiUsable.map { money($0.amount, currency: $0.currency) }.joined(separator: " + ")
            var text = "\(account.provider.title) \(account.shortLabel) API credits: \(amounts)"
            if let grant = account.apiCredits.first(where: { $0.kind == .monthlyGrant }), let expires = grant.expiresAt, expires > now {
                text += ", current grant expires \(moment(expires, now: now, calendar: calendar))"
            }
            lines.append(text)
        }
        if lines.isEmpty { lines.append("No accounts are set up in Little Limits.") }
        return MorningDigestNotice(title: title, body: lines.joined(separator: "\n"))
    }

    static func weekdayMoment(_ date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.amSymbol = "am"
        formatter.pmSymbol = "pm"
        formatter.dateFormat = calendar.component(.minute, from: date) == 0 ? "EEE ha" : "EEE h:mma"
        return formatter.string(from: date)
    }
}
