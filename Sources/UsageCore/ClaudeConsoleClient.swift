import Foundation

/// Console data is fetched by an isolated browser session. This type never owns provider cookies.
public enum ClaudeConsoleClient {
    public static let accountURL = URL(string: "https://platform.claude.com/api/account")!

    public static func balanceURL(organizationID: String) throws -> URL {
        let identifier = try validatedOrganizationID(organizationID)
        return URL(string: "https://platform.claude.com/api/organizations/\(identifier)/prepaid/credits")!
    }

    public static func linkStateURL(organizationID: String) throws -> URL {
        let identifier = try validatedOrganizationID(organizationID)
        return URL(string: "https://platform.claude.com/api/quirky-lollipop/organizations/\(identifier)/link-state")!
    }

    public static func invoicesURL(organizationID: String) throws -> URL {
        let identifier = try validatedOrganizationID(organizationID)
        return URL(string: "https://platform.claude.com/api/organizations/\(identifier)/invoices?limit=25")!
    }

    static func validatedOrganizationID(_ value: String) throws -> String {
        guard let identifier = UUID(uuidString: value), identifier.uuidString.lowercased() == value.lowercased() else {
            throw UsageError.invalidConfiguration("Claude Console organization must be a UUID.")
        }
        return identifier.uuidString.lowercased()
    }

    static func decode<Response: Decodable>(_ type: Response.Type, from data: Data) throws -> Response {
        if let text = String(data: data.prefix(256), encoding: .utf8),
           text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") {
            throw UsageError.authenticationRequired("Sign in to Claude Console to refresh API credits.")
        }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw UsageError.providerFailure("Claude Console returned an unsupported response.") }
    }
}

public struct ClaudeConsoleOrganization: Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let role: String?
    public let capabilities: [String]
}

public struct ClaudeConsoleAccount: Sendable, Equatable {
    public let accountID: String
    public let email: String?
    public let organizations: [ClaudeConsoleOrganization]

    public static func decode(_ data: Data) throws -> Self {
        struct Organization: Decodable { let uuid: String; let name: String?; let capabilities: [String]? }
        struct Membership: Decodable { let role: String?; let organization: Organization }
        struct Response: Decodable { let uuid: String; let email_address: String?; let memberships: [Membership]? }
        let response = try ClaudeConsoleClient.decode(Response.self, from: data)
        _ = try ClaudeConsoleClient.validatedOrganizationID(response.uuid)
        let organizations = try (response.memberships ?? []).map { membership in
            let value = membership.organization
            return ClaudeConsoleOrganization(id: try ClaudeConsoleClient.validatedOrganizationID(value.uuid),
                                             name: value.name ?? value.uuid, role: membership.role,
                                             capabilities: value.capabilities ?? [])
        }
        return Self(accountID: response.uuid.lowercased(), email: response.email_address, organizations: organizations)
    }
}

public struct ClaudeConsoleMoney: Sendable, Equatable {
    public let currency: String
    public let amount: Decimal
}

/// Plan linkage identifies eligibility and allowance, not an individual promotional grant's origin.
public struct ClaudeConsoleLinkState: Sendable, Equatable {
    public enum Status: String, Decodable, Sendable { case eligible, linked, ineligible }

    public let organizationID: String
    public let status: Status
    public let plan: String?
    public let monthlyAllowance: ClaudeConsoleMoney?

    public static func decode(_ data: Data, organizationID: String) throws -> Self {
        struct Response: Decodable {
            let status: Status
            let plan: String?
            let monthly_credit_usd_cents: Decimal?
        }
        let identifier = try ClaudeConsoleClient.validatedOrganizationID(organizationID)
        let response = try ClaudeConsoleClient.decode(Response.self, from: data)
        let plan = response.plan.flatMap { $0.isEmpty ? nil : $0 }
        guard response.status != .eligible || plan != nil else {
            throw UsageError.providerFailure("Claude Console did not identify the eligible plan.")
        }
        let allowance: ClaudeConsoleMoney?
        if response.status != .ineligible, let cents = response.monthly_credit_usd_cents {
            guard cents > 0 else {
                throw UsageError.providerFailure("Claude Console returned an invalid monthly allowance.")
            }
            allowance = ClaudeConsoleMoney(currency: "USD", amount: try ConsoleCurrency.majorUnits(cents, currency: "USD"))
        } else { allowance = nil }
        return Self(organizationID: identifier, status: response.status, plan: plan, monthlyAllowance: allowance)
    }

