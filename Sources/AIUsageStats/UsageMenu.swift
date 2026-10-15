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

    /// Usage sections for the status menu: weekly totals for each provider with two or more accounts, then one
    /// section per account. Total rows open Home. State lines and reading rows open the account page; sections
    /// that need attention end with `Reconnect…` or `Open Account`. Both actions read the account id from `representedObject`.
    static func accountItems(profiles: [AccountProfile], snapshots: [UUID: AccountSnapshot],
                             consoleMessages: [UUID: String], now: Date,
                             target: AnyObject, homeAction: Selector, openAction: Selector, reconnectAction: Selector) -> [NSMenuItem] {
        let font = NSFont.menuFont(ofSize: 0)
        let valueFont = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let overview = UsageOverview(profiles: profiles, snapshots: snapshots, now: now)
        let totals = overview.providers.filter { $0.accountCount > 1 }.map { provider in
            (provider: provider.provider, metrics: totalMetrics(provider, overview: overview, now: now))
        }
        let metrics = profiles.map { profile in
            accountMetrics(profile: profile, snapshot: snapshots[profile.id], now: now)
        }
        let every = metrics.flatMap { $0 } + totals.flatMap(\.metrics)
        let labelWidth = every.map { ($0.label as NSString).size(withAttributes: [.font: font]).width }.max() ?? 0
        let valueWidth = every.map { ($0.value as NSString).size(withAttributes: [.font: valueFont]).width }.max() ?? 0
        let paragraph = NSMutableParagraphStyle()
        paragraph.tabStops = [NSTextTab(textAlignment: .left, location: ceil(labelWidth) + 16),
                              NSTextTab(textAlignment: .left, location: ceil(labelWidth + valueWidth) + 32)]
        func readingItem(_ metric: Metric, action: Selector, accountID: UUID?) -> NSMenuItem {
            let item = NSMenuItem(title: "\(metric.label): \(metric.value)\(metric.timing.isEmpty ? "" : " · \(metric.timing)")",
                                  action: action, keyEquivalent: "")
            item.target = target
            item.representedObject = accountID
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
            return item
        }
        var items: [NSMenuItem] = []
        for total in totals {
            let heading = NSMenuItem.sectionHeader(title: "\(InterfaceFormatting.provider(total.provider)) • All accounts")
            heading.image = ProviderIcons.images[total.provider]
            if #available(macOS 27, *) { heading.preferredImageVisibility = .visible }
            items.append(heading)
            items += total.metrics.map { readingItem($0, action: homeAction, accountID: nil) }
            items.append(.separator())
        }
        for (index, profile) in profiles.enumerated() {
            let snapshot = snapshots[profile.id]
            let provider = InterfaceFormatting.provider(profile.provider)
            let email = InterfaceFormatting.accountEmail(profile)
            let identity = InterfaceFormatting.accountIdentity(profile)
            let observation = snapshot?.fetchedAt.map { "Last reading: \(InterfaceFormatting.exactDate($0))" } ?? HomeInterfaceFormatting.noReadingHelp
            let heading = NSMenuItem.sectionHeader(title: "\(provider) • \(identity)")
            heading.image = ProviderIcons.images[profile.provider]
            if #available(macOS 27, *) { heading.preferredImageVisibility = .visible }
            heading.toolTip = ["\(provider) · \(identity)", email == "Email unavailable" ? email : nil, observation, snapshot?.detail].compactMap { $0 }.joined(separator: "\n")
            items.append(heading)
            // No snapshot or no windows is a section without readings: it still gets a state line and Open Account.
            let state = snapshot.flatMap { accountState($0, now: now) }
                ?? ((snapshot?.windows ?? []).isEmpty ? "Unavailable" : nil)
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
            items += metrics[index].map { readingItem($0, action: openAction, accountID: profile.id) }
            if state != nil || consoleMessages[profile.id] != nil {
                // A reused Codex CLI login is signed in outside the app, so it opens the account instead.
                let needsSignIn = snapshot?.state == .authenticationRequired && profile.source != .codexDefaultLogin
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

    /// Weekly total rows and the next reset for one provider, with the same text as Home's Weekly Totals.
    private static func totalMetrics(_ provider: ProviderQuotaOverview, overview: UsageOverview, now: Date) -> [Metric] {
        let names = Dictionary(uniqueKeysWithValues: overview.accounts.map { ($0.id, "\($0.profile.provider.title) \($0.shortIdentity)") })
        var metrics = ([provider.weekly] + provider.scopedWeekly).map { pool in
            Metric(label: HomeInterfaceFormatting.poolLabel(pool), value: HomeInterfaceFormatting.poolValue(pool),
                   timing: HomeInterfaceFormatting.poolUnknownText(pool) ?? "", detail: HomeInterfaceFormatting.poolHelp(pool, names: names))
        }
        let reset = HomeInterfaceFormatting.nextResetText(provider.nextReset, names: names, now: now, calendar: .current)
        let timing: String
        if case .reset(let next) = provider.nextReset { timing = "in \(UsageFormatting.countdown(to: next.resetsAt, now: now))" } else { timing = "" }
        metrics.append(Metric(label: "Next reset", value: reset.value, timing: timing, detail: reset.help))
        return metrics
    }

    private static func accountMetrics(profile: AccountProfile, snapshot: AccountSnapshot?, now: Date) -> [Metric] {
        var metrics: [Metric] = []
        let windows = snapshot?.windows ?? []
        for window in windows {
            guard let snapshot else { continue }
            let (value, timing) = InterfaceFormatting.reading(window, snapshot: snapshot, now: now)
            metrics.append(Metric(label: InterfaceFormatting.usageTitle(window), value: value, timing: timing,
                                  detail: "\(InterfaceFormatting.usageTitle(window)): \(value). \(InterfaceFormatting.reset(window, snapshot: snapshot, now: now))"))
        }
        // A fully used current 5-hour or weekly window: when the account takes requests again, the latest reset among them.
        if case .exhausted(let usableAt) = AccountUsability(snapshot: snapshot, now: now) {
            let value = usableAt.map { UsageFormatting.countdown(to: $0, now: now) } ?? "Unknown"
            let detail = usableAt.map { "Usable again \(InterfaceFormatting.exactDate($0)), when its last fully used 5-hour or weekly window resets." }
                ?? "A fully used 5-hour or weekly window has no reported reset time, so when this account is usable again is unknown."
            metrics.append(Metric(label: "Usable in", value: value,
                                  timing: usableAt.map { HomeInterfaceFormatting.scheduleText($0, now: now, calendar: .current) } ?? "",
                                  detail: detail))
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
        // A grant that expired after the count was observed, or an old or future observation, makes the count
        // historical, as on Home.
        let grantExpired = grants.contains { $0.expiresAt.map { $0 <= now } == true }
        let oldObservation = summary?.asOf.map { now.timeIntervalSince($0) >= 300 || $0 > now } == true
        let value = grantExpired || oldObservation ? "Last known \(count)" : "\(count) available"
        var lines = ["Earned resets: \(value)"]
        for grant in grants.sorted(by: { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }) {
            lines.append(grant.expiresAt.map { "\(InterfaceFormatting.compactExpiry($0, now: now)) · \(InterfaceFormatting.exactDate($0))" }
                ?? (grant.doesNotExpire ? "Does not expire" : "Expiration date unavailable"))
        }
        return Metric(label: "Earned resets", value: value, timing: timing, detail: lines.joined(separator: "\n"))
    }

    private static func accountState(_ snapshot: AccountSnapshot, now: Date) -> String? {
        let lastRead = snapshot.fetchedAt.map { " · last read \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        switch snapshot.state {
        case .authenticationRequired: return "Sign-in required"
        case .unavailable: return snapshot.windows.isEmpty ? nil : "Unavailable"
        case .stale: return "Stale" + lastRead
        case .available:
            if InterfaceFormatting.isOutdated(snapshot, now: now) { return "Stale" + lastRead }
            return snapshot.fetchedAt == nil && !snapshot.windows.isEmpty ? "Observation time unknown" : nil
        }
    }

}
