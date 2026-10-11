import Foundation
import Testing
@testable import UsageCore

private let monthlyOrganizationID = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
private let monthlyObservedAt = Date(timeIntervalSince1970: 1_791_720_000)
private let monthlyLinkState = Data(#"{"status":"linked","plan":"max","monthly_credit_usd_cents":5000}"#.utf8)
private let monthlyInvoices = Data(#"{"invoices":[{"name":"API credit (Max 20x)","amount":5000,"currency":"USD","effective_at":"2026-10-09T00:00:00Z","expires_at":"2027-11-09T00:00:00Z"}]}"#.utf8)

private func monthlyBalance(purchasedCents: Int = 1200, monthlyCents: Int = 3000) -> Data {
    Data("""
    {"amount":\(purchasedCents + monthlyCents + 200),"currency":"USD",
     "tranches":[{"id":"purchased","currency":"USD","remaining_amount_minor_units":\(purchasedCents)}],
     "promo_tranches":[
      {"id":"monthly","currency":"USD","granted_amount_minor_units":5000,"remaining_amount_minor_units":\(monthlyCents),
       "granted_at":"2026-10-09T00:00:00Z","expires_at":"2027-11-09T00:00:00Z","scope":{"kind":"unscoped"}},
      {"id":"promotion","currency":"USD","granted_amount_minor_units":500,"remaining_amount_minor_units":200,
       "granted_at":"2026-09-09T00:00:00Z","expires_at":"2027-12-09T00:00:00Z","scope":{"kind":"unscoped"}}]}
    """.utf8)
}

private func monthlyService(directory: URL) async throws -> (UsageService, AccountProfile) {
    let helper = directory.appendingPathComponent("capture-helper")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: helper)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helper.path)
    let service = UsageService(directory: directory.appendingPathComponent("Store"), captureHelperURL: helper)
    let profile = try await service.importClaudeCLI(label: "Monthly grant fixture", configurationURL: directory.appendingPathComponent("Claude"))
    try await service.setClaudeConsoleConnection(accountID: profile.id, organizationID: monthlyOrganizationID, expectedIdentity: nil)
    return (service, profile)
}

@Test func identifiedMonthlyGrantOverridesManualFallbackWithoutRenamingOtherPromotions() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AIUsageStatsMonthly-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (service, profile) = try await monthlyService(directory: directory)
    try await service.setManualCredit(accountID: profile.id, credit: CreditBalance(id: "monthly_grant", title: "Manual monthly", amount: 7, source: .manual))
    try await service.updateClaudeConsoleCredits(accountID: profile.id, organizationID: monthlyOrganizationID, responseData: monthlyBalance(),
                                                expectedIdentity: nil, linkStateData: monthlyLinkState, invoicesData: monthlyInvoices, observedAt: monthlyObservedAt)
    let snapshot = try #require(await service.snapshot(for: profile.id))
    let monthly = try #require(snapshot.credits.first { $0.id == "monthly_grant_monthly" })
    #expect(monthly.amount == 30)
    #expect(monthly.originalAmount == 50)
    #expect(monthly.unit == .currency && monthly.currencyCode == "USD")
    #expect(monthly.asOf == monthlyObservedAt)
    #expect(monthly.expiresAt == ISO8601DateFormatter().date(from: "2027-11-09T00:00:00Z"))
    #expect(!snapshot.credits.contains { $0.id == "monthly_grant" })
    #expect(snapshot.credits.first { $0.id == "console_grant_promotion" }?.title == "Promotional API grant")
    #expect(snapshot.credits.first { $0.id == "api_balance_USD" }?.amount == 12)
    #expect(await service.manualCredits(for: profile.id).first { $0.id == "monthly_grant" }?.amount == 7)
}

