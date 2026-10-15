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

/// Codex writes a command as an argument list; `script` becomes `["/bin/zsh", "-lc", script]`.
private func commandCompleted(_ second: Int, item: String, _ script: String, exitCode: Int) -> String {
    commandCompleted(second, item: item, arguments: #"["/bin/zsh","-lc","\#(script)"]"#, exitCode: exitCode)
}

private func commandCompleted(_ second: Int, item: String, arguments: String, exitCode: Int = 0) -> String {
    let item = #"{"id":"\#(item)","type":"CommandExecution","command":\#(arguments),"exit_code":\#(exitCode)}"#
    return event(second, #"{"type":"item_completed","item":\#(item)}"#)
}

private func completedItem(_ second: Int, _ type: String) -> String {
    event(second, #"{"type":"item_completed","item":{"id":"item","type":"\#(type)"}}"#)
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
        commandCompleted(6, item: "exec-1", "rg TODO src", exitCode: 0),
        commandCompleted(7, item: "exec-2", "git status", exitCode: 1),
        toolResult(8),
        // A command can complete before its response's usage line.
        toolCall(9), commandCompleted(10, item: "exec-3", "ls", exitCode: 0),
        usageRecord(11, output: 20, reasoning: 0), toolResult(12),
        toolCall(13, "shell"), toolCall(13, "shell"), usageRecord(14, output: 20, reasoning: 0),
        toolResult(15), toolResult(15),
        assistantReply(16), usageRecord(17, output: 5, reasoning: 0), taskComplete(18)
    ]
    let output = parse(lines)

    #expect(output.responses.map(\.toolCallCount) == [1, 1, 2, 0])
    #expect(output.responses.map(\.hasParallelToolCalls) == [true, false, true, false])
    #expect(output.responses.map(\.outputTokens) == [40, 20, 20, 5])
    #expect(output.responses[1].requestedAt == at(8))
    #expect(output.responses[2].requestedAt == at(12))
    #expect(output.commands.map(\.commandID) == ["exec-1", "exec-2", "exec-3"].map { "\(sessionID):\($0)" })
    #expect(output.commands.map(\.command) == ["rg TODO src", "git status", "ls"])
    #expect(output.commands.map(\.succeeded) == [true, false, true])
    #expect(output.commands.map(\.executedAt) == [at(6), at(7), at(10)])
    let responseIDs = output.responses.map(\.responseID)
    #expect(output.commands.map(\.responseID) == [responseIDs[0], responseIDs[0], responseIDs[1]])
    #expect(output.commands.allSatisfy { $0.model == "gpt-6.1-sol" && $0.projectKey == projectKey })
}

@Test func commandTextComesFromTheShellScriptOrTheJoinedArguments() {
    let lines = [
        sessionMeta(account: "account-1"), taskStarted(1, "turn-1"), turnContext(1), userPrompt(2), toolCall(3),
        commandCompleted(4, item: "exec-1", arguments: #"["zsh","-c","rg -n needle | head -5"]"#),
        commandCompleted(4, item: "exec-2", arguments: #"["/bin/bash","-lc","git status"]"#),
        commandCompleted(4, item: "exec-3", arguments: #"["git","log","-1"]"#),
        commandCompleted(4, item: "exec-4", arguments: #"["/usr/bin/python3","-c","print(1)"]"#),
        commandCompleted(4, item: "exec-5", arguments: #""ls -la""#),
        commandCompleted(4, item: "exec-6", arguments: "[]")
    ]

    #expect(parse(lines).commands.map(\.command)
        == ["rg -n needle | head -5", "git status", "git log -1", "/usr/bin/python3 -c print(1)", "ls -la"])
}

@Test func revertedThreadFileUsesTheConversationID() {
    let rolloutID = "0199e2a1-0000-7000-8000-000000000001"
    var parser = CodexLogParser(filePath: "/logs/rollout-2026-10-14T10-00-00-\(sessionID)_\(rolloutID).jsonl.zst",
                                projectKeySalt: salt)
    for (line, offset) in zip([turnContext(1), userPrompt(2), assistantReply(3)], [Int64(0), 100, 200]) {
        parser.consume(line: Data(line.utf8), at: offset)
    }

    #expect(parser.finish().responses.map(\.responseID) == ["\(sessionID):200"])
}

/// Older subagent logs keep only the final reply as a response item. Each earlier response is a completed
/// `AgentMessage` or `Reasoning` item followed by `token_count`, and usage can follow a tool result.
@Test func olderSubagentLogsGiveOneResponsePerUsageLine() {
    let lines = [
        sessionMeta(account: "account-1"), taskStarted(1, "turn-1"), turnContext(1, model: "gpt-5.5"), userPrompt(2),
        completedItem(3, "AgentMessage"), tokenCount(4, output: 11, reasoning: 1),
        completedItem(5, "Reasoning"), completedItem(5, "AgentMessage"), completedItem(5, "FileChange"),
        tokenCount(6, output: 12, reasoning: 2), tokenCount(6, output: 12, reasoning: 2),
        entry(7, "response_item", #"{"type":"function_call","name":"exec_command","arguments":"{}","call_id":"c"}"#),
        entry(8, "response_item", #"{"type":"function_call_output","call_id":"c","output":"x"}"#),
        tokenCount(9, output: 13, reasoning: 3),
        assistantReply(10), tokenCount(11, output: 14, reasoning: 4), taskComplete(12)
    ]
    let output = parse(lines)

    #expect(output.responses.map(\.outputTokens) == [11, 12, 13, 14])
    #expect(output.responses.map(\.toolCallCount) == [0, 0, 1, 0])
    #expect(output.responses.allSatisfy { $0.model == "gpt-5.5" })
}

/// A forked session copies its parent's `session_meta` later in the file.
@Test func onlyTheFirstSessionMetaSetsTheAccount() {
    let lines = [
        sessionMeta(account: "account-1"),
        entry(1, "session_meta", #"{"id":"parent","cwd":"/work/other"}"#),
        tokenCount(2, rateLimits: #"{"primary":{"used_percent":3,"window_minutes":300}}"#),
        taskStarted(3, "turn-1"), entry(3, "turn_context", #"{"model":"gpt-6.1-sol"}"#), userPrompt(4),
        assistantReply(5)
    ]
    let output = parse(lines)

    #expect(output.quotaReadings.map(\.providerAccountID) == ["account-1"])
    #expect(output.responses.map(\.projectKey) == [projectKey])
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
        commandCompleted(10, item: "exec-1", "rg needle", exitCode: 0),
        commandCompleted(11, item: "exec-2", "wc -l", exitCode: 0),
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
    #expect(resumed.commands.map(\.commandID) == ["\(sessionID):exec-1", "\(sessionID):exec-2"])
    #expect(resumed.resumeByteOffset == turnTwoStart)
}

/// A prompt that interrupts a turn is written before the next turn starts, so the resume offset moves back to it.
@Test func resumingKeepsAPromptWrittenBeforeTheTurnStart() {
    let lines = [
        sessionMeta(account: "account-1"),
        taskStarted(1, "turn-1"), turnContext(1), userPrompt(2), assistantReply(3),
        usageRecord(4, output: 10, reasoning: 0), userPrompt(5), event(6, #"{"type":"turn_aborted","turn_id":"turn-1"}"#),
        taskStarted(7, "turn-2"), turnContext(7), reasoning(8), usageRecord(9, output: 20, reasoning: 5),
        toolCall(10), usageRecord(11, output: 30, reasoning: 5)
    ]
    let full = parse(lines)
    let resumed = parse(lines, from: full.resumeByteOffset)

    #expect(full.resumeByteOffset == offsets(lines)[6])
    #expect(full.responses.map(\.requestedAt) == [at(2), at(5), nil])
    #expect(resumed.responses == Array(full.responses.suffix(2)))
}
