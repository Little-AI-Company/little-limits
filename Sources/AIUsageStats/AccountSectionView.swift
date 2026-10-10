import AppKit
import UsageCore

@MainActor
private final class FocusVisibilityButton: NSButton {
    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { scrollToVisible(bounds) }
        return accepted
    }
}

@MainActor
private final class UsageMetricView: NSView {
    let title = InterfaceControls.label("")
    let value = InterfaceControls.label("", size: 13, weight: .semibold)
    let timing = InterfaceControls.label("", size: 12)

    init(isQuota: Bool) {
        super.init(frame: .zero)
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 2
        value.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        value.alignment = .right
        value.lineBreakMode = .byTruncatingTail
        value.maximumNumberOfLines = 1
        timing.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        timing.alignment = .right
        timing.lineBreakMode = .byWordWrapping
        timing.maximumNumberOfLines = 2
        for label in [title, value, timing] {
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
        }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor),
            title.centerYAnchor.constraint(equalTo: centerYAnchor),
            title.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 3),
            title.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -3),
            title.widthAnchor.constraint(equalToConstant: isQuota ? 118 : 160),
            value.leadingAnchor.constraint(equalTo: title.trailingAnchor, constant: 8),
            value.centerYAnchor.constraint(equalTo: centerYAnchor),
            value.widthAnchor.constraint(equalToConstant: isQuota ? 146 : 104),
            timing.leadingAnchor.constraint(equalTo: value.trailingAnchor, constant: 10),
            timing.trailingAnchor.constraint(equalTo: trailingAnchor),
            timing.centerYAnchor.constraint(equalTo: centerYAnchor),
            timing.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 3),
            timing.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -3),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 26)
        ])
    }
    required init?(coder: NSCoder) { nil }
}

@MainActor
final class AccountSectionView: NSStackView {
    var onExpansionChange: (() -> Void)?
    var keyboardControls: [NSView] { details.isHidden ? [disclosure] : [disclosure, dashboard] }
    private var profile: AccountProfile
    private var snapshot: AccountSnapshot?
    private var consoleMessage: String?
    private let providerLabel = InterfaceControls.label("", size: 15, weight: .semibold)
    private let nameLabel = InterfaceControls.label("", size: 12)
    private let stateLabel = InterfaceControls.label("", size: 11, weight: .medium)
    private let disclosure = FocusVisibilityButton(title: "Details", target: nil, action: nil)
    private let quotaRows = InterfaceControls.stack([], spacing: 0)
    private let creditRows = InterfaceControls.stack([], spacing: 0)
    private let issue = InterfaceControls.label("", size: 12)
    private let details = InterfaceControls.stack([], spacing: 5)
    private let detailsText = InterfaceControls.label("", size: 11)
    private let dashboard = FocusVisibilityButton(title: "Open Usage Dashboard", target: nil, action: nil)
    private var quotaViews: [String: UsageMetricView] = [:]
    private var creditViews: [String: UsageMetricView] = [:]
    private var windowIDs: [String] = []
    private var creditIDs: [String] = []

