import AppKit
import UsageCore

enum InterfaceFormatting {
    static func remaining(_ window: UsageWindow) -> String {
        guard let used = window.utilizationPercent, used.isFinite else { return "Unavailable" }
        return "\(Int((100 - min(100, max(0, used))).rounded()))% remaining"
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
        return "Reset \(UsageFormatting.countdown(to: date, now: now))"
    }

    static func compactExpiry(_ date: Date, now: Date = Date()) -> String {
        guard date > now else { return "Expired" }
        return "Expires \(UsageFormatting.countdown(to: date, now: now))"
    }

    static func shortExpiry(_ date: Date, now: Date = Date()) -> String {
        let calendarDate = date.formatted(.dateTime.month(.abbreviated).day())
        guard date > now else { return "Expired \(calendarDate)" }
        return "\(calendarDate) · \(UsageFormatting.countdown(to: date, now: now)) left"
    }

    static func compactCreditTitle(_ balance: CreditBalance) -> String {
        switch balance.id {
        case "monthly_grant": return "Monthly API grant"
        case "api_balance": return balance.title
        default:
            if balance.id.hasPrefix("api_balance_") { return "Purchased API credits" }
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

    static func expiry(_ date: Date) -> String {
        let resetText = reset(date)
        return resetText.replacingOccurrences(of: "Resets in", with: "Expires in")
            .replacingOccurrences(of: "Reset due", with: "Expired")
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
