import Foundation

public enum DemoFixtures {
    public static let profiles = [
        AccountProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, provider: .claude,
                       label: "Example personal", source: .demo, providerEmail: "personal@example.invalid", sourcePath: "/Example/claude-personal"),
        AccountProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, provider: .codex,
                       label: "Example work", source: .demo, providerAccountID: "example-codex-account", providerEmail: "person@example.invalid"),
        AccountProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, provider: .claude,
                       label: "Example research", source: .demo, providerEmail: "research.department@example.invalid"),
        AccountProfile(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, provider: .claude,
                       label: "Example unverified", source: .demo)
    ]

    public static var snapshots: [AccountSnapshot] {
        let now = Date()
        return [
            AccountSnapshot(profileID: profiles[0].id, fetchedAt: now,
                            windows: [UsageWindow(id: "five_hour", title: "5 hours", utilizationPercent: 37,
                                                  resetsAt: now.addingTimeInterval(7_200)),
                                      UsageWindow(id: "seven_day", title: "7 days", utilizationPercent: 61,
                                                  resetsAt: now.addingTimeInterval(172_800))],
                            credits: [CreditBalance(id: "api_balance", title: "Purchased API credits", amount: 12.50,
                                                    source: .manual, asOf: now, detail: "Fictional manual balance."),
                                      CreditBalance(id: "monthly_grant", title: "Monthly included API grant", amount: 8,
                                                    expiresAt: now.addingTimeInterval(604_800), source: .manual, asOf: now)], state: .available,
                            detail: "Fictional demonstration data."),
            AccountSnapshot(profileID: profiles[1].id, fetchedAt: now,
                            windows: [UsageWindow(id: "codex_primary", title: "5 hours", utilizationPercent: 82,
                                                  resetsAt: now.addingTimeInterval(3_600)),
                                      UsageWindow(id: "codex_secondary", title: "7 days", utilizationPercent: 29,
                                                  resetsAt: now.addingTimeInterval(345_600))],
                            credits: [CreditBalance(id: "api_balance", title: "OpenAI API credits", amount: nil,
                                                    detail: "The connected CLI does not expose API billing balances."),
                                      CreditBalance(id: "provider_credits", title: "Codex credits", amount: 14,
                                                    unit: .credits, asOf: now),
                                      CreditBalance(id: "quota_reset_credits", title: "Quota resets", amount: 2,
                                                    unit: .resets, asOf: now),
                                      CreditBalance(id: "quota_reset_example", title: "Example reset grant", amount: nil,
                                                    unit: .resets, expiresAt: now.addingTimeInterval(86_400),
                                                    asOf: now, status: "available")],
                            state: .available, detail: "Fictional demonstration data.")
        ]
    }
}
