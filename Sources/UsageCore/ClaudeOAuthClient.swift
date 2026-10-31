import Foundation
import CryptoKit
import Security
import LocalAuthentication

public struct ClaudeAuthorizationRequest: Sendable {
    public let id: UUID
    public let authorizationURL: URL
    public let redirectURL: URL
    public let expiresAt: Date
}

struct ClaudeAuthorization: Sendable {
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let redirectURL = URL(string: "http://localhost:54545/callback")!
    let request: ClaudeAuthorizationRequest
    let state: String
    let verifier: String

    init(now: Date = Date()) throws {
        state = try Self.randomString()
        verifier = try Self.randomString()
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLString
        var components = URLComponents(string: "https://claude.ai/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: Self.clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURL.absoluteString),
            URLQueryItem(name: "scope", value: "user:profile"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        request = ClaudeAuthorizationRequest(id: UUID(), authorizationURL: components.url!,
                                            redirectURL: Self.redirectURL, expiresAt: now.addingTimeInterval(300))
    }

    func code(from callback: URL, now: Date = Date()) throws -> String {
        guard now < request.expiresAt,
              let components = URLComponents(url: callback, resolvingAgainstBaseURL: false),
              components.scheme == "http", components.host == "localhost", components.port == 54545,
              components.path == "/callback", components.user == nil, components.password == nil,
              components.fragment == nil else {
            throw UsageError.authenticationRequired("Claude sign-in expired or returned an unexpected callback. Try again.")
        }
        let items = components.queryItems ?? []
        guard items.filter({ $0.name == "code" }).count == 1,
              items.filter({ $0.name == "state" }).count <= 1,
              !items.contains(where: { $0.name == "error" }),
              let returnedCode = items.first(where: { $0.name == "code" })?.value, !returnedCode.isEmpty else {
            throw UsageError.authenticationRequired("Claude sign-in was not completed. Try again.")
        }
        let parts = returnedCode.split(separator: "#", omittingEmptySubsequences: false)
        let returnedState = items.first(where: { $0.name == "state" })?.value ?? (parts.count == 2 ? String(parts[1]) : nil)
        guard returnedState == state, parts.count <= 2, !parts[0].isEmpty,
              parts.count != 2 || parts[1] == state else {
            throw UsageError.authenticationRequired("Claude sign-in did not match this connection. Try again.")
        }
        return String(parts[0])
    }

    private static func randomString() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw UsageError.providerFailure("Could not prepare secure Claude sign-in. Try again.")
        }
        return Data(bytes).base64URLString
    }
}

private extension Data {
    var base64URLString: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

struct ClaudeCredentials: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date
    let identity: String
    var refreshPending = false
}

protocol ClaudeCredentialStore: Sendable {
    func read(accountID: UUID, allowInteraction: Bool) throws -> ClaudeCredentials?
    func save(_ credentials: ClaudeCredentials, accountID: UUID, allowInteraction: Bool) throws
    func remove(accountID: UUID, allowInteraction: Bool) throws
}

enum ClaudeKeychainAccess {
    private static let lock = NSLock()

    static func withPromptsSuppressed<Value>(unless allowInteraction: Bool, _ operation: () throws -> Value) throws -> Value {
        try lock.withLock {
            guard !allowInteraction else { return try operation() }
            var previous = DarwinBoolean(false)
            guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
                  SecKeychainSetUserInteractionAllowed(false) == errSecSuccess else {
                throw UsageError.authenticationRequired("Claude Keychain access could not run without a prompt. Your saved sign-in is preserved.")
            }
            let result = Result(catching: operation)
            guard SecKeychainSetUserInteractionAllowed(previous.boolValue) == errSecSuccess else {
                throw UsageError.authenticationRequired("Claude Keychain access could not restore its interaction setting. Quit and reopen the app.")
            }
            return try result.get()
        }
    }
}

