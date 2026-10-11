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

    static func reading(_ title: String, detail: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        // Informational readings retain ordinary semantic text without becoming commands.
        item.attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.labelColor])
        item.toolTip = detail
        return item
    }

    static func accountItems(profiles: [AccountProfile], snapshots: [UUID: AccountSnapshot],
                             consoleMessages: [UUID: String], now: Date) -> [NSMenuItem] {
        let font = NSFont.menuFont(ofSize: 0)
        let valueFont = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let metrics = profiles.map { profile in
            accountMetrics(profile: profile, snapshot: snapshots[profile.id], consoleMessage: consoleMessages[profile.id], now: now)
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
            for metric in metrics[index] {
                let item = reading("\(metric.label): \(metric.value)\(metric.timing.isEmpty ? "" : " · \(metric.timing)")", detail: metric.detail)
                item.indentationLevel = 1
                let title = NSMutableAttributedString(string: metric.label + "\t", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
                title.append(NSAttributedString(string: metric.value, attributes: [.font: valueFont, .foregroundColor: NSColor.labelColor]))
                if !metric.timing.isEmpty {
                    title.append(NSAttributedString(string: "\t" + metric.timing, attributes: [.font: font, .foregroundColor: NSColor.secondaryLabelColor]))
                }
                title.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
                item.attributedTitle = title
                items.append(item)
            }
            if let snapshot, let state = accountState(snapshot, now: now) {
                let item = reading(state, detail: [observation, snapshot.detail, "Open Manage Accounts for connection details and recovery."].compactMap { $0 }.joined(separator: "\n"))
                item.indentationLevel = 1
                items.append(item)
            }
            if let message = consoleMessages[profile.id] {
                let item = reading("API credits need attention", detail: message + "\nOpen Manage Accounts to reconnect.")
                item.indentationLevel = 1
                items.append(item)
            }
            items.append(.separator())
        }
        return items
    }

    private static func accountMetrics(profile: AccountProfile, snapshot: AccountSnapshot?, consoleMessage: String?, now: Date) -> [Metric] {
        var metrics: [Metric] = []
        let windows = snapshot?.windows ?? []
        if windows.isEmpty {
            metrics.append(Metric(label: "Usage", value: "Unavailable", timing: "", detail: snapshot?.detail ?? "No usage reading yet."))
        }
        for window in windows {
            let timing = window.isActive == false ? "Not current" : InterfaceFormatting.compactReset(window.resetsAt, now: now)
            metrics.append(Metric(label: InterfaceFormatting.usageTitle(window), value: InterfaceFormatting.used(window), timing: timing,
                                  detail: "\(window.title): \(InterfaceFormatting.used(window)). \(InterfaceFormatting.reset(window, now: now))"))
        }
        for credit in snapshot?.credits ?? UsageService.unavailableCredits(for: profile.provider) {
            var timing: [String] = []
            if credit.source == .manual { timing.append("Manual") }
            if let date = credit.expiresAt { timing.append(InterfaceFormatting.compactExpiry(date, now: now)) }
            else if credit.doesNotExpire { timing.append("No expiry") }
            if credit.source != .manual,
               credit.asOf.map({ now.timeIntervalSince($0) >= 300 }) == true || credit.status == "Stale" || consoleMessage != nil { timing.append("Stale") }
            metrics.append(Metric(label: InterfaceFormatting.compactCreditTitle(credit), value: InterfaceFormatting.credit(credit),
                                  timing: timing.joined(separator: " · "), detail: InterfaceFormatting.creditDetail(credit, now: now)))
        }
        return metrics
    }

    private static func accountState(_ snapshot: AccountSnapshot, now: Date) -> String? {
        switch snapshot.state {
        case .authenticationRequired: return "Sign-in required"
        case .unavailable: return snapshot.windows.isEmpty ? nil : "Usage unavailable"
        case .stale: return "Stale usage reading"
        case .available:
            let isStale = snapshot.fetchedAt.map { now.timeIntervalSince($0) >= 300 } == true
                || snapshot.currentWindows.contains { $0.resetsAt.map { $0 <= now } == true }
            return isStale ? "Stale usage reading" : (snapshot.fetchedAt == nil && !snapshot.windows.isEmpty ? "Observation time unknown" : nil)
        }
    }

}
