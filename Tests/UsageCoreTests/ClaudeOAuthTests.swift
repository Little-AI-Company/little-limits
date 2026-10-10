import Foundation
import CryptoKit
import Testing
@testable import UsageCore

@Test func claudeAuthorizationUsesReadOnlyPKCEAndRejectsUnrelatedCallbacks() throws {
    let authorization = try ClaudeAuthorization()
    let parameters = Dictionary(uniqueKeysWithValues: URLComponents(url: authorization.request.authorizationURL,
                                                                    resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
    #expect(parameters["scope"] == "user:profile")
    #expect(parameters["code_challenge_method"] == "S256")
    let challenge = Data(SHA256.hash(data: Data(authorization.verifier.utf8))).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    #expect(parameters["code_challenge"] == challenge)
    #expect(try authorization.code(from: callback(authorization.request)) == "example-code")
    #expect(throws: UsageError.self) { try authorization.code(from: callback(authorization.request, state: "different")) }
    #expect(throws: UsageError.self) { try authorization.code(from: URL(string: "https://example.com/callback?code=test&state=test")!) }
    #expect(throws: UsageError.self) { try authorization.code(from: callback(authorization.request), now: authorization.request.expiresAt) }
    let omittedScope = try JSONDecoder().decode(ClaudeTokenResponse.self, from: tokenResponse.body)
    #expect(try omittedScope.credentials(identity: "account").accessToken == "example-access")
    let widened = try JSONDecoder().decode(ClaudeTokenResponse.self, from: Data(#"{"access_token":"example","expires_in":3600,"scope":"user:profile user:inference"}"#.utf8))
    #expect(throws: UsageError.self) { try widened.credentials(identity: "account") }
}

@Test func claudeQuotaKeepsUnknownZeroAndInactiveWindowsSeparate() throws {
    let response = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(#"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":null},"seven_day_sonnet":{"utilization":23,"resets_at":"2099-01-01T12:00:00.123Z"},"limits":[{"kind":"weekly_scoped","percent":0,"is_active":false,"scope":{"model":{"display_name":"Example"}}}]}"#.utf8))
    let snapshot = try response.snapshot(profileID: UUID())
    #expect(snapshot.state == .available)
    #expect(snapshot.windows.first { $0.id == "five_hour" }?.utilizationPercent == 0)
    #expect(snapshot.windows.first { $0.id == "seven_day" }?.utilizationPercent == nil)
    #expect(snapshot.windows.last?.isActive == false)
    #expect(snapshot.windows.last?.title == "7 days (Example)")
    #expect(snapshot.credits.isEmpty)
    let missing = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(#"{"five_hour":{"utilization":null}}"#.utf8)).snapshot(profileID: UUID())
    #expect(missing.state == .unavailable)
    #expect(missing.fetchedAt == nil)
    let invalid = try JSONDecoder().decode(ClaudeUsageResponse.self, from: Data(#"{"five_hour":{"utilization":101}}"#.utf8))
    #expect(throws: UsageError.self) { try invalid.snapshot(profileID: UUID()) }
}

@Test func claudeOverlappingQuotaShapesOmitMetadataAndUsePrimaryLimitsOnlyAsFallback() throws {
    let overlapping = Data(#"{"five_hour":{"utilization":0,"resets_at":null},"seven_day":{"utilization":null},"seven_day_breakdown":{"models":{"example":12}},"limits":[{"kind":"session","group":"session","percent":0},{"kind":"weekly_all","group":"weekly","percent":37},{"kind":"weekly_scoped","percent":12,"scope":{"model":{"display_name":"Example"}}}]}"#.utf8)
    let snapshot = try JSONDecoder().decode(ClaudeUsageResponse.self, from: overlapping).snapshot(profileID: UUID())
    #expect(snapshot.windows.map(\.title) == ["5 hours", "7 days", "7 days (Example)"])
    #expect(snapshot.windows.map(\.utilizationPercent) == [0, nil, 12])
    let fallback = Data(#"{"limits":[{"kind":"session","group":"session","percent":0},{"kind":"weekly_all","group":"weekly","percent":37},{"kind":"weekly_scoped","percent":12,"scope":{"model":{"display_name":"Example"}}}]}"#.utf8)
    let fallbackSnapshot = try JSONDecoder().decode(ClaudeUsageResponse.self, from: fallback).snapshot(profileID: UUID())
    #expect(fallbackSnapshot.windows.map(\.title) == ["5 hours", "7 days", "7 days (Example)"])
    #expect(fallbackSnapshot.windows.map(\.utilizationPercent) == [0, 37, 12])
}

@Test func inactiveClaudeLimitsPreserveProviderDataWithoutChangingCurrentQuotaOrStaleness() throws {
    let data = Data(#"{"five_hour":{"utilization":20,"resets_at":"2099-01-01T12:00:00Z"},"seven_day":{"utilization":100,"resets_at":"2000-01-01T12:00:00Z"},"limits":[{"kind":"session","percent":20,"is_active":true},{"kind":"weekly_all","percent":100,"is_active":false},{"kind":"weekly_scoped","percent":100,"is_active":false,"resets_at":"2000-01-01T12:00:00Z","scope":{"model":{"display_name":"Example"}}}]}"#.utf8)
    let snapshot = try JSONDecoder().decode(ClaudeUsageResponse.self, from: data).snapshot(profileID: UUID())
    #expect(snapshot.state == .available)
    #expect(snapshot.windows.count == 3)
    #expect(snapshot.windows.first { $0.id == "seven_day" }?.isActive == false)
    #expect(snapshot.windows.first { $0.id == "seven_day" }?.utilizationPercent == 100)
    #expect(snapshot.currentWindows.map(\.utilizationPercent) == [20])
    let inactiveOnly = Data(#"{"five_hour":{"utilization":null},"limits":[{"kind":"session","percent":100,"is_active":false,"resets_at":"2000-01-01T12:00:00Z"}]}"#.utf8)
    let unmeasured = try JSONDecoder().decode(ClaudeUsageResponse.self, from: inactiveOnly).snapshot(profileID: UUID())
    #expect(unmeasured.state == .unavailable)
    #expect(unmeasured.fetchedAt == nil)
    #expect(unmeasured.currentWindows.isEmpty)
    #expect(unmeasured.windows.first?.utilizationPercent == nil)
}

@Test func claudeMigrationRetiresOnlyItsOwnedCaptureAndPreservesEditsAndCleanupRecovery() async throws {
    struct Settings: Codable, Equatable {
        struct StatusLine: Codable, Equatable { let type: String; var command: String; var padding: Int? }
        var statusLine: StatusLine
        let theme: String
    }
    for variant in ["original", "replaced", "padding", "invalid"] {
        let fixture = try OAuthFixture(steps: [.response(tokenResponse), .response(profileResponse), .response(profileResponse), .response(usageResponse)])
        defer { fixture.removeDirectory() }
        let helper = fixture.directory.appendingPathComponent("UsageCapture")
        try UsagePaths.writePrivate(Data("#!/bin/sh\nexit 0\n".utf8), to: helper, permissions: 0o700)
        let source = fixture.directory.appendingPathComponent("Claude")
        let settingsURL = source.appendingPathComponent("settings.json")
        let original = Settings(statusLine: .init(type: "command", command: "printf original", padding: 2), theme: "dark")
        try UsagePaths.writePrivate(JSONEncoder().encode(original), to: settingsURL)
        let legacy = try await fixture.service.importClaudeCLI(label: "Personal", configurationURL: source)
        let before = try ConfigurationStorage(directory: fixture.directory).load()
        let installation = try #require(before.captureInstallations[legacy.id.uuidString])
        let installed = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL))
        var edited = installed
        if variant == "replaced" { edited.statusLine.command = "printf changed" }
        if variant == "padding" { edited.statusLine.padding = 9 }
        try UsagePaths.writePrivate(variant == "invalid" ? Data("{".utf8) : JSONEncoder().encode(edited), to: settingsURL)
        let request = try await fixture.service.prepareClaudeSignIn(existingProfileID: legacy.id)
        let profile = try await fixture.service.completeClaudeSignIn(requestID: request.id, callbackURL: callback(request))
        #expect(profile.id == legacy.id)
        #expect(profile.label == legacy.label)
        #expect(profile.source == .claudeOAuth)
        #expect(fixture.credentials.count == 1)
        #expect(await fixture.service.snapshot(for: profile.id)?.state == .available)
        #expect(FileManager.default.isExecutableFile(atPath: helper.path))
        let after = try ConfigurationStorage(directory: fixture.directory).load()
        #expect((after.captureInstallations[profile.id.uuidString] != nil) == ["padding", "invalid"].contains(variant))
        if variant != "invalid" {
            let restored = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL))
            #expect(restored == (variant == "original" ? original : edited))
        }
        if ["padding", "invalid"].contains(variant) {
            #expect(await fixture.service.snapshot(for: profile.id)?.detail?.contains("old Claude Code connection") == true)
            // Repairing the saved wrapper allows idempotent maintenance to finish, without a new login.
            let statusLine = try JSONDecoder().decode(Settings.StatusLine.self, from: installation.installedStatusLine)
            try UsagePaths.writePrivate(JSONEncoder().encode(Settings(statusLine: statusLine, theme: "dark")), to: settingsURL)
            _ = try await fixture.service.load()
            #expect(try ConfigurationStorage(directory: fixture.directory).load().captureInstallations[profile.id.uuidString] == nil)
            #expect(try JSONDecoder().decode(Settings.self, from: Data(contentsOf: settingsURL)) == original)
            #expect(fixture.credentials.count == 1)
        }
    }
}

@Test func claudeConnectionBindsIdentityReadsImmediatelyAndRejectsDuplicateOrChangedAccount() async throws {
    let fixture = try OAuthFixture(steps: [.response(tokenResponse), .response(profileResponse), .response(profileResponse), .response(usageResponse),
                                         .response(tokenResponse), .response(profileResponse), .response(tokenResponse), .response(otherProfileResponse)])
    defer { fixture.removeDirectory() }
    let request = try await fixture.service.prepareClaudeSignIn(label: "Personal")
    let profile = try await fixture.service.completeClaudeSignIn(requestID: request.id, callbackURL: callback(request))
    #expect(profile.source == .claudeOAuth)
    #expect(profile.providerEmail == "example@example.com")
    #expect(profile.label == "Personal")
    #expect(await fixture.service.snapshot(for: profile.id)?.windows.first?.utilizationPercent == 42)
    let stored = try String(contentsOf: fixture.directory.appendingPathComponent("accounts.json"), encoding: .utf8)
    #expect(!stored.contains("example-access"))
    #expect(!stored.contains("example-refresh"))
    let duplicate = try await fixture.service.prepareClaudeSignIn()
    await #expect(throws: UsageError.self) {
        try await fixture.service.completeClaudeSignIn(requestID: duplicate.id, callbackURL: callback(duplicate))
    }
    let replacement = try await fixture.service.prepareClaudeSignIn(existingProfileID: profile.id)
    await #expect(throws: UsageError.self) {
        try await fixture.service.completeClaudeSignIn(requestID: replacement.id, callbackURL: callback(replacement))
    }
    #expect(try await fixture.service.load() == [profile])
    #expect(try fixture.credentials.read(accountID: profile.id, allowInteraction: false)?.identity == profile.providerAccountID)
    let requests = await fixture.transport.requests
    #expect(requests.filter { $0.httpMethod == "GET" }.allSatisfy { $0.value(forHTTPHeaderField: "User-Agent") == "claude-code/2.1.0" })
    #expect(requests.allSatisfy { ["platform.claude.com", "api.anthropic.com"].contains($0.url?.host) })
}

@Test func cancelledClaudeAuthorizationCannotSaveAProfileOrCredential() async throws {
    let fixture = try OAuthFixture(steps: [.suspended(tokenResponse)])
    defer { fixture.removeDirectory() }
    let request = try await fixture.service.prepareClaudeSignIn()
    let completion = Task { try await fixture.service.completeClaudeSignIn(requestID: request.id, callbackURL: callback(request)) }
    await fixture.transport.waitUntilPaused()
    await fixture.service.cancelClaudeSignIn(id: request.id)
    await fixture.transport.release()
    await #expect(throws: UsageError.self) { try await completion.value }
    #expect(try await fixture.service.load().isEmpty)
    #expect(fixture.credentials.count == 0)
}

@Test func uncertainClaudeTokenRotationRequiresReconnectWithoutRetryAndKeepsLastReading() async throws {
    let fixture = try OAuthFixture(steps: [.response(tokenResponse), .response(profileResponse), .response(profileResponse), .response(usageResponse), .failure])
    defer { fixture.removeDirectory() }
    let profile = try await fixture.connect()
    let savedCredentials = try fixture.credentials.read(accountID: profile.id, allowInteraction: false)
    let previous = try #require(savedCredentials)
    try fixture.credentials.save(ClaudeCredentials(accessToken: previous.accessToken, refreshToken: previous.refreshToken,
                                                   expiresAt: .distantPast, identity: previous.identity), accountID: profile.id, allowInteraction: false)
    let failed = await fixture.service.refreshAccount(id: profile.id)
    #expect(failed.state == .authenticationRequired)
    #expect(failed.windows.first?.utilizationPercent == 42)
    #expect(try fixture.credentials.read(accountID: profile.id, allowInteraction: false)?.refreshPending == true)
    let requestCount = await fixture.transport.requests.count
    let repeated = await fixture.service.refreshAccount(id: profile.id)
    #expect(repeated.state == .authenticationRequired)
    #expect(await fixture.transport.requests.count == requestCount)
}

@Test func removingClaudeAccountDuringUsageCheckCannotRestoreItsReading() async throws {
    let fixture = try OAuthFixture(steps: [.response(tokenResponse), .response(profileResponse), .response(profileResponse), .response(usageResponse),
                                         .response(profileResponse), .suspended(usageResponse)])
    defer { fixture.removeDirectory() }
    let profile = try await fixture.connect()
    let refresh = Task { await fixture.service.refreshAccount(id: profile.id) }
    await fixture.transport.waitUntilPaused()
    try await fixture.service.removeAccount(id: profile.id)
    await fixture.transport.release()
    _ = await refresh.value
    #expect(try await fixture.service.load().isEmpty)
    #expect(await fixture.service.snapshot(for: profile.id) == nil)
    #expect(fixture.credentials.count == 0)
}

@Test func claudeHTTPFailuresDoNotBecomeMeasuredZero() async throws {
    for response in [ClaudeHTTPResponse(status: 200, contentType: "text/html", body: Data("<html>Sign in</html>".utf8)),
                     ClaudeHTTPResponse(status: 401, contentType: "application/json", body: Data("{}".utf8)),
                     ClaudeHTTPResponse(status: 429, contentType: "application/json", body: Data("{}".utf8)),
                     ClaudeHTTPResponse(status: 302, contentType: "text/html", body: Data())] {
        let transport = OAuthTransport(steps: [.response(response)])
        await #expect(throws: UsageError.self) { try await ClaudeOAuthClient(transport: transport).usage(accessToken: "example") }
    }
}

private let tokenResponse = ClaudeHTTPResponse(status: 200, contentType: "application/json",
    body: Data(#"{"access_token":"example-access","refresh_token":"example-refresh","expires_in":3600}"#.utf8))
private let profileResponse = ClaudeHTTPResponse(status: 200, contentType: "application/json",
    body: Data(#"{"account":{"uuid":"AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA","email":"example@example.com"},"organization":{"uuid":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"}}"#.utf8))
private let otherProfileResponse = ClaudeHTTPResponse(status: 200, contentType: "application/json",
    body: Data(#"{"account":{"uuid":"CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC"},"organization":{"uuid":"BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"}}"#.utf8))
private let usageResponse = ClaudeHTTPResponse(status: 200, contentType: "application/json",
    body: Data(#"{"five_hour":{"utilization":42,"resets_at":"2099-01-01T12:00:00Z"}}"#.utf8))

private func callback(_ request: ClaudeAuthorizationRequest, state: String? = nil) -> URL {
    let expected = URLComponents(url: request.authorizationURL, resolvingAgainstBaseURL: false)!.queryItems!.first { $0.name == "state" }!.value!
    var components = URLComponents(url: request.redirectURL, resolvingAgainstBaseURL: false)!
    components.queryItems = [URLQueryItem(name: "code", value: "example-code"), URLQueryItem(name: "state", value: state ?? expected)]
    return components.url!
}

private struct OAuthFixture {
    let directory: URL
    let credentials = MemoryClaudeCredentials()
    let transport: OAuthTransport
    let service: UsageService

    init(steps: [OAuthTransport.Step]) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("AIUsageOAuthTests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        transport = OAuthTransport(steps: steps)
        service = UsageService(directory: directory, claudeClient: ClaudeOAuthClient(transport: transport), claudeCredentials: credentials)
    }
    func connect() async throws -> AccountProfile {
        let request = try await service.prepareClaudeSignIn()
        return try await service.completeClaudeSignIn(requestID: request.id, callbackURL: callback(request))
    }
    func removeDirectory() { try? FileManager.default.removeItem(at: directory) }
}

private final class MemoryClaudeCredentials: ClaudeCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [UUID: ClaudeCredentials] = [:]
    var count: Int { lock.withLock { values.count } }
    func read(accountID: UUID, allowInteraction: Bool) throws -> ClaudeCredentials? { lock.withLock { values[accountID] } }
    func save(_ credentials: ClaudeCredentials, accountID: UUID, allowInteraction: Bool) throws { lock.withLock { values[accountID] = credentials } }
    func remove(accountID: UUID, allowInteraction: Bool) throws { _ = lock.withLock { values.removeValue(forKey: accountID) } }
}

private actor OAuthTransport: ClaudeHTTPTransport {
    enum Step: Sendable { case response(ClaudeHTTPResponse), suspended(ClaudeHTTPResponse), failure }
    private var steps: [Step]
    private(set) var requests: [URLRequest] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private var pauseObserver: CheckedContinuation<Void, Never>?
    init(steps: [Step]) { self.steps = steps }
    func send(_ request: URLRequest) async throws -> ClaudeHTTPResponse {
        requests.append(request)
        guard !steps.isEmpty else { throw UsageError.providerFailure("No fixture response remains.") }
        switch steps.removeFirst() {
        case .response(let response): return response
        case .failure: throw UsageError.providerFailure("Fixture transport failed.")
        case .suspended(let response):
            await withCheckedContinuation { continuation = $0; pauseObserver?.resume(); pauseObserver = nil }
            return response
        }
    }
    func waitUntilPaused() async {
        if continuation != nil { return }
        await withCheckedContinuation { pauseObserver = $0 }
    }
    func release() { continuation?.resume(); continuation = nil }
}
