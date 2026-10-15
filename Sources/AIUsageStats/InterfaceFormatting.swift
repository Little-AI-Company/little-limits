import AppKit
import UsageCore

enum InterfaceFormatting {
    static func accountEmail(_ profile: AccountProfile) -> String {
        guard let email = profile.providerEmail?.trimmingCharacters(in: .whitespacesAndNewlines),
              !email.isEmpty else { return "Email unavailable" }
        return email
    }

    static func accountIdentity(_ profile: AccountProfile) -> String {
        let email = accountEmail(profile)
        if email != "Email unavailable" { return email }
        let fallback = profile.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "\(provider(profile.provider)) Account" : fallback
    }

    static func usageTitle(_ window: UsageWindow) -> String { usageTitle(window.title) }

    /// Maps a provider window title such as `7 days (Fable 5)` to its display name, `Weekly · Fable 5`.
    static func usageTitle(_ title: String) -> String {
        if title == "5 hours" { return "5-hour" }
        if title == "7 days" { return "Weekly" }
        for (raw, name) in [("5 hours", "5-hour"), ("7 days", "Weekly")] where title.hasPrefix(raw + " (") && title.hasSuffix(")") {
            let scope = title.dropFirst(raw.count + 2).dropLast()
            return "\(name) · \(scope)"
        }
        return title
    }

    /// Remaining quota, the one percentage meaning shown everywhere in the interface.
    static func remaining(_ window: UsageWindow) -> String {
        if window.isActive == false { return "Inactive" }
        guard let used = window.utilizationPercent, used.isFinite else { return "Unavailable" }
        return "\(UsageFormatting.percentage(max(0, 100 - used))) left"
    }

    /// Remaining quota with the Home status word: `Low` or `Limit reached`.
    static func remainingWithStatus(_ window: UsageWindow) -> String {
        let value = remaining(window)
        guard window.isActive != false, let used = window.utilizationPercent, used.isFinite else { return value }
        switch HomeInterfaceFormatting.tone(for: max(0, 100 - used)) {
        case .neutral: return value
        case .warning: return "\(value), Low"
        case .critical: return "\(value), Limit reached"
        }
    }

    /// An old reading is prefixed so it is not mistaken for a current one.
    static func lastKnownRemaining(_ window: UsageWindow) -> String {
        let value = remaining(window)
        return value == "Unavailable" || value == "Inactive" ? value : "Last known \(value)"
    }

    /// A reading that must not pass for current: stale, sign-in required, a passed reset, older than five minutes,
    /// or observed in the future after a clock change.
    static func isOutdated(_ snapshot: AccountSnapshot, now: Date) -> Bool {
        switch snapshot.state {
        case .authenticationRequired, .stale: return true
        case .unavailable: return false
        case .available:
            return snapshot.fetchedAt.map { now.timeIntervalSince($0) >= 300 || $0 > now } == true
                || snapshot.currentWindows.contains { $0.resetsAt.map { $0 <= now } == true }
        }
    }

    /// Value and compact timing for one window, shared by the status menu and the account page. An outdated
    /// value reads `Last known 63% left`; sign-in required omits the timing.
    static func reading(_ window: UsageWindow, snapshot: AccountSnapshot, now: Date) -> (value: String, timing: String) {
        let value = isOutdated(snapshot, now: now) ? lastKnownRemaining(window) : remainingWithStatus(window)
        let timing = snapshot.state == .authenticationRequired ? ""
            : window.isActive == false ? "Not current"
            : window.hasNoPendingReset && snapshot.isCurrent(at: now) ? HomeInterfaceFormatting.noPendingResetText
            : compactReset(window.resetsAt, now: now)
        return (value, timing)
    }

    /// `No reset pending` needs a current reading; an old zero cannot show that nothing was used since.
    static func reset(_ window: UsageWindow, snapshot: AccountSnapshot?, now: Date = Date()) -> String {
        if window.isActive == false {
            return window.resetsAt.map { "Provider reported reset: \(exactDate($0))" } ?? "Reset time unknown"
        }
        if window.hasNoPendingReset, snapshot?.isCurrent(at: now) == true { return HomeInterfaceFormatting.noPendingResetText }
        return reset(window.resetsAt, now: now)
    }

