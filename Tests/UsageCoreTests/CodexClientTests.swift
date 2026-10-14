import Darwin
import Foundation
import XCTest
import Testing
@testable import UsageCore

final class CodexClientTests: XCTestCase {
    func testReadOnlyProtocolAndProfileIsolation() throws {
        let fixture = try CodexProcessFixture(script: CodexProcessFixture.responses)
        defer { fixture.remove() }

        let result = try CodexClient(executable: fixture.executable, home: fixture.home)
            .fetch(profileID: UUID(), expectedIdentity: "account-a")

        XCTAssertEqual(result.accountIdentity, "account-a")
        XCTAssertEqual(result.accountEmail, "fixture@example.com")
        XCTAssertEqual(result.snapshot.state, .available)
        XCTAssertEqual(result.snapshot.windows.map(\.utilizationPercent), [25, 40])
        XCTAssertEqual(result.snapshot.windows.first?.resetsAt?.timeIntervalSince1970, 2_000_000_000)
        XCTAssertEqual(result.snapshot.credits.first?.amount, Decimal(string: "12.50"))
        XCTAssertEqual(result.snapshot.credits.first?.unit, .credits)
        XCTAssertEqual(result.snapshot.credits.first(where: { $0.id == "quota_reset_credits" })?.amount, 2)
        XCTAssertEqual(result.snapshot.credits.first(where: { $0.id == "quota_reset_reset-a" })?.expiresAt?.timeIntervalSince1970,
                       2_100_000_000)

        let trace = try String(contentsOf: fixture.home.appendingPathComponent("requests.jsonl"), encoding: .utf8)
        let requests = try trace.split(separator: "\n").map { line in
            try JSONDecoder().decode(RequestRecord.self, from: Data(line.utf8))
        }
        XCTAssertEqual(requests.map(\.method), ["initialize", "initialized", "account/read", "account/rateLimits/read"])
        XCTAssertEqual(requests[2].params?.refreshToken, false)
        XCTAssertEqual(try String(contentsOf: fixture.home.appendingPathComponent("arguments.txt"), encoding: .utf8),
                       "app-server --listen stdio://\n")
        let actualDirectory = try String(contentsOf: fixture.home.appendingPathComponent("directory.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let actualAttributes = try FileManager.default.attributesOfItem(atPath: actualDirectory)
        let expectedAttributes = try FileManager.default.attributesOfItem(atPath: fixture.home.path)
        XCTAssertEqual(actualAttributes[.systemFileNumber] as? NSNumber, expectedAttributes[.systemFileNumber] as? NSNumber)
        XCTAssertEqual(actualAttributes[.systemNumber] as? NSNumber, expectedAttributes[.systemNumber] as? NSNumber)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent("environment-error").path))
        try assertChildStopped(fixture)
    }

    func testDifferentAccountIdentityRejectsUsage() throws {
        let fixture = try CodexProcessFixture(script: CodexProcessFixture.responses)
        defer { fixture.remove() }

        XCTAssertThrowsError(try CodexClient(executable: fixture.executable, home: fixture.home)
            .fetch(profileID: UUID(), expectedIdentity: "account-b")) { error in
                guard case UsageError.authenticationRequired = error else {
                    return XCTFail("Expected authenticationRequired, received \(error)")
                }
            }
        try assertChildStopped(fixture)
    }

    func testExecutableStartFailureThrows() throws {
        let fixture = try CodexProcessFixture(script: CodexProcessFixture.responses)
        defer { fixture.remove() }
        let missingExecutable = fixture.home.appendingPathComponent("missing-codex")

        XCTAssertThrowsError(try CodexClient(executable: missingExecutable, home: fixture.home)
            .fetch(profileID: UUID(), expectedIdentity: nil))
    }

    func testUnresponsiveProcessTimesOutAndIsReaped() throws {
        let fixture = try CodexProcessFixture(script: "trap '' TERM\nexec /bin/sleep 30\n")
        defer { fixture.remove() }
        let startedAt = Date()

        XCTAssertThrowsError(try CodexClient(executable: fixture.executable, home: fixture.home, timeout: 0.25)
            .fetch(profileID: UUID(), expectedIdentity: nil))

        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
        try assertChildStopped(fixture)
    }