    func monthlyCredit(observedAt: Date) -> CreditBalance {
        let allowance = monthlyAllowance.map { " The plan allowance is USD \(NSDecimalNumber(decimal: $0.amount).stringValue) per billing cycle." } ?? ""
        let detail: String
        let creditStatus: String
        switch status {
        case .eligible:
            creditStatus = "Not linked"
            detail = "An eligible Claude plan can be linked to this Console organization in Claude Settings > Billing.\(allowance) No monthly balance has been established."
        case .linked:
            creditStatus = "Balance unidentified"
            detail = "This Console organization is linked to a Claude plan.\(allowance) No promotional grant could be uniquely matched to a monthly API credit invoice, so the remaining monthly balance and expiry are unknown."
        case .ineligible:
            creditStatus = "Not eligible"
            detail = "Console reports no eligible Claude plan for this organization. Existing promotional grants remain separate."
        }
        return CreditBalance(id: "monthly_grant", title: "Monthly included API grant", amount: nil,
                             asOf: observedAt, detail: detail, status: creditStatus)
    }
}

/// Invoice names establish origin; balances and expiry still come from the matching promotional tranche.
public struct ClaudeConsoleInvoices: Sendable, Equatable {
    public let organizationID: String
    private let monthlyReferences: [ConsoleMonthlyGrantReference]

    public static func decode(_ data: Data, organizationID: String) throws -> Self {
        struct Invoice: Decodable {
            let name: String?
            let amount: Decimal?
            let currency: String?
            let effective_at: String?
            let expires_at: String?
        }
        struct Response: Decodable { let invoices: [Invoice] }
        let identifier = try ClaudeConsoleClient.validatedOrganizationID(organizationID)
        let response = try ClaudeConsoleClient.decode(Response.self, from: data)
        let names: Set<String> = ["API credit (Max 5x)", "API credit (Max 20x)", "API credit (Team)"]
        var references: [ConsoleMonthlyGrantReference] = []
        for invoice in response.invoices {
            guard let name = invoice.name, names.contains(name),
                  invoice.currency == nil || invoice.currency?.uppercased() == "USD",
                  let cents = invoice.amount, cents > 0,
                  let grantedAt = try ConsoleDate.parse(invoice.effective_at),
                  let expiresAt = try ConsoleDate.parse(invoice.expires_at), expiresAt > grantedAt else { continue }
            references.append(ConsoleMonthlyGrantReference(name: name,
                amount: try ConsoleCurrency.majorUnits(cents, currency: "USD"), grantedAt: grantedAt, expiresAt: expiresAt))
        }
        return Self(organizationID: identifier, monthlyReferences: references)
    }

    func matchingMonthlyGrants(_ grants: [ClaudeConsoleGrant]) -> [String: String] {
        var matches: [String: String] = [:]
        for grant in grants {
            let references = monthlyReferences.filter { $0.matches(grant) }
            guard references.count == 1, let reference = references.first,
                  grants.filter({ reference.matches($0) }).count == 1 else { continue }
            matches[grant.id] = reference.name
        }
        return matches
    }
}

private struct ConsoleMonthlyGrantReference: Sendable, Equatable {
    let name: String
    let amount: Decimal
    let grantedAt: Date
    let expiresAt: Date

    func matches(_ grant: ClaudeConsoleGrant) -> Bool {
        grant.currency == "USD" && grant.supportsAPI == true && grant.grantedAmount == amount
            && grant.grantedAt == grantedAt && grant.expiresAt == expiresAt
    }
}

public struct ClaudeConsoleGrant: Sendable, Equatable, Identifiable {
    public let id: String
    public let currency: String
    public let grantedAmount: Decimal
    public let remainingAmount: Decimal
    public let expiresAt: Date?
    public let grantedAt: Date?
    public let supportsAPI: Bool?
    public let scopeDescription: String
}

public struct ClaudeConsoleBalance: Sendable, Equatable {
    public let organizationID: String
    public let observedAt: Date
    /// The raw aggregate is retained separately. It must not be labeled as a monthly allowance.
    public let totalBalance: ClaudeConsoleMoney?
    public let purchasedBalances: [ClaudeConsoleMoney]
    public let promotionalGrants: [ClaudeConsoleGrant]
    public let linkState: ClaudeConsoleLinkState?
    private let monthlyGrantNames: [String: String]