struct ClaudeKeychainStore: ClaudeCredentialStore {
    // Keeps the service name from the app's first name, AI Usage Stats, so saved sign-ins stay readable.
    private let service = "AI Usage Stats Claude OAuth"

    private func query(accountID: UUID, allowInteraction: Bool) -> [String: Any] {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: accountID.uuidString]
        if !allowInteraction {
            let context = LAContext()
            context.interactionNotAllowed = true
            query[kSecUseAuthenticationContext as String] = context
            query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
        }
        return query
    }

    func read(accountID: UUID, allowInteraction: Bool) throws -> ClaudeCredentials? {
        var query = query(accountID: accountID, allowInteraction: allowInteraction)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = try ClaudeKeychainAccess.withPromptsSuppressed(unless: allowInteraction) {
            SecItemCopyMatching(query as CFDictionary, &result)
        }
        return try Self.credentials(status: status, result: result)
    }

    static func credentials(status: OSStatus, result: CFTypeRef?) throws -> ClaudeCredentials? {
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw UsageError.authenticationRequired(status == errSecInteractionNotAllowed || status == errSecAuthFailed
                ? UsageError.keychainPermissionRequiredMessage
                : "Claude credentials are unavailable in Keychain. Reconnect this account.")
        }
        do { return try JSONDecoder().decode(ClaudeCredentials.self, from: data) }
        catch { throw UsageError.authenticationRequired("Saved Claude credentials are incomplete. Reconnect this account.") }
    }

    func save(_ credentials: ClaudeCredentials, accountID: UUID, allowInteraction: Bool) throws {
        let data = try JSONEncoder().encode(credentials)
        let query = query(accountID: accountID, allowInteraction: allowInteraction)
        let changes = [kSecValueData as String: data]
        let status = try ClaudeKeychainAccess.withPromptsSuppressed(unless: allowInteraction) {
            let status = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
            guard status == errSecItemNotFound else { return status }
            var entry = query
            entry[kSecValueData as String] = data
            entry[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            return SecItemAdd(entry as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw UsageError.authenticationRequired("Could not save Claude credentials in Keychain. Reconnect this account.")
        }
    }

    func remove(accountID: UUID, allowInteraction: Bool) throws {
        let status = try ClaudeKeychainAccess.withPromptsSuppressed(unless: allowInteraction) {
            SecItemDelete(query(accountID: accountID, allowInteraction: allowInteraction) as CFDictionary)
        }
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw UsageError.providerFailure("Could not remove this account's Claude credentials from Keychain.")
        }
    }
}

struct ClaudeHTTPResponse: Sendable {
    let status: Int
    let contentType: String?
    let body: Data
}

protocol ClaudeHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> ClaudeHTTPResponse
}

private final class ClaudeRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

struct ClaudeURLSessionTransport: ClaudeHTTPTransport {
    func send(_ request: URLRequest) async throws -> ClaudeHTTPResponse {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: ClaudeRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let response = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            var body = Data()
            for try await byte in bytes {
                guard body.count < 1_048_576 else { throw URLError(.dataLengthExceedsMaximum) }
                body.append(byte)
            }
            return ClaudeHTTPResponse(status: response.statusCode, contentType: response.value(forHTTPHeaderField: "Content-Type"), body: body)
        } catch is CancellationError { throw CancellationError() }
        catch { throw UsageError.providerFailure("Claude could not be reached. Check your connection, then try again.") }
    }
}

struct ClaudeProviderProfile: Decodable, Sendable {
    struct Account: Decodable, Sendable {
        let uuid: UUID
        let email: String?
        let hasClaudeMax: Bool?
        let hasClaudePro: Bool?
        private enum CodingKeys: String, CodingKey { case uuid, email, email_address, has_claude_max, has_claude_pro }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            uuid = try values.decode(UUID.self, forKey: .uuid)
            email = try values.decodeIfPresent(String.self, forKey: .email)
                ?? values.decodeIfPresent(String.self, forKey: .email_address)
            // A non-boolean flag must not reject the profile. The plan stays unknown.
            hasClaudeMax = Self.optionalBoolean(values, .has_claude_max)
            hasClaudePro = Self.optionalBoolean(values, .has_claude_pro)
        }