    func testCompletedProcessIgnoringTerminationIsReaped() throws {
        let fixture = try CodexProcessFixture(script: CodexProcessFixture.responses + "trap '' TERM\nexec /bin/sleep 30\n")
        defer { fixture.remove() }
        let startedAt = Date()

        let result = try CodexClient(executable: fixture.executable, home: fixture.home, timeout: 2)
            .fetch(profileID: UUID(), expectedIdentity: "account-a")

        XCTAssertEqual(result.snapshot.state, .available)
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 3)
        try assertChildStopped(fixture)
    }

    private func assertChildStopped(_ fixture: CodexProcessFixture, file: StaticString = #filePath, line: UInt = #line) throws {
        let text = try String(contentsOf: fixture.home.appendingPathComponent("child.pid"), encoding: .utf8)
        let identifier = try XCTUnwrap(Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), file: file, line: line)
        XCTAssertEqual(kill(identifier, 0), -1, "Child process survived client cleanup.", file: file, line: line)
        XCTAssertEqual(errno, ESRCH, file: file, line: line)
    }
}

@Test func codexLoginEmailPersistsOnlyForTheValidatedAccount() async throws {
    let fixture = try CodexProcessFixture(script: CodexProcessFixture.responses)
    defer { fixture.remove() }
    let directory = fixture.directory.appendingPathComponent("Store")
    let service = UsageService(directory: directory, codexExecutableURL: fixture.executable)
    let profile = try await service.createCodexProfile(label: "Legacy label")
    _ = await service.refreshAccount(id: profile.id)
    let bound = try #require(try await service.load().first)
    #expect(bound.id == profile.id && bound.providerAccountID == "account-a")
    #expect(bound.providerEmail == "fixture@example.com")
    #expect(bound.label == "Legacy label")
    let original = try String(contentsOf: fixture.executable, encoding: .utf8)
    try original.replacingOccurrences(of: "\"email\":\"fixture@example.com\",", with: "").write(to: fixture.executable, atomically: false, encoding: .utf8)
    _ = await service.refreshAccount(id: profile.id)
    #expect(try await service.load().first?.providerEmail == "fixture@example.com")
    try original.replacingOccurrences(of: "account-a", with: "account-b").replacingOccurrences(of: "fixture@example.com", with: "other@example.invalid")
        .write(to: fixture.executable, atomically: false, encoding: .utf8)
    let failed = await service.refreshAccount(id: profile.id)
    #expect(failed.state == .authenticationRequired)
    let preserved = try #require(try await service.load().first)
    #expect(preserved.providerAccountID == "account-a" && preserved.providerEmail == "fixture@example.com")
    let reloaded = UsageService(directory: directory, codexExecutableURL: fixture.executable)
    #expect(try await reloaded.load().first?.providerEmail == "fixture@example.com")
}

@Test func codexAccountPlanAndMeasuredDurationsPersistThroughFailedRefresh() async throws {
    let fixture = try CodexProcessFixture(script: CodexProcessFixture.responses)
    defer { fixture.remove() }
    let directory = fixture.directory.appendingPathComponent("Store")
    let service = UsageService(directory: directory, codexExecutableURL: fixture.executable)
    let profile = try await service.createCodexProfile(label: "Work")
    let fresh = await service.refreshAccount(id: profile.id)
    #expect(fresh.planName == "Plus")
    #expect(fresh.windows.map(\.windowDurationMinutes) == [300, 10_080])
    let original = try String(contentsOf: fixture.executable, encoding: .utf8)
    try original.replacingOccurrences(of: "account-a", with: "account-b").write(to: fixture.executable, atomically: false, encoding: .utf8)
    let failed = await service.refreshAccount(id: profile.id)
    #expect(failed.state == .authenticationRequired)
    #expect(failed.planName == "Plus")
    #expect(failed.windows.map(\.windowDurationMinutes) == [300, 10_080])
    let reloaded = UsageService(directory: directory, codexExecutableURL: fixture.executable)
    _ = try await reloaded.load()
    let stored = try #require(await reloaded.snapshot(for: profile.id))
    #expect(stored.planName == "Plus")
    #expect(stored.state == .authenticationRequired)
    #expect(stored.windows.map(\.windowDurationMinutes) == [300, 10_080])
}

