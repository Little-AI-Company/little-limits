import AppKit
import UsageCore

@MainActor
enum UsageMenu {
    private struct Metric {
        let label: String
        let value: String
        let timing: String
        let detail: String
        var tone: HomeReadingTone = .neutral
    }

    private enum AccountState {
        case signInRequired
        case unavailable
        case stale(lastRead: Date?)
        case observationTimeUnknown

        var text: String {
            switch self {
            case .signInRequired: "Sign-in required"
            case .unavailable: "Unavailable"
            case .stale(let lastRead): "Stale" + (lastRead.map { " · last read \($0.formatted(date: .omitted, time: .shortened))" } ?? "")
            case .observationTimeUnknown: "Observation time unknown"
            }
        }

        var symbolName: String {
            switch self {
            case .signInRequired: "person.crop.circle.badge.exclamationmark.fill"
            case .unavailable: "exclamationmark.circle"
            case .stale, .observationTimeUnknown: "clock"
            }
        }

        var symbolColor: NSColor {
            switch self {
            case .signInRequired: BrandPalette.destructive
            case .unavailable, .stale, .observationTimeUnknown: BrandPalette.secondaryLabel
            }
        }
    }

    private static let imageSide: CGFloat = 16

    static func progress(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    static func stateLine(_ title: String, detail: String?, target: AnyObject, action: Selector,
                          accountID: UUID? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.representedObject = accountID
        item.toolTip = detail
        return item
    }

    static func accountItems(profiles: [AccountProfile], snapshots: [UUID: AccountSnapshot],
                             consoleMessages: [UUID: String], now: Date,
                             target: AnyObject, homeAction: Selector, openAction: Selector, reconnectAction: Selector,
                             refreshAction: Selector) -> [NSMenuItem] {
        let font = NSFont.menuFont(ofSize: 0)
        let valueFont = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let overview = UsageOverview(profiles: profiles, snapshots: snapshots, now: now)
        let totals = overview.providers.filter { $0.accountCount > 1 }.map { provider in
            (provider: provider.provider, metrics: totalMetrics(provider, overview: overview, now: now))
        }.filter { !$0.metrics.isEmpty }
        let shortNames = Dictionary(uniqueKeysWithValues: overview.accounts.map { ($0.id, $0.shortIdentity) })
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
            item.setImage(stateImage(metric.tone.symbolName, color: metric.tone.symbolColor, description: metric.tone.word))
            if let word = metric.tone.word {
                item.setAccessibilityLabel("\(metric.label), \(metric.value), \(word)\(metric.timing.isEmpty ? "" : ", \(metric.timing)")")
            }
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
            let heading = NSMenuItem.sectionHeader(title: "\(InterfaceFormatting.provider(total.provider)) · All accounts")
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
            let name = shortNames[profile.id] ?? InterfaceFormatting.accountIdentity(profile)
            let observation = snapshot?.fetchedAt.map { "Last reading: \(InterfaceFormatting.exactDate($0))" } ?? HomeInterfaceFormatting.noReadingHelp
            let heading = NSMenuItem.sectionHeader(title: "\(provider) · \(name)")
            heading.image = ProviderIcons.images[profile.provider]
            if #available(macOS 27, *) { heading.preferredImageVisibility = .visible }
            heading.toolTip = [email == name ? nil : email, observation, snapshot?.detail].compactMap { $0 }.joined(separator: "\n")
            items.append(heading)
            let state = snapshot.flatMap { accountState($0, now: now) }
                ?? ((snapshot?.windows ?? []).isEmpty ? .unavailable : nil)
            if let state {
                let item = stateLine(state.text, detail: [observation, snapshot?.detail].compactMap { $0 }.joined(separator: "\n"),
                                     target: target, action: openAction, accountID: profile.id)
                item.setImage(stateImage(state.symbolName, color: state.symbolColor, description: state.text))
                items.append(item)
            }
            if let message = consoleMessages[profile.id] {
                let item = stateLine("API Credits need attention", detail: message, target: target, action: openAction, accountID: profile.id)
                item.setImage(stateImage("exclamationmark.circle", color: BrandPalette.secondaryLabel, description: "Needs attention"))
                items.append(item)
            }
            items += metrics[index].map { readingItem($0, action: openAction, accountID: profile.id) }
            if state != nil || consoleMessages[profile.id] != nil {
                let reconnectable = profile.source != .codexDefaultLogin
                let (title, action, help): (String, Selector, String?) = switch state {
                case .signInRequired where reconnectable: ("Reconnect…", reconnectAction, nil)
                case .signInRequired: ("Refresh", refreshAction, "Sign in to the Codex CLI in Terminal, then choose Refresh.")
                case .unavailable, .stale: ("Refresh", refreshAction, "Read this account's usage again")
                case .observationTimeUnknown, nil: ("Open Account", openAction, nil)
                }
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = target
                item.representedObject = profile.id
                item.toolTip = help
                item.setImage(stateImage(nil, color: .labelColor, description: nil))
                items.append(item)
            }
            items.append(.separator())
        }
        return items
    }