@Test func monthlyMetadataFailureRetainsDatedStaleGrantAndFreshPurchasedBalance() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AIUsageStatsMonthly-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (service, profile) = try await monthlyService(directory: directory)
    try await service.updateClaudeConsoleCredits(accountID: profile.id, organizationID: monthlyOrganizationID, responseData: monthlyBalance(),
                                                expectedIdentity: nil, linkStateData: monthlyLinkState, invoicesData: monthlyInvoices, observedAt: monthlyObservedAt)
    let refreshedAt = monthlyObservedAt.addingTimeInterval(30)
    try await service.updateClaudeConsoleCredits(accountID: profile.id, organizationID: monthlyOrganizationID,
                                                responseData: monthlyBalance(purchasedCents: 3400, monthlyCents: 2000), expectedIdentity: nil,
                                                linkStateData: monthlyLinkState, invoicesData: Data("<html>Sign in</html>".utf8), observedAt: refreshedAt)
    let snapshot = try #require(await service.snapshot(for: profile.id))
    let monthly = try #require(snapshot.credits.first { $0.id == "monthly_grant_monthly" })
    #expect(monthly.amount == 30)
    #expect(monthly.asOf == monthlyObservedAt)
    #expect(monthly.status == "Stale")
    #expect(monthly.detail?.contains("Monthly invoices could not be read") == true)
    #expect(!snapshot.credits.contains { $0.id == "console_grant_monthly" || $0.id == "monthly_grant" })
    let purchased = try #require(snapshot.credits.first { $0.id == "api_balance_USD" })
    #expect(purchased.amount == 34 && purchased.asOf == refreshedAt)
    #expect(purchased.status == nil)
    #expect(snapshot.credits.first { $0.id == "console_grant_promotion" }?.asOf == refreshedAt)
    let reloaded = UsageService(directory: directory.appendingPathComponent("Store"))
    _ = try await reloaded.load()
    #expect(await reloaded.snapshot(for: profile.id)?.credits.first { $0.id == monthly.id }?.status == "Stale")
    try await service.updateClaudeConsoleCredits(accountID: profile.id, organizationID: monthlyOrganizationID, responseData: monthlyBalance(),
                                                expectedIdentity: nil, observedAt: refreshedAt, monthlyMetadataError: "Monthly details unavailable.")
    #expect(await service.snapshot(for: profile.id)?.credits.first { $0.id == monthly.id }?.detail == monthly.detail)
    try await service.setClaudeConsoleConnection(accountID: profile.id, organizationID: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", expectedIdentity: nil)
    #expect(await service.snapshot(for: profile.id)?.credits.contains { $0.id.hasPrefix("monthly_grant_") } == false)
}

@Test func genericPromotionsKeepMonthlyManualFallbackAndUnknownMonthlyState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AIUsageStatsMonthly-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let (service, profile) = try await monthlyService(directory: directory)
    let noInvoices = Data(#"{"invoices":[]}"#.utf8)
    try await service.updateClaudeConsoleCredits(accountID: profile.id, organizationID: monthlyOrganizationID, responseData: monthlyBalance(),
                                                expectedIdentity: nil, linkStateData: monthlyLinkState, invoicesData: noInvoices, observedAt: monthlyObservedAt)
    let unknown = try #require(await service.snapshot(for: profile.id))
    #expect(unknown.credits.first { $0.id == "monthly_grant" }?.amount == nil)
    #expect(unknown.credits.first { $0.id == "monthly_grant" }?.status == "Balance unidentified")
    #expect(unknown.credits.contains { $0.id == "console_grant_monthly" })
    try await service.setManualCredit(accountID: profile.id, credit: CreditBalance(id: "monthly_grant", title: "Manual monthly", amount: 7, source: .manual))
    let manual = try #require(await service.snapshot(for: profile.id)?.credits.first { $0.id == "monthly_grant" })
    #expect(manual.amount == 7 && manual.source == .manual)
    #expect(await service.snapshot(for: profile.id)?.credits.contains { $0.id == "console_grant_monthly" } == true)
}
