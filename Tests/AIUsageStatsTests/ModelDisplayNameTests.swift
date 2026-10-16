import Foundation
import Testing
import UsageCore
@testable import AIUsageStats

@Test
func modelIdentifiersReadAsDisplayNames() {
    #expect(InterfaceFormatting.modelDisplayName("claude-fable-5-1") == "Fable 5.1")
    #expect(InterfaceFormatting.modelDisplayName("claude-opus-5-5") == "Opus 5.5")
    #expect(InterfaceFormatting.modelDisplayName("claude-opus-5") == "Opus 5")
    #expect(InterfaceFormatting.modelDisplayName("gpt-6.1-sol") == "GPT-6.1 Sol")
    #expect(InterfaceFormatting.modelDisplayName("gpt-5.5") == "GPT-5.5")
}

@Test
func unknownModelIdentifierShowsAsLogged() {
    #expect(InterfaceFormatting.modelDisplayName("claude-3-5-sonnet-20241022") == "claude-3-5-sonnet-20241022")
    #expect(InterfaceFormatting.modelDisplayName("<synthetic>") == "<synthetic>")
}

@Test
func earnedResetsUseHomeVocabularyWithNextExpiry() throws {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let count = CreditBalance(id: "quota_reset_credits", title: "Earned resets", amount: 2, unit: .resets,
                              asOf: now.addingTimeInterval(-60))
    let grant = CreditBalance(id: "quota_reset_a", title: "Reset grant", amount: 1, unit: .resets,
                              expiresAt: now.addingTimeInterval(86_400), asOf: now.addingTimeInterval(-60), status: "available")
    let consumed = CreditBalance(id: "quota_reset_b", title: "Used grant", amount: 1, unit: .resets,
                                 expiresAt: now.addingTimeInterval(3_600), asOf: now.addingTimeInterval(-60), status: "consumed")
    let summary = try #require(InterfaceFormatting.earnedResets([count, grant, consumed], now: now))
    #expect(summary.value == "2 available")
    #expect(summary.timing == "Next expires in 1d 0h")
    #expect(InterfaceFormatting.earnedResets([count, grant], isCurrentReading: false, now: now)?.value == "Last known 2")
    #expect(InterfaceFormatting.earnedResets([], now: now) == nil)
}