@Test func codexPlanNameUsesKnownCodesWithoutInventingCapacityOrDuration() throws {
    func snapshot(_ json: String, planType: String? = nil) throws -> AccountSnapshot {
        try JSONDecoder().decode(CodexUsageResponse.self, from: Data(json.utf8))
            .snapshot(profileID: UUID(), observedAt: Date(timeIntervalSince1970: 1_000), planType: planType)
    }
    let explicit = try snapshot(#"{"rateLimits":{"planType":"pro","primary":{"usedPercent":25,"resetsAt":2000}}}"#, planType: " plus ")
    #expect(explicit.planName == "Pro")
    #expect(explicit.windows.map(\.windowDurationMinutes) == [nil])
    let measured = try snapshot(#"{"rateLimits":{"planType":"PLUS","primary":{"usedPercent":0,"windowDurationMins":300,"resetsAt":2000}}}"#)
    #expect(measured.planName == "Plus")
    #expect(measured.windows.first?.windowDurationMinutes == 300)
    let suppressed = try snapshot(#"{"rateLimits":{"planType":"plus","primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":2000}}}"#, planType: " unknown ")
    #expect(suppressed.planName == "Plus")
    let blank = try snapshot(#"{"rateLimits":{"planType":"pro","primary":{"usedPercent":1,"windowDurationMins":10080,"resetsAt":2000}}}"#, planType: " ")
    #expect(blank.planName == "Pro")
    #expect(blank.windows.first?.windowDurationMinutes == 10_080)
    let conflict = try snapshot(#"{"rateLimitsByLimitId":{"b":{"planType":"pro","primary":{"usedPercent":2,"windowDurationMins":10080}},"a":{"planType":"plus","primary":{"usedPercent":1,"windowDurationMins":300}}}}"#)
    #expect(conflict.planName == nil)
    #expect(conflict.windows.map(\.windowDurationMinutes) == [300, 10_080])
    let raw = try snapshot(#"{"rateLimits":{"planType":"pro","primary":{"usedPercent":4,"windowDurationMins":300,"resetsAt":2000}}}"#, planType: "max_5x")
    #expect(raw.planName == "Pro")
    let fallback = try snapshot(#"{"rateLimits":{"primary":{"usedPercent":4,"resetsAt":2000}}}"#, planType: "plus")
    #expect(fallback.planName == "Plus")
    let conflictingFallback = try snapshot(#"{"rateLimitsByLimitId":{"a":{"planType":"plus"},"b":{"planType":"pro"}}}"#, planType: "plus")
    #expect(conflictingFallback.planName == nil)
    let reported = try snapshot(#"{"rateLimits":{"planType":"max_5x","primary":{"usedPercent":4,"windowDurationMins":300,"resetsAt":2000}}}"#)
    #expect(reported.planName == "max_5x")
    let unknown = try snapshot(#"{"rateLimits":{"planType":"unknown","primary":{"usedPercent":4,"resetsAt":2000}}}"#)
    #expect(unknown.planName == nil)
    #expect(unknown.windows.first?.windowDurationMinutes == nil)
    let enterprise = try snapshot(#"{"rateLimits":{"planType":"enterprise","primary":{"usedPercent":1,"windowDurationMins":300,"resetsAt":2000}}}"#)
    #expect(enterprise.planName == "Enterprise")
}

@Test func codexSignInWaitRefreshesOnceTheTerminalLoginFinishes() async throws {
    let fixture = try CodexProcessFixture(script: CodexProcessFixture.signedInAfterThirdRead)
    defer { fixture.remove() }
    let service = UsageService(directory: fixture.directory.appendingPathComponent("Store"), codexExecutableURL: fixture.executable)
    let profile = try await service.createCodexProfile(label: "Work")

    let outcome = await service.awaitCodexSignIn(id: profile.id, interval: .milliseconds(20), timeout: .seconds(20))

    guard case .signedIn(let snapshot) = outcome else { return #expect(Bool(false), "Expected sign-in, received \(outcome)") }
    #expect(snapshot.state == .available && snapshot.profileID == profile.id)
    #expect(try await service.load().first?.providerAccountID == "account-a")
}

@Test func codexSignInWaitStopsOnTimeoutCancellationAndRemoval() async throws {
    let fixture = try CodexProcessFixture(script: CodexProcessFixture.signedOut)
    defer { fixture.remove() }
    let service = UsageService(directory: fixture.directory.appendingPathComponent("Store"), codexExecutableURL: fixture.executable)
    let profile = try await service.createCodexProfile(label: "Work")

    #expect(await service.awaitCodexSignIn(id: profile.id, interval: .milliseconds(20), timeout: .milliseconds(300)) == .timedOut)

    let cancelled = Task { await service.awaitCodexSignIn(id: profile.id, interval: .milliseconds(20), timeout: .seconds(60)) }
    cancelled.cancel()
    #expect(await cancelled.value == .cancelled)

    let removed = Task { await service.awaitCodexSignIn(id: profile.id, interval: .milliseconds(20), timeout: .seconds(60)) }
    try await Task.sleep(for: .milliseconds(100))
    try await service.removeAccount(id: profile.id)
    #expect(await removed.value == .accountRemoved)
}

@Test func currentCodexLoginIsReadOnlyAndListedOnce() async throws {
    let fixture = try CodexProcessFixture(script: CodexProcessFixture.responses)
    defer { fixture.remove() }
    let home = fixture.home.standardizedFileURL.resolvingSymlinksInPath()
    let service = UsageService(directory: fixture.directory.appendingPathComponent("Store"), codexExecutableURL: fixture.executable,
                               codexDefaultHomeURL: fixture.home)

    let login = try #require(await service.currentCodexLogin())
    #expect(login.email == "fixture@example.com" && login.home == home)
    let trace = try String(contentsOf: fixture.home.appendingPathComponent("requests.jsonl"), encoding: .utf8)
    let methods = try trace.split(separator: "\n").map { try JSONDecoder().decode(RequestRecord.self, from: Data($0.utf8)).method }
    #expect(methods == ["initialize", "initialized", "account/read"])

    let profile = try await service.createCodexProfileUsingCurrentLogin(label: "Codex Account")
    #expect(profile.source == .codexDefaultLogin && profile.sourcePath == home.path)
    #expect(profile.providerAccountID == "account-a" && profile.providerEmail == "fixture@example.com")
    #expect(await service.snapshot(for: profile.id)?.windows.isEmpty == false)
    #expect(!FileManager.default.fileExists(atPath: fixture.home.appendingPathComponent("config.toml").path))

    // The same login, or another profile signed in to the same Codex account, is refused.
    #expect(await service.currentCodexLogin() == nil)
    await #expect(throws: UsageError.self) { try await service.createCodexProfileUsingCurrentLogin(label: "Again") }
    await #expect(throws: UsageError.self) { try await service.codexLoginCommand(accountID: profile.id) }
    let separate = try await service.createCodexProfile(label: "Separate")
    #expect(await service.refreshAccount(id: separate.id).state == .authenticationRequired)
    #expect(try await service.load().first { $0.id == separate.id }?.providerAccountID == nil)

    try await service.removeAccount(id: profile.id)
    #expect(FileManager.default.fileExists(atPath: fixture.home.path))
}

@Test func currentCodexLoginIsAbsentWhenSignedOutOrMissing() async throws {
    let fixture = try CodexProcessFixture(script: CodexProcessFixture.signedOut)
    defer { fixture.remove() }
    let store = fixture.directory.appendingPathComponent("Store")
    #expect(await UsageService(directory: store, codexExecutableURL: fixture.executable, codexDefaultHomeURL: fixture.home)
        .currentCodexLogin() == nil)
    let missing = fixture.directory.appendingPathComponent("missing-home")
    #expect(await UsageService(directory: store, codexExecutableURL: fixture.executable, codexDefaultHomeURL: missing)
        .currentCodexLogin() == nil)
    #expect(!FileManager.default.fileExists(atPath: missing.path))
}

private struct RequestRecord: Decodable {
    struct Parameters: Decodable { let refreshToken: Bool? }
    let method: String
    let params: Parameters?
}

private struct CodexProcessFixture {
    let directory: URL
    let home: URL
    let executable: URL

    init(script: String) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("codex-client-test-" + UUID().uuidString,
                                                                                 isDirectory: true)
        home = directory.appendingPathComponent("profile", isDirectory: true)
        executable = directory.appendingPathComponent("codex-fixture")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let preamble = #"""
        #!/bin/sh
        trap '' TERM
        printf '%s\n' "$$" > "$CODEX_HOME/child.pid"
        printf '%s\n' "$*" > "$CODEX_HOME/arguments.txt"
        pwd -P > "$CODEX_HOME/directory.txt"
        if [ "${CODEX_ACCESS_TOKEN+x}" = x ] || [ "${CODEX_API_KEY+x}" = x ] || [ "${OPENAI_API_KEY+x}" = x ]; then
          : > "$CODEX_HOME/environment-error"
          exit 70
        fi

        """#
        try Data((preamble + script).utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    static let responses = #"""
    phase=0
    while IFS= read -r request; do
      printf '%s\n' "$request" >> "$CODEX_HOME/requests.jsonl"
      phase=$((phase + 1))
      case "$phase" in
        1)
          case "$request" in *initialize*) ;; *) exit 71 ;; esac
          printf '%s\n' '{"id":1,"result":{"userAgent":"codex-fixture","platformFamily":"unix","platformOs":"macos"}}'
          ;;
        2)
          case "$request" in *initialized*) ;; *) exit 72 ;; esac
          ;;
        3)
          case "$request" in *account*read*) ;; *) exit 73 ;; esac
          printf '%s\n' '{"method":"account/updated","params":{"authMode":"chatgpt","planType":"plus"}}'
          printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"fixture@example.com","planType":"plus"},"requiresOpenaiAuth":true}}'
          ;;
        4)
          case "$request" in *rateLimits*read*) ;; *) exit 74 ;; esac
          printf '%s\n' '{"id":3,"result":{"accountId":"account-a","rateLimits":{"limitId":"codex","primary":{"usedPercent":25,"windowDurationMins":300,"resetsAt":2000000000},"secondary":{"usedPercent":40,"windowDurationMins":10080,"resetsAt":2000100000},"credits":{"hasCredits":true,"unlimited":false,"balance":"12.50"}},"rateLimitResetCredits":{"availableCount":2,"credits":[{"id":"reset-a","resetType":"codexRateLimits","status":"available","grantedAt":1900000000,"expiresAt":2100000000,"title":"Earned reset"}]}}}'
          break
          ;;
        *) exit 75 ;;
      esac
    done

    """#

    /// `account/read` reports no login.
    static let signedOut = responses.replacingOccurrences(of: #"{"type":"chatgpt","email":"fixture@example.com","planType":"plus"}"#,
                                                          with: "null")

    /// `account/read` reports no login for the first two launches, as while `codex login` is still open.
    static let signedInAfterThirdRead = responses.replacingOccurrences(of: signedInReply, with:
        #"reads=$(($(cat "$CODEX_HOME/reads" 2>/dev/null || echo 0) + 1)); echo "$reads" > "$CODEX_HOME/reads"; "#
        + #"if [ "$reads" -lt 3 ]; then printf '%s\n' '{"id":2,"result":{"account":null,"requiresOpenaiAuth":true}}'; "#
        + "else \(signedInReply); fi")

    private static let signedInReply =
        #"printf '%s\n' '{"id":2,"result":{"account":{"type":"chatgpt","email":"fixture@example.com","planType":"plus"},"requiresOpenaiAuth":true}}'"#
}
