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
                      model: "claude-opus-5-5", projectName: "ai-usage-stats", requestedAt: nil,
                      completedAt: observedAt, outputTokens: outputTokens, thinkingTokens: 0, toolCallCount: 2,
                      hasParallelToolCalls: true)
    }
    func event(succeeded: Bool?) -> ShellCommandEvent {
        ShellCommandEvent(provider: .claude, commandID: "toolu_1", responseID: "msg_1", sessionID: "session",
                          model: "claude-opus-5-5", projectName: nil, executedAt: observedAt, succeeded: succeeded,
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
