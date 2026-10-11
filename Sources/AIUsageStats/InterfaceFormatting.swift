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

    static func usageTitle(_ window: UsageWindow) -> String {
        if window.title == "5 hours" { return "5-hour" }
        if window.title == "7 days" { return "Weekly" }
        if window.title.hasPrefix("5 hours (") { return window.title.replacingOccurrences(of: "5 hours", with: "5-hour") }
        if window.title.hasPrefix("7 days (") { return window.title.replacingOccurrences(of: "7 days", with: "Weekly") }
        return window.title
    }

    static func used(_ window: UsageWindow) -> String {
        if window.isActive == false { return "Inactive" }
        guard let used = window.utilizationPercent, used.isFinite else { return "Unavailable" }
        return "\(UsageFormatting.percentage(used)) used"
    }

    static func reset(_ window: UsageWindow, now: Date = Date()) -> String {
        if window.isActive == false {
            return window.resetsAt.map { "Provider reported reset: \(exactDate($0))" } ?? "Provider reset time unavailable"
        }
        return reset(window.resetsAt, now: now)
    }

    static func reset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Reset time unavailable" }
        let duration = UsageFormatting.countdown(to: date, now: now)
        let countdown = date <= now ? "Reset due" : "Resets in \(duration)"
        return "\(countdown) · \(exactDate(date))"
    }

    static func exactDate(_ date: Date) -> String {
        date.formatted(.dateTime.year().month(.abbreviated).day().hour().minute().timeZone(.specificName(.short)))
    }

    static func compactReset(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "Reset unknown" }
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
        case "api_balance": return balance.title == "Purchased API credits" ? "Purchased credits" : "API credits"
        case "provider_credits": return "Credits"
        default:
            if balance.id.hasPrefix("monthly_grant_") { return "Monthly grant" }
            if balance.id.hasPrefix("api_balance_") { return "Purchased credits" }
            return balance.title
        }
    }

    static func credit(_ balance: CreditBalance) -> String {
        if balance.isUnlimited { return "Unlimited" }
        guard let amount = balance.amount else { return balance.status ?? "Unavailable" }
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
        else { lines.append("Observation time unavailable.") }
        if let date = balance.expiresAt { lines.append("\(compactExpiry(date, now: now)) · \(exactDate(date)).") }
        else { lines.append(balance.doesNotExpire ? "Does not expire." : "Expiration date unavailable.") }
        if let status = balance.status { lines.append("Status: \(status)") }
        if let detail = balance.detail { lines.append(detail) }
        return lines.joined(separator: "\n")
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
