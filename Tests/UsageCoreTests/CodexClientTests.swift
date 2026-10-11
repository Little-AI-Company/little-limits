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
}
