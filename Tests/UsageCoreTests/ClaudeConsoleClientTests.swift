import Foundation
import XCTest
@testable import UsageCore

final class ClaudeConsoleClientTests: XCTestCase {
    private let organizationID = "A122F9F0-0BB2-4DB9-9B76-0D5942F95617"
    private let now = Date(timeIntervalSince1970: 1_791_504_000)

    func testPurchasedAndPromotionalCreditsRemainSeparate() throws {
        let balance = try decode(#"""
        {
          "amount": 22500, "currency": "USD",
          "tranches": [{"id":"purchase-a","currency":"USD","remaining_amount_minor_units":2500}],
          "promo_tranches": [{"id":"grant-a","currency":"USD","granted_amount_minor_units":20000,
            "remaining_amount_minor_units":18765,"granted_at":"2026-10-08T12:00:00.123Z",
            "expires_at":"2026-11-08T12:00:00Z","scope":{"kind":"scoped","applies_to":[{"product":"api"}]}}]
        }
        """#)
        XCTAssertEqual(balance.organizationID, organizationID.lowercased())
        XCTAssertEqual(balance.totalBalance?.amount, Decimal(string: "225.00"))
        XCTAssertEqual(balance.purchasedBalances.first?.amount, 25)
        let grant = try XCTUnwrap(balance.promotionalGrants.first)
        XCTAssertEqual(grant.grantedAmount, 200)
        XCTAssertEqual(grant.remainingAmount, Decimal(string: "187.65"))
        XCTAssertEqual(grant.expiresAt, isoDate("2026-11-08T12:00:00Z"))
        XCTAssertEqual(grant.grantedAt?.timeIntervalSince1970, 1_791_460_800.123)
        XCTAssertEqual(balance.credits.map(\.id), ["api_balance_USD", "console_grant_grant-a"])
        XCTAssertEqual(balance.credits.last?.originalAmount, 200)
        XCTAssertEqual(balance.credits.last?.currencyCode, "USD")
        XCTAssertFalse(balance.credits.last?.title.contains("Monthly") ?? true)
    }

    func testMultipleCurrencyMinorUnitsAreNotCombined() throws {
        let balance = try decode(#"""
        {"tranches":[
          {"currency":"EUR","remaining_amount_minor_units":1234},
          {"currency":"EUR","remaining_amount_minor_units":6},
          {"currency":"JPY","remaining_amount_minor_units":1500},
          {"currency":"KWD","remaining_amount_minor_units":12345}],
         "promo_tranches":[]}
        """#)
        XCTAssertEqual(balance.purchasedBalances.map(\.currency), ["EUR", "JPY", "KWD"])
        XCTAssertEqual(balance.purchasedBalances.map(\.amount), [Decimal(string: "12.40")!, 1500, Decimal(string: "12.345")!])
        XCTAssertEqual(balance.credits.map(\.unit), [.currency, .currency, .currency])
    }

    func testExpiredTranchesAreExcludedAndExhaustedGrantsStayVisible() throws {
        let balance = try decode(#"""
        {"amount":2000,"currency":"USD","tranches":[
          {"currency":"USD","remaining_amount_minor_units":2000,"expires_at":"2026-01-01T00:00:00Z"}],
         "promo_tranches":[
          {"id":"expired","currency":"USD","granted_amount_minor_units":10000,"remaining_amount_minor_units":10000,
           "expires_at":"2026-01-01T00:00:00Z"},
          {"id":"exhausted","currency":"USD","granted_amount_minor_units":10000,"remaining_amount_minor_units":0,
           "expires_at":"2027-01-01T00:00:00Z"}]}
        """#)
        XCTAssertEqual(balance.purchasedBalances.first?.amount, 0)
        XCTAssertEqual(balance.promotionalGrants.map(\.id), ["exhausted"])
        XCTAssertEqual(balance.promotionalGrants.first?.remainingAmount, 0)
    }

    func testNullListsDoNotTurnAggregateIntoPurchasedBalance() throws {
        let balance = try decode(#"{"amount":12000,"currency":"USD","tranches":null,"promo_tranches":null}"#)
        XCTAssertEqual(balance.totalBalance?.amount, 120)
        XCTAssertTrue(balance.purchasedBalances.isEmpty)
        XCTAssertTrue(balance.promotionalGrants.isEmpty)
        XCTAssertTrue(balance.credits.isEmpty)
        let missingCurrency = try decode(#"{"amount":12000,"tranches":null,"promo_tranches":null}"#)
        XCTAssertNil(missingCurrency.totalBalance)
        XCTAssertThrowsError(try decode("{}"))
    }

    func testUnknownScopeIsExplicitAndKnownNonAPIScopeIsNotPublishedAsAPICredit() throws {
        let balance = try decode(#"""
        {"promo_tranches":[
          {"id":"unknown","currency":"USD","granted_amount_minor_units":1000,"remaining_amount_minor_units":500,
           "expires_at":null,"scope":null},
          {"id":"code-only","currency":"USD","granted_amount_minor_units":1000,"remaining_amount_minor_units":500,
           "scope":{"kind":"scoped","applies_to":[{"product":"code_api"}]}}]}
        """#)
        XCTAssertEqual(balance.promotionalGrants.count, 2)
        XCTAssertNil(balance.promotionalGrants.first?.supportsAPI)
        XCTAssertEqual(balance.credits.map(\.id), ["console_grant_unknown"])
        XCTAssertEqual(balance.credits.first?.detail, "Scope unavailable")
        XCTAssertEqual(balance.credits.first?.title, "Promotional grant (scope unavailable)")
        XCTAssertNil(balance.credits.first?.expiresAt)
        XCTAssertFalse(balance.credits.first?.doesNotExpire ?? true)
    }

    func testInvalidAmountsDatesAndCurrenciesAreRejected() throws {
        let fixtures = [
            #"{"tranches":[{"currency":"USD","remaining_amount_minor_units":-1}]}"#,
            #"{"tranches":[{"currency":"USD","remaining_amount_minor_units":1.5}]}"#,
            #"{"tranches":[{"currency":"USD","granted_amount_minor_units":5,"remaining_amount_minor_units":10}]}"#,
            #"{"tranches":[{"currency":"USD","remaining_amount_minor_units":10,"expires_at":"not-a-date"}]}"#,
            #"{"tranches":[{"currency":"INVALID","remaining_amount_minor_units":10}]}"#,
            #"{"promo_tranches":[{"currency":"USD","granted_amount_minor_units":10,"remaining_amount_minor_units":11}]}"#,
            #"{"promo_tranches":[{"id":"same","currency":"USD","granted_amount_minor_units":10,"remaining_amount_minor_units":5},{"id":"same","currency":"USD","granted_amount_minor_units":10,"remaining_amount_minor_units":5}]}"#
        ]
        for fixture in fixtures { XCTAssertThrowsError(try decode(fixture), fixture) }
    }

    func testHTMLLoginResponseAndUnsafeOrganizationIdentifiersAreRejected() throws {
        XCTAssertThrowsError(try decode("  <!DOCTYPE html><html>Sign in</html>")) { error in
            guard case UsageError.authenticationRequired = error else { return XCTFail("Expected authentication request.") }
        }
        for identifier in ["../account", "org?other=1", "https://example.com", organizationID + "/usage", " " + organizationID] {
            XCTAssertThrowsError(try ClaudeConsoleClient.balanceURL(organizationID: identifier))
            XCTAssertThrowsError(try ClaudeConsoleBalance.decode(Data("{}".utf8), organizationID: identifier))
        }
        let endpoint = try ClaudeConsoleClient.balanceURL(organizationID: organizationID)
        XCTAssertEqual(endpoint.host, "platform.claude.com")
        XCTAssertEqual(endpoint.scheme, "https")
        XCTAssertEqual(endpoint.path, "/api/organizations/\(organizationID.lowercased())/prepaid/credits")
        XCTAssertNil(endpoint.query)
    }

    func testAccountDiscoveryUsesAccountMembershipsWithoutCredentials() throws {
        let fixture = #"""
        {"uuid":"32AD236B-82B9-4F82-AFFD-7195FB5987CE","email_address":"fixture@example.com",
         "memberships":[{"role":"owner","organization":{"uuid":"A122F9F0-0BB2-4DB9-9B76-0D5942F95617",
                          "name":"Fixture organization","capabilities":["api"]}}]}
        """#
        let account = try ClaudeConsoleAccount.decode(Data(fixture.utf8))
        XCTAssertEqual(account.email, "fixture@example.com")
        XCTAssertEqual(account.organizations.first?.id, organizationID.lowercased())
        XCTAssertEqual(account.organizations.first?.capabilities, ["api"])
        XCTAssertEqual(account.organizations.first?.role, "owner")
        XCTAssertEqual(ClaudeConsoleClient.accountURL.absoluteString, "https://platform.claude.com/api/account")
    }

    private func decode(_ json: String) throws -> ClaudeConsoleBalance {
        try ClaudeConsoleBalance.decode(Data(json.utf8), organizationID: organizationID, observedAt: now)
    }

    private func isoDate(_ text: String) -> Date? { ISO8601DateFormatter().date(from: text) }
}