    public var credits: [CreditBalance] {
        let purchased = purchasedBalances.map { balance in
            CreditBalance(id: "api_balance_\(balance.currency)", title: "Purchased API credits (\(balance.currency))",
                          amount: balance.amount, unit: .currency, asOf: observedAt,
                          currencyCode: balance.currency)
        }
        let promotional = promotionalGrants.filter { $0.supportsAPI != false }.map { grant in
            let monthlyName = monthlyGrantNames[grant.id]
            return CreditBalance(id: monthlyName != nil ? "monthly_grant_\(grant.id)" : "console_grant_\(grant.id)",
                          title: monthlyName != nil ? "Monthly included API grant"
                              : grant.supportsAPI == true ? "Promotional API grant" : "Promotional grant (scope unavailable)",
                          amount: grant.remainingAmount, unit: .currency, expiresAt: grant.expiresAt,
                          asOf: observedAt, detail: monthlyName.map { "\($0). Matched to the Console invoice by original amount, grant date, and expiry. \(grant.scopeDescription)" } ?? grant.scopeDescription,
                          currencyCode: grant.currency, originalAmount: grant.grantedAmount)
        }
        let monthlyStatus = monthlyGrantNames.isEmpty ? linkState.map { [$0.monthlyCredit(observedAt: observedAt)] } ?? [] : []
        return purchased + promotional + monthlyStatus
    }

    public static func decode(_ data: Data, organizationID: String, observedAt: Date = Date(),
                              linkState: ClaudeConsoleLinkState? = nil, invoices: ClaudeConsoleInvoices? = nil) throws -> Self {
        let identifier = try ClaudeConsoleClient.validatedOrganizationID(organizationID)
        guard linkState == nil || linkState?.organizationID == identifier else {
            throw UsageError.providerFailure("Claude Console monthly grant linkage belongs to another organization.")
        }
        guard invoices == nil || invoices?.organizationID == identifier else {
            throw UsageError.providerFailure("Claude Console invoices belong to another organization.")
        }
        let response = try ClaudeConsoleClient.decode(ConsoleBalanceResponse.self, from: data)
        guard response.amount != nil || response.tranches != nil || response.promo_tranches != nil else {
            throw UsageError.providerFailure("Claude Console did not return credit balances.")
        }
        let total: ClaudeConsoleMoney?
        if let amount = response.amount, let currency = response.currency {
            total = ClaudeConsoleMoney(currency: try ConsoleCurrency.code(currency),
                                       amount: try ConsoleCurrency.majorUnits(amount, currency: currency))
        } else { total = nil }
        var purchased: [String: Decimal] = [:]
        for tranche in response.tranches ?? [] {
            guard try tranche.isUnexpired(at: observedAt) else { continue }
            if let granted = tranche.granted_amount_minor_units,
               granted < tranche.remaining_amount_minor_units {
                throw UsageError.providerFailure("Claude Console returned an invalid purchased credit balance.")
            }
            let currency = try ConsoleCurrency.code(tranche.currency)
            let remaining = try ConsoleCurrency.majorUnits(tranche.remaining_amount_minor_units, currency: currency)
            purchased[currency, default: 0] += remaining
        }
        // A present empty purchased list establishes a zero purchased balance for the main currency.
        if response.tranches != nil, purchased.isEmpty, let total { purchased[total.currency] = 0 }
        var grants: [ClaudeConsoleGrant] = []
        var identifiers: Set<String> = []
        var providerGrantIdentifiers: Set<String> = []
        for (index, tranche) in (response.promo_tranches ?? []).enumerated() {
            guard try tranche.isUnexpired(at: observedAt) else { continue }
            let currency = try ConsoleCurrency.code(tranche.currency)
            guard let granted = tranche.granted_amount_minor_units, granted > 0,
                  tranche.remaining_amount_minor_units <= granted else {
                throw UsageError.providerFailure("Claude Console returned an invalid promotional grant.")
            }
            let grantID = tranche.id ?? "observation-\(index)"
            guard !grantID.isEmpty, identifiers.insert(grantID).inserted else {
                throw UsageError.providerFailure("Claude Console returned duplicate or missing grant identifiers.")
            }
            if tranche.id != nil { providerGrantIdentifiers.insert(grantID) }
            grants.append(ClaudeConsoleGrant(id: grantID, currency: currency,
                                            grantedAmount: try ConsoleCurrency.majorUnits(granted, currency: currency),
                                            remainingAmount: try ConsoleCurrency.majorUnits(tranche.remaining_amount_minor_units,
                                                                                         currency: currency),
                                            expiresAt: try ConsoleDate.parse(tranche.expires_at),
                                            grantedAt: try ConsoleDate.parse(tranche.granted_at),
                                            supportsAPI: tranche.scope?.supportsAPI,
                                            scopeDescription: tranche.scope?.description ?? "Scope unavailable"))
        }
        return Self(organizationID: identifier, observedAt: observedAt, totalBalance: total,
                    purchasedBalances: purchased.keys.sorted().map { ClaudeConsoleMoney(currency: $0, amount: purchased[$0]!) },
                    promotionalGrants: grants, linkState: linkState,
                    // Array positions cannot identify the same grant across refreshes.
                    monthlyGrantNames: (invoices?.matchingMonthlyGrants(grants) ?? [:])
                        .filter { providerGrantIdentifiers.contains($0.key) })
    }
}

