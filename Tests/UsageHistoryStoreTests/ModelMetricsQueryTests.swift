import Foundation
import Testing
import UsageHistory
@testable import UsageHistoryStore

private let start = Date(timeIntervalSince1970: 1_760_000_000)

private func withDatabase(_ body: (HistoryDatabase) async throws -> Void) async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ModelMetricsQueryTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    try await body(try HistoryDatabase(url: directory.appendingPathComponent("history.sqlite")))
}

private func response(_ id: String, provider: HistoryProvider = .claude, model: String = "claude-opus-5-5",
                      session: String = "s1", turn: String = "t1", seconds: Double? = 10, outputTokens: Int?,
                      thinkingTokens: Int?, toolCalls: Int = 0, parallel: Bool = false) -> ModelResponse {
    ModelResponse(provider: provider, responseID: id, sessionID: session, turnID: turn, model: model, projectKey: nil,
                  requestedAt: seconds.map { start.addingTimeInterval(-$0) }, completedAt: start,
                  outputTokens: outputTokens, thinkingTokens: thinkingTokens, toolCallCount: toolCalls,
                  hasParallelToolCalls: parallel)
}

private func command(_ id: String, model: String = "claude-opus-5-5", project: String? = "busy", text: String = "ls",
                     succeeded: Bool? = true, search: SearchProgram = .none, gitStatus: Bool = false,
                     gitCommit: Bool = false, interpreter: InlineInterpreter = .none,
                     purpose: InlineScriptPurpose? = nil, scriptLines: Int? = nil) -> ShellCommandRecord {
    let event = ShellCommandEvent(provider: .claude, commandID: id, responseID: "r", sessionID: "s1", model: model,
                                  projectKey: project, executedAt: start, succeeded: succeeded, command: text)
    let classification = CommandClassification(
        searchProgram: search, pipesIntoHeadOrTail: false, runsGitStatus: gitStatus, runsGitCommit: gitCommit,
        inlineInterpreter: interpreter, runsSavedScript: false, inlineScriptPurpose: purpose,
        inlineScriptLineCount: scriptLines, programSequence: "")
    return ShellCommandRecord(event: event, classification: classification, classifierVersion: 1)
}

@Test func unknownTokenCountsAreLeftOutRatherThanCountedAsZero() async throws {
    try await withDatabase { database in
        try await database.pool.write { db in
            try response("a", turn: "t1", seconds: 10, outputTokens: 1_000, thinkingTokens: 400, toolCalls: 2,
                         parallel: true).insert(db)
            try response("b", turn: "t1", seconds: 10, outputTokens: 500, thinkingTokens: 100).insert(db)
            try response("c", turn: "t2", seconds: 10, outputTokens: nil, thinkingTokens: nil).insert(db)
            try response("d", turn: "t2", seconds: nil, outputTokens: 900, thinkingTokens: nil).insert(db)
            try response("e", session: "s2", turn: "t3", outputTokens: 10, thinkingTokens: 0).insert(db)
            try response("x", provider: .codex, model: "gpt-6.1-sol", outputTokens: 300, thinkingTokens: 30).insert(db)
        }
        let report = try await database.modelMetrics()
        #expect(report.models.map(\.model) == ["claude-opus-5-5", "gpt-6.1-sol"])
        let opus = try #require(report.models.first)
        #expect(opus.responseCount == 5)
        #expect(opus.thinkingTokens == MetricRatio(count: 500, total: 1_510))
        #expect(opus.parallelToolCallResponses == MetricRatio(count: 1, total: 5))
        #expect(opus.outputSpeed?.sampleCount == 3)
        #expect(opus.outputSpeed?.median == 50)
        #expect(opus.stepsPerTurn?.sampleCount == 2)
        #expect(opus.stepsPerTurn?.mean == 2)
        #expect(opus.isSmallSample)
        #expect(report.models[1].provider == .codex)
        #expect(report.models[1].stepsPerTurn == nil)
    }
}

@Test func updatesDeliverRowsCommittedAfterTheFirstReport() async throws {
    try await withDatabase { database in
        var updates = database.modelMetricsUpdates().makeAsyncIterator()
        #expect(try await updates.next()?.isEmpty == true)
        try await database.pool.write { db in
            try response("a", outputTokens: 100, thinkingTokens: 10).insert(db)
        }
        #expect(try await updates.next()?.models.first?.responseCount == 1)
    }
}

@Test func shellMetricsUseTheirOwnDenominators() async throws {
    try await withDatabase { database in
        try await database.pool.write { db in
            try command("1", search: .grep).insert(db)
            try command("2", search: .grep).insert(db)
            try command("3", search: .ripgrep).insert(db)
            try command("4", gitStatus: true).insert(db)
            try command("5", gitStatus: true).insert(db)
            try command("6", gitStatus: true).insert(db)
            try command("7", succeeded: true, gitCommit: true).insert(db)
            try command("8", succeeded: false, gitCommit: true).insert(db)
            try command("9", succeeded: nil, gitCommit: true).insert(db)
            try command("10", project: "quiet", text: "python3 - <<EOF\n1\n2\nEOF", interpreter: .python,
                        purpose: .readsJSON, scriptLines: 2).insert(db)
            try command("11", project: "quiet", interpreter: .python, purpose: .editsFileInPlace, scriptLines: 10).insert(db)
            try command("12", project: "quiet", interpreter: .javascript, scriptLines: 4).insert(db)
            try command("13", project: nil, interpreter: .python, purpose: .readsJSON, scriptLines: 6).insert(db)
            try command("14", project: "quiet").insert(db)
            try command("15", model: "claude-fable-5-1", project: "quiet").insert(db)
            try command("16", model: "claude-fable-5-1", project: "quiet", interpreter: .python).insert(db)
            try command("17", model: "claude-fable-5-1", project: "busy", interpreter: .python).insert(db)
            try command("18", model: "claude-sonnet-5", succeeded: nil, gitCommit: true).insert(db)
        }
        let models = try await database.modelMetrics().models
        let fable = try #require(models.first { $0.model == "claude-fable-5-1" })
        #expect(fable.inlineOutsideBusiestProject == MetricRatio(count: 1, total: 1))
        #expect(models.first { $0.model == "claude-sonnet-5" }?.gitStatusPerCommit == MetricRatio(count: 0, total: 0))
        let opus = try #require(models.first { $0.model == "claude-opus-5-5" })
        #expect(opus.shellCommandCount == 14)
        #expect(opus.grepSearches == MetricRatio(count: 2, total: 3))
        #expect(opus.gitStatusPerCommit == MetricRatio(count: 3, total: 1))
        #expect(opus.inlineCode == MetricRatio(count: 4, total: 14))
        #expect(opus.inlinePython.count == 3)
        #expect(opus.inlineOutsideBusiestProject == MetricRatio(count: 3, total: 4))
        #expect(opus.inlinePythonPurposes == [.readsJSON: 2, .editsFileInPlace: 1])
        #expect(opus.inlineScriptLines?.median == 5)
        #expect(abs((opus.inlineScriptLines?.percentile90 ?? 0) - 8.8) < 1e-9)
        #expect(opus.commandLength?.median == 2)
    }
}
