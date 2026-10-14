import AppKit
import Testing
import UsageCore
@testable import AIUsageStats

@MainActor
private final class MenuTarget: NSObject {
    @objc func open(_ sender: Any?) {}
    @objc func reconnect(_ sender: Any?) {}
}

/// MENU-13: an account with no reading has a state line and a recovery command like every other non-current
/// section, instead of a lone `Usage Unavailable` row.
@Test @MainActor
func accountWithoutReadingShowsAStateLineAndOpenAccount() {
    let profile = AccountProfile(provider: .codex, label: "Personal", source: .demo, providerEmail: "codex@example.invalid")
    let target = MenuTarget()
    let items = UsageMenu.accountItems(profiles: [profile], snapshots: [:], consoleMessages: [:], now: Date(), target: target,
                                       openAction: #selector(MenuTarget.open(_:)), reconnectAction: #selector(MenuTarget.reconnect(_:)))
    let titles = items.filter { !$0.isSeparatorItem && !$0.isSectionHeader }.map(\.title)
    #expect(titles == ["Unavailable", "Open Account"])
    let state = items.first { $0.title == "Unavailable" }
    #expect(state?.isEnabled == true)
    #expect(state?.representedObject as? UUID == profile.id)
    #expect(state?.toolTip?.contains("Choose Refresh All") == true)
}
