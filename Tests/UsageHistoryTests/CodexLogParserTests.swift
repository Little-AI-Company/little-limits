import Foundation
import Testing
import UsageHistory

private let salt: [UInt8] = Array(0..<16)
private let sessionID = "0199e2a1-7c4d-7f3e-9b21-5d6c8e0f1a2b"
private let logPath = "/logs/2026/10/14/rollout-2026-10-14T10-00-00-\(sessionID).jsonl"
private let projectKey = ProjectKey.make(workingDirectory: "/work/app", salt: salt)

private func at(_ second: Int) -> Date {
    Date(timeIntervalSince1970: 1_791_972_000 + Double(second) + 0.25)
}

private func entry(_ second: Int, _ type: String, _ payload: String) -> String {
    let seconds = second < 10 ? "0\(second)" : "\(second)"
    return #"{"timestamp":"2026-10-14T10:00:\#(seconds).250Z","type":"\#(type)","payload":\#(payload)}"#
}

private func event(_ second: Int, _ payload: String) -> String { entry(second, "event_msg", payload) }

private func sessionMeta(account: String?) -> String {
    let accountField = account.map { #","creator_account_id":"\#($0)""# } ?? ""
    return entry(0, "session_meta", #"{"id":"\#(sessionID)","cwd":"/work/app"\#(accountField)}"#)
}

private func taskStarted(_ second: Int, _ turnID: String) -> String {
    event(second, #"{"type":"task_started","turn_id":"\#(turnID)"}"#)
}

private func taskComplete(_ second: Int) -> String { event(second, #"{"type":"task_complete"}"#) }

private func turnContext(_ second: Int, model: String = "gpt-6.1-sol") -> String {
    entry(second, "turn_context", #"{"cwd":"/work/app","model":"\#(model)","effort":"high"}"#)
}

private func userPrompt(_ second: Int) -> String {
    entry(second, "response_item", #"{"type":"message","role":"user","content":[{"type":"input_text","text":"x"}]}"#)
}

private func reasoning(_ second: Int) -> String { entry(second, "response_item", #"{"type":"reasoning","summary":[]}"#) }

private func assistantReply(_ second: Int) -> String {
    entry(second, "response_item", #"{"type":"message","role":"assistant","content":[{"type":"output_text","text":"x"}]}"#)
}

private func toolCall(_ second: Int, _ name: String = "exec") -> String {
    entry(second, "response_item", #"{"type":"custom_tool_call","name":"\#(name)","call_id":"call","input":"x"}"#)
}

private func toolResult(_ second: Int) -> String {
    entry(second, "response_item", #"{"type":"custom_tool_call_output","call_id":"call","output":"x"}"#)
}

private func commandCompleted(_ second: Int, item: String, _ command: String, exitCode: Int) -> String {
    event(second, #"{"type":"item_completed","item":{"id":"\#(item)","type":"command_execution","command":"\#(command)","exit_code":\#(exitCode)}}"#)
}

private func usageRecord(_ second: Int, output: Int, reasoning: Int?) -> String {
    let reasoningField = reasoning.map { #","reasoning_output_tokens":\#($0)"# } ?? ""
    return event(second, #"{"type":"token_usage_record","usage":{"input_tokens":900,"output_tokens":\#(output)\#(reasoningField)}}"#)
}

private func tokenCount(_ second: Int, output: Int? = nil, reasoning: Int? = nil, rateLimits: String = "null") -> String {
    let info = output.map { #"{"last_token_usage":{"output_tokens":\#($0),"reasoning_output_tokens":\#(reasoning ?? 0)}}"# }
    return event(second, #"{"type":"token_count","info":\#(info ?? "null"),"rate_limits":\#(rateLimits)}"#)
}

private func offsets(_ lines: [String]) -> [Int64] {
    var offset: Int64 = 0
    return lines.map { line in
        defer { offset += Int64(line.utf8.count + 1) }
        return offset
    }
}

/// Parses `lines` from `start`. A resumed read passes the file's first line first.
private func parse(_ lines: [String], from start: Int64 = 0) -> LogParseOutput {
    var parser = CodexLogParser(filePath: logPath, projectKeySalt: salt)
    if start > 0 { parser.consume(line: Data(lines[0].utf8), at: 0) }
    for (line, offset) in zip(lines, offsets(lines)) where offset >= start {
        parser.consume(line: Data(line.utf8), at: offset)
    }
    return parser.finish()
}

@Test func oldAndNewTokenFormatsAndUnknownUsage() {
    let lines = [
        sessionMeta(account: "account-1"), taskStarted(1, "turn-1"), turnContext(1), userPrompt(2),
        reasoning(3), assistantReply(4), usageRecord(5, output: 120, reasoning: 80),
        tokenCount(5, output: 999, reasoning: 999),
        userPrompt(6), assistantReply(7), tokenCount(8, output: 50, reasoning: 20),
        userPrompt(9), assistantReply(10),
        userPrompt(11), assistantReply(12), usageRecord(13, output: 30, reasoning: nil),
        taskComplete(14)
    ]
    let output = parse(lines)

    #expect(output.responses.map(\.outputTokens) == [120, 50, nil, 30])
    #expect(output.responses.map(\.thinkingTokens) == [80, 20, nil, nil])
    let first = output.responses[0]
    #expect(first.responseID == "\(sessionID):\(offsets(lines)[4])")
    #expect(first.sessionID == sessionID)
    #expect(first.turnID == "turn-1")
    #expect(first.model == "gpt-6.1-sol")
    #expect(first.projectKey == projectKey)
    #expect(first.requestedAt == at(2))
    #expect(first.completedAt == at(5))
    #expect(output.responses[2].completedAt == at(10))
}

@Test func execWithTwoCommandsGivesTwoEventsAndParallelToolCalls() {
    let lines = [
        sessionMeta(account: "account-1"), taskStarted(1, "turn-1"), turnContext(1), userPrompt(2),
        reasoning(3), toolCall(4), usageRecord(5, output: 40, reasoning: 10),
        commandCompleted(6, item: "item_7", "rg TODO src", exitCode: 0),
        commandCompleted(7, item: "item_7", "git status", exitCode: 1),
        toolResult(8),
        toolCall(9, "shell"), usageRecord(10, output: 20, reasoning: 0),
        commandCompleted(11, item: "item_8", "ls", exitCode: 0),
        toolCall(12, "shell"), toolCall(12, "shell"), usageRecord(13, output: 20, reasoning: 0),
        toolResult(14), toolResult(14),
        assistantReply(15), usageRecord(16, output: 5, reasoning: 0), taskComplete(17)
    ]
    let output = parse(lines)

    #expect(output.responses.map(\.toolCallCount) == [1, 1, 2, 0])
    #expect(output.responses.map(\.hasParallelToolCalls) == [true, false, true, false])
    #expect(output.responses[1].requestedAt == at(8))
    #expect(output.commands.map(\.commandID) == ["item_7:0", "item_7:1", "item_8:0"])
    #expect(output.commands.map(\.command) == ["rg TODO src", "git status", "ls"])
    #expect(output.commands.map(\.succeeded) == [true, false, true])
    #expect(output.commands.map(\.executedAt) == [at(6), at(7), at(11)])
    let responseIDs = output.responses.map(\.responseID)
    #expect(output.commands.map(\.responseID) == [responseIDs[0], responseIDs[0], responseIDs[1]])
    #expect(output.commands.allSatisfy { $0.model == "gpt-6.1-sol" && $0.projectKey == projectKey })
}

private let rateLimitsWithID = #"""
{"limit_id":"premium","primary":{"used_percent":42.5,"window_minutes":300,"resets_at":1760450000},\#
"secondary":{"used_percent":10,"window_minutes":10080}}
"""#

@Test func quotaReadingsUseTheLimitIDOrCodex() {
    let lines = [
        sessionMeta(account: "account-1"),
        tokenCount(1, rateLimits: rateLimitsWithID),
        tokenCount(2, rateLimits: #"{"primary":{"used_percent":3,"window_minutes":300}}"#)
    ]

    #expect(parse(lines).quotaReadings == [
        LogQuotaReading(providerAccountID: "account-1", windowID: "premium_primary", usedPercent: 42.5,
                        resetsAt: Date(timeIntervalSince1970: 1_760_450_000), windowDurationMinutes: 300,
                        observedAt: at(1)),
        LogQuotaReading(providerAccountID: "account-1", windowID: "premium_secondary", usedPercent: 10,
                        resetsAt: nil, windowDurationMinutes: 10_080, observedAt: at(1)),
        LogQuotaReading(providerAccountID: "account-1", windowID: "codex_primary", usedPercent: 3,
                        resetsAt: nil, windowDurationMinutes: 300, observedAt: at(2))
    ])
}

@Test func quotaReadingsWithoutAnAccountAreSkipped() {
    let lines = [
        sessionMeta(account: nil), taskStarted(1, "turn-1"), turnContext(1), userPrompt(2),
        assistantReply(3), tokenCount(4, output: 12, reasoning: 0, rateLimits: rateLimitsWithID)
    ]
    let output = parse(lines)

    #expect(output.quotaReadings.isEmpty)
    #expect(output.responses.map(\.outputTokens) == [12])
}

@Test func malformedLinesAreSkipped() {
    let lines = [
        sessionMeta(account: "account-1"), "not json", taskStarted(1, "turn-1"), turnContext(1), "[1,2]",
        userPrompt(2), #"{"type":"response_item","payload":{"type":"reasoning"}}"#,
        assistantReply(3), #"{"timestamp":"yesterday","type":"event_msg","payload":{"type":"task_complete"}}"#,
        usageRecord(4, output: 9, reasoning: 1)
    ]
    let output = parse(lines)

    #expect(output.responses.count == 1)
    #expect(output.responses[0].turnID == "turn-1")
    #expect(output.responses[0].outputTokens == 9)
}

@Test func resumingReemitsTheLastResponseComplete() throws {
    let lines = [
        sessionMeta(account: "account-1"),
        taskStarted(1, "turn-1"), turnContext(1), userPrompt(2), assistantReply(3),
        usageRecord(4, output: 10, reasoning: 0), taskComplete(5),
        taskStarted(6, "turn-2"), turnContext(6, model: "gpt-6-astra"), userPrompt(7),
        toolCall(8), usageRecord(9, output: 25, reasoning: 5),
        commandCompleted(10, item: "item_9", "rg needle", exitCode: 0),
        commandCompleted(11, item: "item_9", "wc -l", exitCode: 0),
        toolResult(12), reasoning(13), assistantReply(14),
        // Written after the first read.
        usageRecord(15, output: 70, reasoning: 40),
        tokenCount(15, rateLimits: #"{"primary":{"used_percent":8,"window_minutes":300}}"#), taskComplete(16)
    ]
    let growing = Array(lines[..<17])
    let firstRead = parse(growing)
    let turnTwoStart = offsets(lines)[7]
    #expect(firstRead.resumeByteOffset == turnTwoStart)
    #expect(firstRead.responses.last?.outputTokens == nil)

    let resumed = parse(lines, from: firstRead.resumeByteOffset)
    let complete = parse(lines)

    #expect(resumed.responses == Array(complete.responses.suffix(2)))
    #expect(resumed.commands == complete.commands)
    #expect(resumed.quotaReadings == complete.quotaReadings)
    let last = try #require(resumed.responses.last)
    #expect(last.responseID == firstRead.responses.last?.responseID)
    #expect(last.turnID == "turn-2")
    #expect(last.model == "gpt-6-astra")
    #expect(last.projectKey == projectKey)
    #expect(last.requestedAt == at(12))
    #expect(last.outputTokens == 70)
    #expect(last.thinkingTokens == 40)
    #expect(resumed.commands.map(\.commandID) == ["item_9:0", "item_9:1"])
    #expect(resumed.resumeByteOffset == turnTwoStart)
}
