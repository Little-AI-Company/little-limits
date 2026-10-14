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
                                                    detail: "OpenAI API balances are entered manually."),
                                      CreditBalance(id: "provider_credits", title: "Codex credits", amount: 14,
                                                    unit: .credits, asOf: now),
                                      CreditBalance(id: "quota_reset_credits", title: "Earned resets", amount: 2,
                                                    unit: .resets, asOf: now),
                                      CreditBalance(id: "quota_reset_example", title: "Example reset grant", amount: nil,
                                                    unit: .resets, expiresAt: now.addingTimeInterval(86_400),
                                                    asOf: now, status: "available")],
                            state: .available, detail: "Fictional demonstration data."),
            AccountSnapshot(profileID: profiles[2].id, fetchedAt: now,
                            windows: [UsageWindow(id: "five_hour", title: "5 hours", utilizationPercent: 100,
                                                  resetsAt: now.addingTimeInterval(3_600))],
                            credits: UsageService.unavailableCredits(for: .claude),
                            state: .available, detail: "Fictional demonstration data.")
        ]
    }

    public static let homeProfiles = [
        AccountProfile(id: homeClaudePersonalID, provider: .claude, label: "Personal", source: .demo,
                       providerEmail: "personal@example.invalid"),
        AccountProfile(id: homeClaudeStudioID, provider: .claude, label: "Studio", source: .demo,
                       providerEmail: "studio@example.invalid"),
        AccountProfile(id: homeCodexWorkID, provider: .codex, label: "Work", source: .demo,
                       providerAccountID: "home-codex-work", providerEmail: "work@example.invalid"),
        AccountProfile(id: homeCodexPersonalID, provider: .codex, label: "Personal", source: .demo,
                       providerAccountID: "home-codex-personal", providerEmail: "codex@example.invalid")
    ]

    public static var homeSnapshots: [AccountSnapshot] {
        let now = Date()
        return homeDemonstrations(at: now).map { demonstration in
            AccountSnapshot(profileID: demonstration.profileID, fetchedAt: now, windows: demonstration.windows,
                            credits: demonstration.credits, state: .available, detail: "Fictional demonstration data.",
                            planName: demonstration.planName)
        }
    }

    /// One fresh Claude reading, one Claude sign-in request, one Codex reading from 18 minutes ago, and one Codex account with no reading.
    public static var homeReadingStateSnapshots: [AccountSnapshot] {
        let now = Date()
        let demonstrations = homeDemonstrations(at: now)
        let personal = demonstrations[0]
        let studio = demonstrations[1]
        let work = demonstrations[2]
        let previousReading = now.addingTimeInterval(-18 * 60)
        let previousCredits = work.credits.map { credit in
            CreditBalance(id: credit.id, title: credit.title, amount: credit.amount, unit: credit.unit,
                          expiresAt: credit.expiresAt, source: credit.source, asOf: previousReading,
                          detail: credit.detail, isUnlimited: credit.isUnlimited, status: credit.status,
                          doesNotExpire: credit.doesNotExpire, currencyCode: credit.currencyCode,
                          originalAmount: credit.originalAmount)
        }
        return [
            AccountSnapshot(profileID: personal.profileID, fetchedAt: now, windows: personal.windows,
                            credits: personal.credits, state: .available, detail: "Fictional demonstration data.",
                            planName: personal.planName),
            AccountSnapshot(profileID: studio.profileID, fetchedAt: now, windows: studio.windows,
                            credits: studio.credits, state: .authenticationRequired, detail: "Sign in to this Claude account.",
                            planName: studio.planName),
            AccountSnapshot(profileID: work.profileID, fetchedAt: previousReading, windows: work.windows,
                            credits: previousCredits, state: .stale, detail: "The last reading is 18 minutes old.",
                            planName: work.planName)
        ]
    }

    private static let homeClaudePersonalID = UUID(uuidString: "00000000-0000-0000-0000-000000000011")!
    private static let homeClaudeStudioID = UUID(uuidString: "00000000-0000-0000-0000-000000000012")!
    private static let homeCodexWorkID = UUID(uuidString: "00000000-0000-0000-0000-000000000013")!
    private static let homeCodexPersonalID = UUID(uuidString: "00000000-0000-0000-0000-000000000014")!

    private struct HomeDemonstration {
        let profileID: UUID
        let windows: [UsageWindow]
        let credits: [CreditBalance]
        let planName: String
    }

    /// Durations are representative fixture data. A parser does not invent a duration the provider did not report.
    private static func homeDemonstrations(at now: Date) -> [HomeDemonstration] {
        let hour: TimeInterval = 3_600
        let day: TimeInterval = 86_400
        func window(id: String, title: String, used: Double, resetsAfter: TimeInterval?, duration: Int) -> UsageWindow {
            UsageWindow(id: id, title: title, utilizationPercent: used,
                        resetsAt: resetsAfter.map { now.addingTimeInterval($0) }, windowDurationMinutes: duration)
        }
        func earnedResets(_ amount: Int, expiresAfter: TimeInterval) -> [CreditBalance] {
            [CreditBalance(id: "quota_reset_credits", title: "Earned resets", amount: Decimal(amount), unit: .resets,
                           asOf: now)] + (0..<amount).map { index in
                CreditBalance(id: "quota_reset_example_\(index + 1)", title: "Earned reset", amount: nil,
                              unit: .resets, expiresAt: now.addingTimeInterval(expiresAfter), asOf: now,
                              status: "available")
            }
        }
        return [
            HomeDemonstration(profileID: homeClaudePersonalID, windows: [
                window(id: "five_hour", title: "5 hours", used: 1, resetsAfter: 2 * hour, duration: 300),
                window(id: "seven_day", title: "7 days", used: 25, resetsAfter: 3 * day, duration: 10_080),
                window(id: "seven_day_fable_5", title: "7 days (Fable 5)", used: 49, resetsAfter: 5 * day, duration: 10_080)
            ], credits: [], planName: "Max"),
            HomeDemonstration(profileID: homeClaudeStudioID, windows: [
                window(id: "five_hour", title: "5 hours", used: 0, resetsAfter: nil, duration: 300),
                window(id: "seven_day", title: "7 days", used: 0, resetsAfter: 6 * day, duration: 10_080),
                window(id: "seven_day_sonnet", title: "7 days (Sonnet)", used: 0, resetsAfter: 6 * day, duration: 10_080)
            ], credits: [], planName: "Max"),
            HomeDemonstration(profileID: homeCodexWorkID, windows: [
                window(id: "primary", title: "5 hours", used: 37, resetsAfter: 4 * hour, duration: 300),
                window(id: "weekly", title: "7 days", used: 83, resetsAfter: 4 * day, duration: 10_080)
            ], credits: earnedResets(2, expiresAfter: 12 * day), planName: "Pro"),
            HomeDemonstration(profileID: homeCodexPersonalID, windows: [
                window(id: "primary", title: "5 hours", used: 100, resetsAfter: 90 * 60, duration: 300),
                window(id: "weekly", title: "7 days", used: 100, resetsAfter: 2 * day, duration: 10_080)
            ], credits: earnedResets(3, expiresAfter: 15 * day), planName: "Plus")
        ]
    }
}
