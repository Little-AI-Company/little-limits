import AppKit
import UsageCore

@MainActor
enum UsageMenu {
    private struct Metric {
        let label: String
        let value: String
        let timing: String
        let detail: String
    }

    /// A transient progress line with nothing to open, such as `Loading Accounts…`. AppKit draws it disabled.
    static func progress(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    /// A state or error line. It is an enabled item with a real action so AppKit draws it at label
    /// contrast, not disabled contrast; the full explanation is in the tooltip.
    static func stateLine(_ title: String, detail: String?, target: AnyObject, action: Selector,
                          accountID: UUID? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = accountID
        item.toolTip = detail
        return item
    }

    /// Account sections for the status menu. State lines and reading rows open the account page; sections
    /// that need attention end with `Reconnect…` or `Open Account`. Both actions read the account id from `representedObject`.
    static func accountItems(profiles: [AccountProfile], snapshots: [UUID: AccountSnapshot],
                             consoleMessages: [UUID: String], now: Date,
                             target: AnyObject, openAction: Selector, reconnectAction: Selector) -> [NSMenuItem] {
        let font = NSFont.menuFont(ofSize: 0)
        let valueFont = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let metrics = profiles.map { profile in
            accountMetrics(profile: profile, snapshot: snapshots[profile.id], now: now)
        }
        let labelWidth = metrics.flatMap { $0 }.map { ($0.label as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let valueWidth = metrics.flatMap { $0 }.map { ($0.value as NSString).size(withAttributes: [.font: valueFont]).width }.max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: ceil(labelWidth) + 16),
                              NSTextTab(textAlignment: .left, location: ceil(labelWidth + valueWidth) + 32)]
        var items: [NSMenuItem] = []
        for (index, profile) in profiles.enumerated() {
            let snapshot = snapshots[profile.id]
            let provider = InterfaceFormatting.provider(profile.provider)
            let email = InterfaceFormatting.accountEmail(profile)
            let identity = InterfaceFormatting.accountIdentity(profile)
            let observation = snapshot?.fetchedAt.map { "Last reading: \(InterfaceFormatting.exactDate($0))" } ?? "No usage reading yet."
            let heading = NSMenuItem.sectionHeader(title: "\(provider) • \(identity)")
            heading.image = ProviderIcons.images[profile.provider]
            if #available(macOS 27, *) { heading.preferredImageVisibility = .visible }
            heading.toolTip = ["\(provider) · \(identity)", email == "Email unavailable" ? email : nil, observation, snapshot?.detail].compactMap { $0 }.joined(separator: "\n")
            items.append(heading)
            let state = snapshot.flatMap { accountState($0, now: now) }
            if let state {
                let item = stateLine(state, detail: [observation, snapshot?.detail].compactMap { $0 }.joined(separator: "\n"),
                                     target: target, action: openAction, accountID: profile.id)
                item.indentationLevel = 1
                items.append(item)
            }
            if let message = consoleMessages[profile.id] {
                let item = stateLine("API Credits need attention", detail: message, target: target, action: openAction, accountID: profile.id)
                item.indentationLevel = 1
                items.append(item)
            }
            for metric in metrics[index] {
                let item = NSMenuItem(title: "\(metric.label): \(metric.value)\(metric.timing.isEmpty ? "" : " · \(metric.timing)")",
                                      action: openAction, keyEquivalent: "")
                item.target = target
                item.representedObject = profile.id
                item.toolTip = metric.detail
                item.indentationLevel = 1
                // No explicit colors: AppKit draws label color and the highlight inversion for enabled items.
                let title = NSMutableAttributedString(string: metric.label + "\t", attributes: [.font: font])
                title.append(NSAttributedString(string: metric.value, attributes: [.font: valueFont]))
                if !metric.timing.isEmpty {
                    title.append(NSAttributedString(string: "\t" + metric.timing, attributes: [.font: font]))
                }
                title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
                item.attributedTitle = title
                items.append(item)
            }
            if state != nil || consoleMessages[profile.id] != nil {
                let needsSignIn = snapshot?.state == .authenticationRequired
                let item = NSMenuItem(title: needsSignIn ? "Reconnect…" : "Open Account",
                                      action: needsSignIn ? reconnectAction : openAction, keyEquivalent: "")
                item.target = target
                item.representedObject = profile.id
                item.indentationLevel = 1
                items.append(item)
            }
            items.append(.separator())
        }
        return items
    }

    private static func accountMetrics(profile: AccountProfile, snapshot: AccountSnapshot?, now: Date) -> [Metric] {
        var metrics: [Metric] = []
        let windows = snapshot?.windows ?? []
        let needsSignIn = snapshot?.state == .authenticationRequired
        let isOutdated = snapshot.map { isOutdated($0, now: now) } ?? false
        if windows.isEmpty {
            metrics.append(Metric(label: "Usage", value: "Unavailable", timing: "", detail: snapshot?.detail ?? "No usage reading yet."))
        }
        for window in windows {
            let value = isOutdated ? InterfaceFormatting.lastKnownRemaining(window) : InterfaceFormatting.remainingWithStatus(window)
            let timing = needsSignIn ? "" : window.isActive == false ? "Not current" : InterfaceFormatting.compactReset(window.resetsAt, now: now)
            metrics.append(Metric(label: InterfaceFormatting.usageTitle(window), value: value, timing: timing,
                                  detail: "\(InterfaceFormatting.usageTitle(window)): \(value). \(InterfaceFormatting.reset(window, now: now))"))
        }
        let credits = snapshot?.credits ?? UsageService.unavailableCredits(for: profile.provider)
        if let earned = earnedResets(credits, now: now) { metrics.append(earned) }
        for credit in credits where !isEarnedReset(credit) && !isPlaceholder(credit) {
            var timing: [String] = []
            if credit.source == .manual { timing.append("Manual") }
            if let date = credit.expiresAt { timing.append(InterfaceFormatting.compactExpiry(date, now: now)) }
            else if credit.doesNotExpire { timing.append("No expiry") }
            if credit.source != .manual,
               credit.asOf.map({ now.timeIntervalSince($0) >= 300 }) == true || credit.status == "Stale" {
                timing.append("Stale" + (credit.asOf.map { " · last read \($0.formatted(date: .omitted, time: .shortened))" } ?? ""))
            }
            metrics.append(Metric(label: InterfaceFormatting.compactCreditTitle(credit), value: InterfaceFormatting.credit(credit),
                                  timing: timing.joined(separator: " · "), detail: InterfaceFormatting.creditDetail(credit, now: now)))
        }
        return metrics
    }

    private static func isEarnedReset(_ credit: CreditBalance) -> Bool {
        credit.id.hasPrefix("quota_reset_")
    }

    /// A balance the provider has not reported and the user has not connected: no amount, no status, no observation.
    private static func isPlaceholder(_ credit: CreditBalance) -> Bool {
        credit.amount == nil && !credit.isUnlimited && credit.status == nil && credit.asOf == nil && credit.source != .manual
    }

    /// One row for the count and the nearest expiry. Per-grant expiry stays in the tooltip.
    private static func earnedResets(_ credits: [CreditBalance], now: Date) -> Metric? {
        let summary = credits.first { $0.id == "quota_reset_credits" }
        let grants = credits.filter { isEarnedReset($0) && $0.id != "quota_reset_credits" }
        guard summary != nil || !grants.isEmpty else { return nil }
        let count = summary?.amount.map { NSDecimalNumber(decimal: $0).intValue } ?? grants.count
        let nextExpiry = grants.compactMap(\.expiresAt).filter { $0 > now }.min()
        let timing = nextExpiry.map { "Next expires in \(UsageFormatting.countdown(to: $0, now: now))" } ?? ""
        var lines = ["Earned resets: \(count) available"]
        for grant in grants.sorted(by: { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }) {
            lines.append(grant.expiresAt.map { "\(InterfaceFormatting.compactExpiry($0, now: now)) · \(InterfaceFormatting.exactDate($0))" }
                ?? (grant.doesNotExpire ? "Does not expire" : "Expiration date unavailable"))
        }
        return Metric(label: "Earned resets", value: "\(count) available", timing: timing, detail: lines.joined(separator: "\n"))
    }

    private static func isOutdated(_ snapshot: AccountSnapshot, now: Date) -> Bool {
        switch snapshot.state {
        case .authenticationRequired, .stale: return true
        case .unavailable: return false
        case .available:
            return snapshot.fetchedAt.map { now.timeIntervalSince($0) >= 300 } == true
                || snapshot.currentWindows.contains { $0.resetsAt.map { $0 <= now } == true }
        }
    }

    private static func accountState(_ snapshot: AccountSnapshot, now: Date) -> String? {
        let lastRead = snapshot.fetchedAt.map { " · last read \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        switch snapshot.state {
        case .authenticationRequired: return "Sign-in required"
        case .unavailable: return snapshot.windows.isEmpty ? nil : "Unavailable"
        case .stale: return "Stale" + lastRead
        case .available:
            if isOutdated(snapshot, now: now) { return "Stale" + lastRead }
            return snapshot.fetchedAt == nil && !snapshot.windows.isEmpty ? "Observation time unknown" : nil
        }
    }

}