    private static func totalMetrics(_ provider: ProviderQuotaOverview, overview: UsageOverview, now: Date) -> [Metric] {
        let names = Dictionary(uniqueKeysWithValues: overview.accounts.map { ($0.id, "\($0.profile.provider.title) \($0.shortIdentity)") })
        func isShared(_ pool: QuotaPool) -> Bool { pool.countedAccountIDs.count + pool.unknownAccountIDs.count > 1 }
        guard isShared(provider.weekly) else { return [] }
        var metrics = ([provider.weekly] + provider.scopedWeekly.filter(isShared)).map { pool in
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
            let (described, timing) = InterfaceFormatting.reading(window, snapshot: snapshot, now: now)
            let outdated = InterfaceFormatting.isOutdated(snapshot, now: now)
            let value = outdated ? InterfaceFormatting.lastKnownRemaining(window) : InterfaceFormatting.remaining(window)
            let measured = !outdated && window.isActive != false && window.utilizationPercent?.isFinite == true
            metrics.append(Metric(label: InterfaceFormatting.usageTitle(window), value: value, timing: timing,
                                  detail: "\(InterfaceFormatting.usageTitle(window)): \(described). \(InterfaceFormatting.reset(window, snapshot: snapshot, now: now))",
                                  tone: measured ? HomeInterfaceFormatting.tone(for: window, now: now) : .neutral))
        }
        if case .exhausted(let usableAt) = AccountUsability(snapshot: snapshot, now: now) {
            let value = usableAt.map { UsageFormatting.countdown(to: $0, now: now) } ?? ""
            let detail = usableAt.map { "Usable again \(InterfaceFormatting.exactDate($0)), when the last of its 5-hour or weekly windows at 0% left resets." }
                ?? "A 5-hour or weekly window at 0% left has no reported reset time, so when this account is usable again is unknown."
            metrics.append(Metric(label: usableAt == nil ? "Usable time unknown" : "Usable in", value: value,
                                  timing: usableAt.map { HomeInterfaceFormatting.scheduleText($0, now: now, calendar: .current) } ?? "",
                                  detail: detail))
        }
        let credits = snapshot?.credits ?? UsageService.unavailableCredits(for: profile.provider)
        if let earned = earnedResets(credits, now: now) { metrics.append(earned) }
        for credit in credits where !isEarnedReset(credit) && !isPlaceholder(credit) {
            var timing: [String] = []
            if credit.source == .manual { timing.append("Manual") }
            if let date = credit.expiresAt { timing.append(InterfaceFormatting.creditExpiry(credit, date: date, now: now)) }
            else if credit.doesNotExpire { timing.append("No expiry") }
            if credit.source != .manual,
               credit.asOf.map({ !AccountSnapshot.isObservationCurrent($0, now: now) }) == true || credit.status == "Stale" {
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

    private static func isPlaceholder(_ credit: CreditBalance) -> Bool {
        credit.amount == nil && !credit.isUnlimited && credit.status == nil && credit.asOf == nil && credit.source != .manual
    }

    private static func earnedResets(_ credits: [CreditBalance], now: Date) -> Metric? {
        let summary = credits.first { $0.id == "quota_reset_credits" }
        let grants = credits.filter { isEarnedReset($0) && $0.id != "quota_reset_credits" }
        guard summary != nil || !grants.isEmpty else { return nil }
        let count = summary?.amount.map { NSDecimalNumber(decimal: $0).intValue } ?? grants.count
        let nextExpiry = grants.compactMap(\.expiresAt).filter { $0 > now }.min()
        let timing = nextExpiry.map { "Next expires in \(UsageFormatting.countdown(to: $0, now: now))" } ?? ""
        let grantExpired = grants.contains { $0.expiresAt.map { $0 <= now } == true }
        let oldObservation = summary?.asOf.map { !AccountSnapshot.isObservationCurrent($0, now: now) } == true
        let value = grantExpired || oldObservation ? "Last known \(count) available" : "\(count) available"
        var lines = ["Earned resets: \(value)"]
        for grant in grants.sorted(by: { ($0.expiresAt ?? .distantFuture) < ($1.expiresAt ?? .distantFuture) }) {
            lines.append(grant.expiresAt.map { "\(InterfaceFormatting.compactExpiry($0, now: now)) · \(InterfaceFormatting.exactDate($0))" }
                ?? (grant.doesNotExpire ? "Does not expire" : "Expiration date unavailable"))
        }
        return Metric(label: "Earned resets", value: value, timing: timing, detail: lines.joined(separator: "\n"))
    }

    private static func accountState(_ snapshot: AccountSnapshot, now: Date) -> AccountState? {
        switch snapshot.state {
        case .authenticationRequired: return .signInRequired
        case .unavailable: return snapshot.windows.isEmpty ? nil : .unavailable
        case .stale: return .stale(lastRead: snapshot.fetchedAt)
        case .available:
            if InterfaceFormatting.isOutdated(snapshot, now: now) { return .stale(lastRead: snapshot.fetchedAt) }
            return snapshot.fetchedAt == nil && !snapshot.windows.isEmpty ? .observationTimeUnknown : nil
        }
    }

    private static func stateImage(_ symbolName: String?, color: NSColor, description: String?) -> NSImage {
        let pointSize = NSFont.menuFont(ofSize: 0).pointSize - 2
        let image = NSImage(size: NSSize(width: imageSide, height: imageSide), flipped: false) { rect in
            guard let symbolName,
                  let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                    .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
                        .applying(NSImage.SymbolConfiguration(paletteColors: [color]))) else { return true }
            let size = symbol.size
            symbol.draw(in: NSRect(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2, width: size.width, height: size.height))
            return true
        }
        image.accessibilityDescription = description
        return image
    }
}

private extension NSMenuItem {
    func setImage(_ image: NSImage) {
        self.image = image
        if #available(macOS 27, *) { preferredImageVisibility = .visible }
    }
}