    init(profile: AccountProfile) {
        self.profile = profile
        super.init(frame: .zero)
        orientation = .vertical
        alignment = .leading
        spacing = 4
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.maximumNumberOfLines = 1
        disclosure.target = self
        disclosure.action = #selector(toggleDetails(_:))
        disclosure.setButtonType(.pushOnPushOff)
        disclosure.bezelStyle = .inline
        disclosure.isBordered = false
        disclosure.refusesFirstResponder = false
        disclosure.imagePosition = .imageLeading
        disclosure.controlSize = .small
        disclosure.font = .systemFont(ofSize: 12)
        disclosure.setContentHuggingPriority(.required, for: .horizontal)
        disclosure.heightAnchor.constraint(equalToConstant: 24).isActive = true
        let heading = NSStackView(views: [providerLabel, nameLabel, NSView(), stateLabel, disclosure])
        heading.orientation = .horizontal
        heading.spacing = 8
        providerLabel.setContentHuggingPriority(.required, for: .horizontal)
        stateLabel.setContentHuggingPriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        dashboard.target = self
        dashboard.action = #selector(openDashboard(_:))
        dashboard.controlSize = .small
        dashboard.refusesFirstResponder = false
        details.addArrangedSubview(detailsText)
        details.addArrangedSubview(dashboard)
        details.isHidden = true
        detailsText.widthAnchor.constraint(equalTo: details.widthAnchor).isActive = true
        let separator = InterfaceControls.separator()
        for component in [heading, quotaRows, separator, creditRows, issue, details] {
            addArrangedSubview(component)
            component.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        setCustomSpacing(6, after: heading)
        setCustomSpacing(6, after: quotaRows)
        setCustomSpacing(6, after: separator)
        setCustomSpacing(6, after: creditRows)
        updateDisclosure()
    }
    required init?(coder: NSCoder) { nil }

    func update(profile: AccountProfile, snapshot: AccountSnapshot?, consoleMessage: String?, now: Date) {
        self.profile = profile
        self.snapshot = snapshot
        self.consoleMessage = consoleMessage
        providerLabel.stringValue = InterfaceFormatting.provider(profile.provider)
        nameLabel.stringValue = profile.label
        nameLabel.toolTip = profile.label
        disclosure.setAccessibilityLabel("Details for \(profile.label)")
        dashboard.title = "Open \(InterfaceFormatting.provider(profile.provider)) Usage Dashboard"
        let windows = snapshot?.windows ?? []
        let credits = snapshot?.credits ?? UsageService.unavailableCredits(for: profile.provider)
        synchronizeRows(windows: windows, credits: credits)
        updateTimes(now: now)
        updateIssue()
        updateDetails(now: now)
    }

    func updateTimes(now: Date) {
        let windows = snapshot?.windows ?? []
        let credits = snapshot?.credits ?? UsageService.unavailableCredits(for: profile.provider)
        if windows.isEmpty, let row = quotaViews["unavailable"] {
            row.title.stringValue = "Plan usage"
            row.value.stringValue = "Unavailable"
            row.timing.stringValue = ""
            row.setAccessibilityLabel("Plan usage unavailable")
        }
        for window in windows {
            guard let row = quotaViews[window.id] else { continue }
            row.title.stringValue = window.title
            row.value.stringValue = InterfaceFormatting.remaining(window)
            row.timing.stringValue = window.isActive == false ? "Not current" : InterfaceFormatting.compactReset(window.resetsAt, now: now)
            row.toolTip = "\(window.title): \(InterfaceFormatting.remaining(window)). \(InterfaceFormatting.reset(window, now: now))"
            row.setAccessibilityLabel(row.toolTip)
            row.title.toolTip = window.title
            row.timing.setAccessibilityLabel(InterfaceFormatting.reset(window, now: now))
        }
        for credit in credits {
            guard let row = creditViews[credit.id] else { continue }
            row.title.stringValue = InterfaceFormatting.compactCreditTitle(credit)
            row.value.stringValue = InterfaceFormatting.credit(credit)
            if let date = credit.expiresAt {
                row.timing.stringValue = credit.unit == .resets
                    ? InterfaceFormatting.shortExpiry(date, now: now)
                    : InterfaceFormatting.compactExpiry(date, now: now)
            } else if credit.doesNotExpire {
                row.timing.stringValue = "No expiry"
            } else {
                row.timing.stringValue = ""
            }
            if credit.source == .manual {
                if let date = credit.expiresAt {
                    row.timing.stringValue = date > now ? "Manual · \(UsageFormatting.countdown(to: date, now: now)) left" : "Manual · Expired"
                } else { row.timing.stringValue = "Manual" }
            } else if credit.asOf.map({ now.timeIntervalSince($0) >= 300 }) == true || consoleMessage != nil {
                row.timing.stringValue = row.timing.stringValue.isEmpty ? "Stale" : "\(row.timing.stringValue)\nStale"
            }
            var description = "\(credit.title): \(InterfaceFormatting.credit(credit))."
            if credit.source == .manual { description += " Manual balance." }
            if let date = credit.expiresAt { description += " \(InterfaceFormatting.expiry(date))" }
            else { description += credit.doesNotExpire ? " Does not expire." : " Expiration date unavailable." }
            if let date = credit.asOf { description += " Observed \(InterfaceFormatting.exactDate(date))." }
            row.toolTip = description
            row.setAccessibilityLabel(description)
            row.title.toolTip = credit.title
            row.timing.setAccessibilityLabel(description)
        }
        if let snapshot {
            if snapshot.state == .authenticationRequired { stateLabel.stringValue = "Sign-in required" }
            else if isStale(snapshot, now: now) { stateLabel.stringValue = "Stale" }
            else if snapshot.fetchedAt == nil { stateLabel.stringValue = "No reading" }
            else { stateLabel.stringValue = "" }
        } else { stateLabel.stringValue = "No reading" }
        stateLabel.isHidden = stateLabel.stringValue.isEmpty
        if !details.isHidden { updateDetails(now: now) }
    }

    private func synchronizeRows(windows: [UsageWindow], credits: [CreditBalance]) {
        let newWindowIDs = windows.isEmpty ? ["unavailable"] : windows.map(\.id)
        if newWindowIDs != windowIDs {
            replaceRows(in: quotaRows, ids: newWindowIDs, existing: &quotaViews, isQuota: true)
            windowIDs = newWindowIDs
        }
        let newCreditIDs = credits.map(\.id)
        if newCreditIDs != creditIDs {
            replaceRows(in: creditRows, ids: newCreditIDs, existing: &creditViews, isQuota: false)
            creditIDs = newCreditIDs
        }
    }

    private func replaceRows(in stack: NSStackView, ids: [String], existing: inout [String: UsageMetricView], isQuota: Bool) {
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        existing = existing.filter { ids.contains($0.key) }
        for id in ids {
            let row = existing[id] ?? UsageMetricView(isQuota: isQuota)
            existing[id] = row
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func updateIssue() {
        if snapshot?.state == .authenticationRequired {
            issue.stringValue = "Sign in to this account again in Accounts."
        } else if let consoleMessage {
            issue.stringValue = "API credits need attention. Open Accounts to reconnect."
            issue.toolTip = consoleMessage
        } else if snapshot?.state == .unavailable {
            issue.stringValue = "No usage reading yet. Open Details for the next step."
        } else {
            issue.stringValue = ""
        }
        issue.isHidden = issue.stringValue.isEmpty
    }

    private func updateDetails(now: Date) {
        var lines: [String] = []
        if let identity = profile.providerAccountID { lines.append("Account: \(identity)") }
        if let snapshot {
            if let date = snapshot.fetchedAt {
                lines.append("\(profile.provider == .claude ? "Captured" : "Fetched") \(InterfaceFormatting.exactDate(date))\(isStale(snapshot, now: now) ? " · Stale" : "")")
            } else { lines.append("No quota reading yet.") }
            for window in snapshot.windows {
                lines.append("\(window.title): \(window.isActive == false ? "Inactive. " : "")\(InterfaceFormatting.reset(window, now: now))")
            }
            for credit in snapshot.credits {
                var line = "\(credit.title): \(InterfaceFormatting.credit(credit))"
                if credit.source == .manual { line += " · Manual" }
                if let original = credit.originalAmount {
                    line += " remaining of \(InterfaceFormatting.formatAmount(original, unit: credit.unit, currencyCode: credit.currencyCode)) granted"
                }
                if let date = credit.asOf { line += " · Observed \(InterfaceFormatting.exactDate(date))" }
                if let date = credit.expiresAt { line += "\n\(InterfaceFormatting.expiry(date))" }
                else { line += credit.doesNotExpire ? "\nDoes not expire." : "\nExpiration date unavailable." }
                if let detail = credit.detail { line += "\n\(detail)" }
                lines.append(line)
            }
            if let detail = snapshot.detail { lines.append(detail) }
        }
        if let consoleMessage { lines.append("API billing: \(consoleMessage)") }
        detailsText.stringValue = lines.joined(separator: "\n\n")
    }

    private func isStale(_ snapshot: AccountSnapshot, now: Date) -> Bool {
        snapshot.state == .stale || snapshot.state == .authenticationRequired
            || snapshot.fetchedAt.map { now.timeIntervalSince($0) >= 300 } == true
            || snapshot.currentWindows.contains { $0.resetsAt.map { $0 <= now } == true }
    }

    private func updateDisclosure() {
        let expanded = disclosure.state == .on
        disclosure.image = NSImage(systemSymbolName: expanded ? "chevron.down" : "chevron.right", accessibilityDescription: nil)
        disclosure.setAccessibilityValue(expanded ? "Expanded" : "Collapsed")
    }
    @objc private func toggleDetails(_ sender: NSButton) {
        window?.makeFirstResponder(sender)
        details.isHidden = sender.state != .on
        updateDisclosure()
        if !details.isHidden { updateDetails(now: Date()) }
        onExpansionChange?()
    }
    @objc private func openDashboard(_ sender: Any?) {
        let address = profile.provider == .claude ? "https://claude.ai/settings/usage" : "https://chatgpt.com/codex/settings/usage"
        if let url = URL(string: address) { NSWorkspace.shared.open(url) }
    }
}