private struct ConsoleBalanceResponse: Decodable {
    let amount: Decimal?
    let currency: String?
    let tranches: [ConsoleTranche]?
    let promo_tranches: [ConsoleTranche]?
}

private struct ConsoleTranche: Decodable {
    let id: String?
    let granted_amount_minor_units: Decimal?
    let remaining_amount_minor_units: Decimal
    let currency: String
    let expires_at: String?
    let granted_at: String?
    let scope: ConsoleScope?

    func isUnexpired(at date: Date) throws -> Bool {
        try ConsoleDate.parse(expires_at).map { $0 > date } ?? true
    }
}

private struct ConsoleScope: Decodable {
    struct Application: Decodable {
        let product: String?
        let model_family: String?
        let model_version: String?
    }
    let kind: String?
    let applies_to: [Application]?

    var supportsAPI: Bool? {
        if kind == "unscoped" { return true }
        guard kind == "scoped", let applications = applies_to, !applications.isEmpty else { return nil }
        guard applications.allSatisfy({ $0.product != nil }) else { return nil }
        return applications.contains { $0.product == "api" }
    }

    var description: String {
        if kind == "unscoped" { return "All models and products" }
        guard kind == "scoped", let applications = applies_to, !applications.isEmpty else { return "Scope unavailable" }
        let values = applications.map { application in
            [application.product, application.model_family, application.model_version].compactMap { $0 }.joined(separator: " ")
        }.filter { !$0.isEmpty }
        return values.isEmpty ? "Scope unavailable" : "Scope: " + values.joined(separator: ", ")
    }
}

private enum ConsoleDate {
    static func parse(_ value: String?) throws -> Date? {
        guard let value else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw UsageError.providerFailure("Claude Console returned an invalid credit date.")
        }
        return date
    }
}

private enum ConsoleCurrency {
    static func code(_ value: String) throws -> String {
        let code = value.uppercased()
        guard Locale.commonISOCurrencyCodes.contains(code), !["XAU", "XAG", "XPD", "XPT", "XXX", "XTS"].contains(code) else {
            throw UsageError.providerFailure("Claude Console returned an unsupported credit currency.")
        }
        return code
    }

    static func majorUnits(_ value: Decimal, currency: String) throws -> Decimal {
        let currency = try code(currency)
        var valueCopy = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &valueCopy, 0, .plain)
        guard !value.isNaN, value >= 0, rounded == value else {
            throw UsageError.providerFailure("Claude Console returned an invalid credit amount.")
        }
        let zero = ["BIF", "CLP", "DJF", "GNF", "ISK", "JPY", "KMF", "KRW", "PYG", "RWF", "UGX", "UYI", "VND", "VUV", "XAF", "XOF", "XPF"]
        let three = ["BHD", "IQD", "JOD", "KWD", "LYD", "OMR", "TND"]
        let exponent = zero.contains(currency) ? 0 : three.contains(currency) ? 3 : ["CLF", "UYW"].contains(currency) ? 4 : 2
        var divisor: Decimal = 1
        for _ in 0..<exponent { divisor *= 10 }
        return value / divisor
    }
}