    static func reset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Reset time unknown" }
        let duration = UsageFormatting.countdown(to: date, now: now)
        let countdown = date <= now ? "Reset due" : "Resets in \(duration)"
        return "\(countdown) · \(exactDate(date))"
    }

    static func exactDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().timeZone(.specificName(.short)))
    }

    static func compactReset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Reset time unknown" }
        guard date > now else { return "Reset due" }
        return "Resets in \(UsageFormatting.countdown(to: date, now: now))"
    }

    static func compactExpiry(_ date: Date, now: Date = Date()) -> String {
        guard date > now else { return "Expired" }
        return "Expires in \(UsageFormatting.countdown(to: date, now: now))"
    }

    static func compactCreditTitle(_ balance: CreditBalance) -> String {
        switch balance.id {
        case "monthly_grant": return "Monthly grant"
        case "api_balance": return balance.title == "Purchased API credits" ? "Purchased credits" : balance.title
        case "provider_credits": return "Codex credits"
        default:
            if balance.id.hasPrefix("monthly_grant_") { return "Monthly grant" }
            if balance.id.hasPrefix("api_balance_") { return "Purchased credits" }
            return balance.title
        }
    }

    static func credit(_ balance: CreditBalance) -> String {
        if balance.isUnlimited { return "Unlimited" }
        guard let amount = balance.amount else {
            if balance.status == "available" { return "Unknown" }
            return balance.status ?? "Unavailable"
        }
        return formatAmount(amount, unit: balance.unit, currencyCode: balance.currencyCode)
    }

    static func formatAmount(_ amount: Decimal, unit: CreditUnit, currencyCode: String?) -> String {
        switch unit {
        case .usd:
            return NSDecimalNumber(decimal: amount).doubleValue.formatted(.currency(code: "USD"))
        case .currency:
            guard let code = currencyCode else { return "\(NSDecimalNumber(decimal: amount).stringValue) (currency unavailable)" }
            return NSDecimalNumber(decimal: amount).doubleValue.formatted(.currency(code: code))
        case .credits:
            return "\(NSDecimalNumber(decimal: amount).stringValue) credits"
        case .resets:
            return "\(NSDecimalNumber(decimal: amount).stringValue) resets"
        }
    }

    static func creditDetail(_ balance: CreditBalance, now: Date = Date()) -> String {
        var lines = ["\(balance.title): \(credit(balance))"]
        if balance.source == .manual { lines.append("Manual balance.") }
        if let original = balance.originalAmount {
            lines.append("Original grant: \(formatAmount(original, unit: balance.unit, currencyCode: balance.currencyCode)).")
        }
        if let date = balance.asOf { lines.append("Observed \(exactDate(date)).") }
        else { lines.append("Observation time unknown.") }
        if let date = balance.expiresAt { lines.append("\(compactExpiry(date, now: now)) · \(exactDate(date)).") }
        else { lines.append(balance.doesNotExpire ? "Does not expire." : "Expiration date unavailable.") }
        if let status = balance.status { lines.append("Status: \(status)") }
        if let detail = balance.detail { lines.append(detail) }
        return lines.joined(separator: "\n")
    }

    static func compactCreditTiming(_ balance: CreditBalance, now: Date = Date()) -> String {
        var parts: [String] = []
        if balance.source == .manual { parts.append("Manual") }
        if let date = balance.expiresAt { parts.append(compactExpiry(date, now: now)) }
        else if balance.doesNotExpire { parts.append("No expiry") }
        else if balance.amount != nil { parts.append("Expiry unknown") }
        if balance.source != .manual,
           balance.status == "Stale" || balance.asOf.map({ now.timeIntervalSince($0) >= 300 }) == true {
            parts.append("Stale")
        }
        return parts.joined(separator: " · ")
    }

    static func provider(_ provider: Provider) -> String {
        switch provider { case .claude: "Claude"; case .codex: "Codex" }
    }
}

@MainActor
enum InterfaceControls {
    static func label(_ text: String, size: CGFloat = 12, weight: NSFont.Weight = .regular) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .labelColor
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        return label
    }

    static func stack(_ views: [NSView], spacing: CGFloat = 6) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = spacing
        return stack
    }

    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