        private static func optionalBoolean(_ values: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Bool? {
            guard values.contains(key) else { return nil }
            return try? values.decodeIfPresent(Bool.self, forKey: key)
        }
    }
    struct Organization: Decodable, Sendable {
        let uuid: UUID
        let organizationType: String?
        let subscriptionStatus: String?
        private enum CodingKeys: String, CodingKey { case uuid, organization_type, subscription_status }
        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            uuid = try values.decode(UUID.self, forKey: .uuid)
            organizationType = Self.optionalText(values, .organization_type)
            subscriptionStatus = Self.optionalText(values, .subscription_status)
        }

        private static func optionalText(_ values: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> String? {
            guard values.contains(key) else { return nil }
            guard let value = try? values.decodeIfPresent(String.self, forKey: key) else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
    let account: Account
    let organization: Organization?

    /// Team, Max, Pro, or Free from the profile flags already returned by the profile read. Missing or conflicting flags stay unknown.
    var planName: String? {
        if organization?.organizationType?.lowercased() == "claude_team",
           organization?.subscriptionStatus?.lowercased() == "active" {
            return "Team"
        }
        if account.hasClaudeMax == true { return "Max" }
        if account.hasClaudePro == true { return "Pro" }
        if account.hasClaudeMax == false, account.hasClaudePro == false { return "Free" }
        return nil
    }

    func resolvedIdentity(expected: String? = nil, tokenAccount: UUID? = nil, tokenOrganization: UUID? = nil) throws -> String {
        guard tokenAccount == nil || tokenAccount == account.uuid,
              organization == nil || tokenOrganization == nil || organization?.uuid == tokenOrganization else {
            throw UsageError.authenticationRequired("Claude returned conflicting account or organization details. Sign in with the intended account.")
        }
        let reportedOrganization = organization?.uuid ?? tokenOrganization
        if let expected {
            let parts = expected.split(separator: "/", omittingEmptySubsequences: false)
            guard (1...2).contains(parts.count), UUID(uuidString: String(parts[0])) == account.uuid,
                  parts.count == 1 || UUID(uuidString: String(parts[1])) != nil else {
                throw UsageError.authenticationRequired("This sign-in belongs to a different Claude account. Add it as a separate account.")
            }
            if parts.count == 2, let reportedOrganization,
               UUID(uuidString: String(parts[1])) != reportedOrganization {
                throw UsageError.authenticationRequired("This sign-in belongs to a different Claude organization. Add it as a separate account.")
            }
            // An omitted organization cannot erase a known binding; account-only bindings remain valid.
            return expected
        }
        return account.uuid.uuidString + (reportedOrganization.map { "/" + $0.uuidString } ?? "")
    }
}

struct ClaudeTokenResponse: Decodable, Sendable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Double
    let scope: String?
    let token_type: String?
    let account: ClaudeProviderProfile.Account?
    let organization: ClaudeProviderProfile.Organization?

    func credentials(identity: String, previousRefreshToken: String? = nil, now: Date = Date()) throws -> ClaudeCredentials {
        guard !access_token.isEmpty, expires_in.isFinite, expires_in > 0,
              token_type == nil || token_type?.lowercased() == "bearer",
              scope == nil || Set(scope!.split(separator: " ")) == ["user:profile"] else {
            throw UsageError.authenticationRequired("Claude did not accept the requested read-only access. This experimental connection is unavailable.")
        }
        return ClaudeCredentials(accessToken: access_token, refreshToken: refresh_token ?? previousRefreshToken,
                                 expiresAt: now.addingTimeInterval(expires_in), identity: identity)
    }
}

struct ClaudeUsageResponse: Decodable, Sendable {
    struct Window: Decodable, Sendable {
        let utilization: Double?
        let resets_at: String?
        enum CodingKeys: String, CodingKey { case utilization, resets_at }
    }
    struct Limit: Decodable, Sendable {
        struct Scope: Decodable, Sendable {
            struct Model: Decodable, Sendable { let id: String?; let display_name: String? }
            let model: Model?
        }
        let kind: String?
        let group: String?
        let percent: Double?
        let resets_at: String?
        let is_active: Bool?
        let scope: Scope?
    }
    let windows: [(String, Window)]
    let limits: [Limit]

