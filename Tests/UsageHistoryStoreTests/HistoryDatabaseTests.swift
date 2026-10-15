import Foundation
import GRDB
import Testing
import UsageHistory
@testable import UsageHistoryStore

private let observedAt = Date(timeIntervalSince1970: 1_760_000_000)

private func temporaryDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("UsageHistoryStoreTests-\(UUID().uuidString)")
        .appendingPathComponent("history.sqlite")
}

@Test func laterReadsCompleteRecordsWithoutDuplicatesAndSurviveReopening() throws {
    let url = temporaryDatabaseURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let reading = QuotaReading(provider: .codex, accountID: UUID(), windowID: "codex_secondary", usedPercent: 0,
                               resetsAt: nil, windowDurationMinutes: 10_080, observedAt: observedAt,
                               source: .codexLogBackfill)
    func response(outputTokens: Int?) -> ModelResponse {
        ModelResponse(provider: .claude, responseID: "msg_1", sessionID: "session", turnID: "turn",
                      model: "claude-opus-5-5", projectKey: "0123456789abcdef", requestedAt: nil,
                      completedAt: observedAt, outputTokens: outputTokens, thinkingTokens: 0, toolCallCount: 2,
                      hasParallelToolCalls: true)
    }
    func event(succeeded: Bool?) -> ShellCommandEvent {
        ShellCommandEvent(provider: .claude, commandID: "toolu_1", responseID: "msg_1", sessionID: "session",
                          model: "claude-opus-5-5", projectKey: nil, executedAt: observedAt, succeeded: succeeded,
                          command: "git status")
    }
    let classification = CommandClassification(searchProgram: .none, pipesIntoHeadOrTail: false, runsGitStatus: true,
                                               runsGitCommit: false, inlineInterpreter: .none, runsSavedScript: false,
                                               inlineScriptPurpose: nil, inlineScriptLineCount: nil,
                                               programSequence: "git status")
    let partialCommand = ShellCommandRecord(event: event(succeeded: nil), classification: classification,
                                            classifierVersion: 1)
    let command = ShellCommandRecord(event: event(succeeded: true), classification: classification, classifierVersion: 1)

    // The first read ends before the response's final usage line and the command's result.
    let database = try HistoryDatabase(url: url)
    try database.pool.write { db in
        try reading.insert(db)
        try response(outputTokens: nil).insert(db)
        try partialCommand.insert(db)
    }
    try database.pool.write { db in
        try reading.insert(db)
        try response(outputTokens: 120).insert(db)
        try command.insert(db)
    }

    let reopened = try HistoryDatabase(url: url)
    // A new salt would split every project's history at the reopen.
    #expect(reopened.projectKeySalt == database.projectKeySalt)
    #expect(database.projectKeySalt.count == 16)
    let stored = try reopened.pool.read { db in
        (try QuotaReading.fetchAll(db), try ModelResponse.fetchAll(db), try ShellCommandRecord.fetchAll(db))
    }
    #expect(stored.0 == [reading])
    #expect(stored.1 == [response(outputTokens: 120)])
    #expect(stored.2 == [command])
}

@Test func newerSourceFilePositionReplacesTheOldOne() throws {
    let url = temporaryDatabaseURL()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let database = try HistoryDatabase(url: url)
    let first = SourceFilePosition(path: "/logs/a.jsonl", byteOffset: 10, fileSize: 10, modifiedAt: observedAt)
    let second = SourceFilePosition(path: "/logs/a.jsonl", byteOffset: 25, fileSize: 25,
                                    modifiedAt: observedAt.addingTimeInterval(60))
    try database.pool.write { db in
        try first.insert(db)
        try second.insert(db)
    }
    #expect(try database.pool.read(SourceFilePosition.fetchAll) == [second])
}

/// A v2 database keeps its quota history, gains the index, and forgets its read positions, so every log is read
/// again with the current Codex command attribution.
@Test func freshAndPreviousVersionDatabasesMigrateCleanly() throws {
    let freshURL = temporaryDatabaseURL()
    let previousURL = temporaryDatabaseURL()
    defer {
        try? FileManager.default.removeItem(at: freshURL.deletingLastPathComponent())
        try? FileManager.default.removeItem(at: previousURL.deletingLastPathComponent())
    }
    let reading = QuotaReading(provider: .claude, accountID: UUID(), windowID: "seven_day", usedPercent: 40,
                               resetsAt: nil, windowDurationMinutes: 10_080, observedAt: observedAt,
                               source: .claudeOAuth)
    try FileManager.default.createDirectory(at: previousURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
    let previous = try DatabasePool(path: previousURL.path)
    try HistoryDatabase.migrator.migrate(previous, upTo: "v2")
    try previous.write { db in
        try reading.insert(db)
        try SourceFilePosition(path: "/logs/a.jsonl", byteOffset: 10, fileSize: 10, modifiedAt: observedAt).insert(db)
    }
    try previous.close()

    for url in [freshURL, previousURL] {
        let database = try HistoryDatabase(url: url)
        let state = try database.pool.read { db in
            (try HistoryDatabase.migrator.hasCompletedMigrations(db),
             try db.indexes(on: QuotaReading.databaseTableName).map(\.columns))
        }
        #expect(state.0)
        #expect(state.1.contains(["observedAt"]))
    }
    let migrated = try HistoryDatabase(url: previousURL).pool.read { db in
        (try QuotaReading.fetchAll(db), try SourceFilePosition.fetchCount(db))
    }
    #expect(migrated.0 == [reading])
    #expect(migrated.1 == 0)
}
