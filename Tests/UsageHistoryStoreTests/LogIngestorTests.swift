import Foundation
import GRDB
import Testing
import UsageHistory
@testable import UsageHistoryStore

// Synthetic log lines. Every prompt, command, and account id below is invented.

private func temporaryHome() throws -> URL {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("LogIngestorTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    return home
}

private func write(_ lines: [String], to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(lines.map { $0 + "\n" }.joined().utf8).write(to: url)
}

private func codexSession(account: String, usedPercent: [Int]) -> [String] {
    func line(_ second: Int, _ type: String, _ payload: String) -> String {
        #"{"timestamp":"2026-10-14T10:00:\#(10 + second).000Z","type":"\#(type)","payload":\#(payload)}"#
    }
    var lines = [
        line(0, "session_meta", #"{"cwd":"/work/app","creator_account_id":"\#(account)"}"#),
        line(1, "event_msg", #"{"type":"task_started","turn_id":"turn-1"}"#),
        line(2, "turn_context", #"{"cwd":"/work/app","model":"gpt-test"}"#)
    ]
    for (index, percent) in usedPercent.enumerated() {
        lines += [
            line(3 + index * 3, "response_item", #"{"type":"reasoning","summary":[]}"#),
            line(4 + index * 3, "event_msg", #"{"type":"item_completed","item":{"id":"item-\#(index)","type":"command_execution","command":"rg synthetic","exit_code":0}}"#),
            line(5 + index * 3, "event_msg", #"{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":\#(percent),"window_minutes":300,"resets_at":1791990000}}}"#)
        ]
    }
    return lines + [line(40, "event_msg", #"{"type":"task_complete"}"#)]
}

private let claudeSession = [
    #"{"type":"user","uuid":"u1","timestamp":"2026-10-14T10:00:00.000Z","sessionId":"s1","cwd":"/work/app","message":{"role":"user","content":"synthetic prompt"}}"#,
    #"{"type":"assistant","uuid":"a1","timestamp":"2026-10-14T10:00:05.000Z","sessionId":"s1","cwd":"/work/app","message":{"id":"msg_1","model":"claude-test-1","content":[{"type":"tool_use","id":"toolu_1","name":"Bash","input":{"command":"grep -r synthetic ."}}],"stop_reason":"tool_use","usage":{"output_tokens":12}}}"#
]

private func rowCounts(_ database: HistoryDatabase) throws -> [Int] {
    try database.pool.read { db in
        try ["quotaReading", "modelResponse", "shellCommand"].map { try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \($0)") ?? 0 }
    }
}

@Test func codexBackfillAttachesReadingsOnlyToTheMatchingAccount() async throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let sessions = home.appendingPathComponent(".codex/sessions/2026/10/14")
    try write(codexSession(account: "acct-linked", usedPercent: [10, 10, 20]),
              to: sessions.appendingPathComponent("rollout-2026-10-14T10-00-00-0199e2a1-0000-7000-8000-000000000001.jsonl"))
    try write(codexSession(account: "acct-unlinked", usedPercent: [50]),
              to: sessions.appendingPathComponent("rollout-2026-10-14T11-00-00-0199e2a1-0000-7000-8000-000000000002.jsonl"))
    try write(codexSession(account: "acct-shared", usedPercent: [70]),
              to: sessions.appendingPathComponent("rollout-2026-10-14T12-00-00-0199e2a1-0000-7000-8000-000000000003.jsonl"))
    let database = try HistoryDatabase(url: home.appendingPathComponent("history.sqlite"))
    let ingestor = LogIngestor(database: database, homeDirectory: home)
    let linked = UUID(), firstShared = UUID(), secondShared = UUID()

    // Read before the account is linked: every reading is dropped.
    var summary = await ingestor.ingest(codexAccounts: [])
    #expect(summary.quotaReadingsMatched == 0)
    #expect(try await database.pool.read(QuotaReading.fetchCount) == 0)

    // Linking the account reads the logs again. A Codex account id shared by two app accounts matches neither.
    summary = await ingestor.ingest(codexAccounts: [
        CodexAccountLink(accountID: linked, providerAccountID: "acct-linked"),
        CodexAccountLink(accountID: firstShared, providerAccountID: "acct-shared"),
        CodexAccountLink(accountID: secondShared, providerAccountID: "acct-shared")
    ])
    #expect(summary.filesRead == 3)
    #expect(summary.quotaReadingsMatched == 3)
    #expect(summary.quotaReadingsUnmatched == 2)
    let readings = try await database.pool.read(QuotaReading.fetchAll)
    #expect(Set(readings.map(\.accountID)) == [linked])
    // Only changes are kept: 10, then 20.
    #expect(readings.map(\.usedPercent).sorted() == [10, 20])
    #expect(readings.allSatisfy { $0.source == .codexLogBackfill && $0.windowID == "codex_primary" })
}

@Test func rereadingOrMovingALogAddsNothing() async throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let name = "rollout-2026-10-14T10-00-00-0199e2a1-0000-7000-8000-000000000001.jsonl"
    let codexFile = home.appendingPathComponent(".codex/sessions/2026/10/14/\(name)")
    try write(codexSession(account: "acct", usedPercent: [10, 20]), to: codexFile)
    try write(claudeSession, to: home.appendingPathComponent(".claude/projects/-work-app/s1.jsonl"))
    let database = try HistoryDatabase(url: home.appendingPathComponent("history.sqlite"))
    let ingestor = LogIngestor(database: database, homeDirectory: home)
    let accounts = [CodexAccountLink(accountID: UUID(), providerAccountID: "acct")]

    let first = await ingestor.ingest(codexAccounts: accounts)
    #expect(first.filesRead == 2 && first.filesFailed == 0)
    let counts = try rowCounts(database)
    #expect(counts == [2, 3, 3])

    let unchanged = await ingestor.ingest(codexAccounts: accounts)
    #expect(unchanged.filesUnchanged == 2 && unchanged.filesRead == 0)

    // Codex archives a session by moving it; the new path is read from the start.
    let archived = home.appendingPathComponent(".codex/archived_sessions/\(name)")
    try FileManager.default.createDirectory(at: archived.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: codexFile, to: archived)
    try await database.pool.write { db in _ = try SourceFilePosition.deleteAll(db) }
    let reread = await ingestor.ingest(codexAccounts: accounts)
    #expect(reread.filesRead == 2 && reread.quotaReadingsAdded == 0)
    #expect(try rowCounts(database) == counts)
}

@Test func recorderSkipsAReadingThatIsNotNewer() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let database = try HistoryDatabase(url: home.appendingPathComponent("history.sqlite"))
    let account = UUID()
    func reading(_ window: String, at second: TimeInterval, used: Double) -> QuotaReading {
        QuotaReading(provider: .claude, accountID: account, windowID: window, usedPercent: used, resetsAt: nil,
                     windowDurationMinutes: nil, observedAt: Date(timeIntervalSince1970: 1_791_972_000 + second),
                     source: .claudeOAuth)
    }

    #expect(try database.recordQuotaReadings([reading("five_hour", at: 0, used: 10), reading("seven_day", at: 0, used: 30)]) == 2)
    // A failed refresh keeps the earlier reading time; an older capture reports an earlier one.
    #expect(try database.recordQuotaReadings([reading("five_hour", at: 0, used: 10), reading("seven_day", at: 0, used: 30)]) == 0)
    #expect(try database.recordQuotaReadings([reading("five_hour", at: -60, used: 5)]) == 0)
    #expect(try database.recordQuotaReadings([reading("five_hour", at: 300, used: 12)]) == 1)
}