    init(from decoder: Decoder) throws {
        struct Key: CodingKey {
            let stringValue: String
            let intValue: Int? = nil
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        let values = try decoder.container(keyedBy: Key.self)
        windows = try values.allKeys.filter { $0.stringValue == "five_hour" || $0.stringValue == "seven_day" || $0.stringValue.hasPrefix("seven_day_") }
            .sorted { $0.stringValue < $1.stringValue }
            .compactMap { key in
                if key.stringValue != "five_hour", key.stringValue != "seven_day" {
                    // Named quota windows have quota fields, unlike seven_day_breakdown metadata.
                    guard let fields = try? values.superDecoder(forKey: key).container(keyedBy: Window.CodingKeys.self),
                          fields.contains(.utilization) || fields.contains(.resets_at) else { return nil }
                }
                return try values.decodeIfPresent(Window.self, forKey: key).map { (key.stringValue, $0) }
            }
        limits = try values.decodeIfPresent([Limit].self, forKey: Key(stringValue: "limits")) ?? []
    }

    func snapshot(profileID: UUID, observedAt: Date = Date(), planName: String? = nil) throws -> AccountSnapshot {
        func reset(_ text: String?) throws -> Date? {
            guard let text else { return nil }
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: text) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: text) else { throw UsageError.providerFailure("Claude returned an invalid quota reset time.") }
            return date
        }
        func percent(_ value: Double?) throws -> Double? {
            guard let value else { return nil }
            guard value.isFinite, (0...100).contains(value) else { throw UsageError.providerFailure("Claude returned an invalid quota percentage.") }
            return value
        }
        var result = try windows.map { id, window in
            let title = id == "five_hour" ? "5 hours" : id == "seven_day" ? "7 days" : "7 days (" + id.dropFirst("seven_day_".count).replacingOccurrences(of: "_", with: " ") + ")"
            return UsageWindow(id: id, title: title, utilizationPercent: try percent(window.utilization), resetsAt: try reset(window.resets_at))
        }
        for (index, limit) in limits.enumerated() {
            guard let kind = limit.kind?.trimmingCharacters(in: .whitespacesAndNewlines), !kind.isEmpty else { continue }
            let model = limit.scope?.model?.display_name ?? limit.scope?.model?.id
            let canonicalID: String?
            if model == nil, ["five_hour", "session"].contains(kind) { canonicalID = "five_hour" }
            else if model == nil, ["seven_day", "weekly", "weekly_all"].contains(kind) { canonicalID = "seven_day" }
            else { canonicalID = nil }
            if let canonicalID, let index = result.firstIndex(where: { $0.id == canonicalID }) {
                if let isActive = limit.is_active {
                    let canonical = result[index]
                    result[index] = UsageWindow(id: canonical.id, title: canonical.title,
                                                utilizationPercent: canonical.utilizationPercent, resetsAt: canonical.resetsAt,
                                                isActive: canonical.isActive == false ? false : isActive)
                }
                continue
            }
            let windowTitle: String
            switch kind {
            case "five_hour", "session": windowTitle = "5 hours"
            case "seven_day", "weekly", "weekly_all", "weekly_scoped": windowTitle = "7 days"
            default: windowTitle = kind.replacingOccurrences(of: "_", with: " ")
            }
            let title = model.map { windowTitle + " (" + $0 + ")" } ?? windowTitle
            result.append(UsageWindow(id: canonicalID ?? "limit_\(index)_\(kind)", title: title,
                                      utilizationPercent: try percent(limit.percent), resetsAt: try reset(limit.resets_at), isActive: limit.is_active))
        }
        let current = result.filter { $0.isActive != false }
        let measured = current.contains { $0.utilizationPercent != nil }
        let stale = current.contains { $0.resetsAt.map { $0 <= observedAt } == true }
        return AccountSnapshot(profileID: profileID, fetchedAt: measured ? observedAt : nil, windows: result,
                               state: measured ? (stale ? .stale : .available) : .unavailable,
                               detail: measured ? (stale ? "A reported quota reset has passed. Refresh to read current usage." : "Read from this Claude account.")
                               : "Claude returned no measured subscription quota. Your account may not expose these limits.",
                               planName: planName)
    }
}

struct ClaudeOAuthClient: Sendable {
    let transport: any ClaudeHTTPTransport
    init(transport: any ClaudeHTTPTransport = ClaudeURLSessionTransport()) { self.transport = transport }

    func exchange(_ authorization: ClaudeAuthorization, code: String) async throws -> ClaudeTokenResponse {
        try await token(body: ["grant_type": "authorization_code", "code": code,
                               "redirect_uri": ClaudeAuthorization.redirectURL.absoluteString,
                               "client_id": ClaudeAuthorization.clientID, "code_verifier": authorization.verifier,
                               "state": authorization.state])
    }

    func refresh(_ refreshToken: String) async throws -> ClaudeTokenResponse {
        try await token(body: ["grant_type": "refresh_token", "refresh_token": refreshToken,
                               "client_id": ClaudeAuthorization.clientID])
    }

    private func token(body: [String: String]) async throws -> ClaudeTokenResponse {
        var request = URLRequest(url: URL(string: "https://platform.claude.com/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await decode(request, as: ClaudeTokenResponse.self, authorizationExchange: body["grant_type"] == "authorization_code")
    }

    func profile(accessToken: String) async throws -> ClaudeProviderProfile {
        try await decode(authorizedRequest(path: "profile", accessToken: accessToken), as: ClaudeProviderProfile.self)
    }

    func usage(accessToken: String) async throws -> ClaudeUsageResponse {
        try await decode(authorizedRequest(path: "usage", accessToken: accessToken), as: ClaudeUsageResponse.self)
    }

    private func authorizedRequest(path: String, accessToken: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/\(path)")!)
        request.setValue("Bearer " + accessToken, forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.0", forHTTPHeaderField: "User-Agent")
        return request
    }

    private func decode<Value: Decodable>(_ request: URLRequest, as type: Value.Type, authorizationExchange: Bool = false) async throws -> Value {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let response = try await transport.send(request)
        if authorizationExchange, [400, 401, 403].contains(response.status) {
            throw UsageError.authenticationRequired("Claude did not accept this read-only authorization. This experimental connection may be unavailable.")
        }
        if [401, 403].contains(response.status) { throw UsageError.authenticationRequired("Claude access was refused. Reconnect this account.") }
        if response.status == 429 { throw UsageError.providerFailure("Claude is limiting usage checks. Wait before checking again.") }
        guard (200...299).contains(response.status) else {
            throw UsageError.providerFailure("Claude could not complete the account request (HTTP \(response.status)).")
        }
        guard response.contentType?.lowercased().contains("application/json") == true else {
            throw UsageError.providerFailure("Claude returned an unexpected account response. Try again.")
        }
        do { return try JSONDecoder().decode(type, from: response.body) }
        catch { throw UsageError.providerFailure("Claude returned incomplete or invalid account data.") }
    }
}

extension UsageError {
    public static let keychainPermissionRequiredMessage =
        "Claude Keychain access needs permission. Your saved sign-in is preserved; allow Keychain access for this account."
}

extension AccountSnapshot {
    public var needsKeychainPermission: Bool {
        state == .authenticationRequired && detail?.contains(UsageError.keychainPermissionRequiredMessage) == true
    }
}
