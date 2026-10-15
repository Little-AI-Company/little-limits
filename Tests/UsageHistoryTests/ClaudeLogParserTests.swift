import Foundation
import Testing
import UsageHistory

private let salt: [UInt8] = Array(0..<16)
private let cwd = "/Users/a/clients/acme/web"

// Synthetic log lines. Every prompt, reply, and command below is invented.

private func prompt(_ uuid: String, at time: String, cwd: String = cwd) -> String {
    #"{"type":"user","uuid":"\#(uuid)","timestamp":"2026-06-09T\#(time)Z","sessionId":"s1","cwd":"\#(cwd)","message":{"role":"user","content":"synthetic prompt"}}"#
}

private func toolResult(_ toolUseID: String, at time: String, isError: Bool? = nil) -> String {
    let flag = isError.map { #","is_error":\#($0)"# } ?? ""
    return #"{"type":"user","uuid":"r-\#(toolUseID)","timestamp":"2026-06-09T\#(time)Z","sessionId":"s1","cwd":"\#(cwd)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"\#(toolUseID)","content":"synthetic output"\#(flag)}]}}"#
}

private func assistant(_ id: String, at time: String, block: String, outputTokens: Int, thinkingTokens: Int? = nil,
                       stopReason: String? = nil, cwd: String = cwd) -> String {
    let stop = stopReason.map { #""\#($0)""# } ?? "null"
    let details = thinkingTokens.map { #","output_tokens_details":{"thinking_tokens":\#($0)}"# } ?? ""
    return #"{"type":"assistant","uuid":"a-\#(id)-\#(time)","timestamp":"2026-06-09T\#(time)Z","sessionId":"s1","cwd":"\#(cwd)","message":{"id":"\#(id)","type":"message","role":"assistant","model":"claude-test-1","content":[\#(block)],"stop_reason":\#(stop),"usage":{"input_tokens":3,"output_tokens":\#(outputTokens)\#(details)}}}"#
}

private let thinkingBlock = #"{"type":"thinking","thinking":"synthetic"}"#
private let textBlock = #"{"type":"text","text":"synthetic reply"}"#

private func bash(_ id: String, _ command: String) -> String {
    #"{"type":"tool_use","id":"\#(id)","name":"Bash","input":{"command":"\#(command)","description":"synthetic"}}"#
}

private func read(_ id: String) -> String {
    #"{"type":"tool_use","id":"\#(id)","name":"Read","input":{"file_path":"/tmp/synthetic.txt"}}"#
}

private func date(_ time: String) -> Date {
    try! Date("2026-06-09T\(time)Z", strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
}

/// Feeds newline-terminated lines starting at `startOffset`, as an ingestor reading a file would, and returns each
/// line's absolute offset.
@discardableResult
private func feed(_ lines: [String], into parser: inout ClaudeLogParser, from startOffset: Int64 = 0) -> [Int64] {
    var offset = startOffset
    var offsets: [Int64] = []
    for line in lines {
        let data = Data((line + "\n").utf8)
        parser.consume(line: data, at: offset)
        offsets.append(offset)
        offset += Int64(data.count)
    }
    return offsets
}

private func parse(_ lines: [String]) -> LogParseOutput {
    var parser = ClaudeLogParser(filePath: "/synthetic/s1.jsonl", projectKeySalt: salt)
    feed(lines, into: &parser)
    return parser.finish()
}

@Test func splitContentBlocksFormOneResponseWithTheLargestOutputTokens() throws {
    let output = parse([
        prompt("p1", at: "12:00:00.000"),
        assistant("msg_A", at: "12:00:02.000", block: thinkingBlock, outputTokens: 5),
        assistant("msg_A", at: "12:00:04.000", block: textBlock, outputTokens: 12),
        assistant("msg_A", at: "12:00:05.500", block: textBlock, outputTokens: 40, thinkingTokens: 25,
                  stopReason: "end_turn")
    ])

    let response = try #require(output.responses.first)
    #expect(output.responses.count == 1)
    #expect(response.provider == .claude)
    #expect(response.responseID == "msg_A")
    #expect(response.sessionID == "s1")
    #expect(response.turnID == "p1")
    #expect(response.model == "claude-test-1")
    #expect(response.projectKey == ProjectKey.make(workingDirectory: cwd, salt: salt))
    #expect(response.requestedAt == Date(timeIntervalSince1970: 1_781_006_400))
    #expect(response.completedAt == date("12:00:05.500"))
    #expect(response.outputTokens == 40)
    #expect(response.thinkingTokens == 25)
    #expect(response.toolCallCount == 0)
    #expect(!response.hasParallelToolCalls)
}

@Test func responseWithoutFinalUsageLineHasUnknownTokens() throws {
    let output = parse([
        prompt("p1", at: "12:00:00.000"),
        assistant("msg_A", at: "12:00:02.000", block: thinkingBlock, outputTokens: 5, thinkingTokens: 4),
        assistant("msg_A", at: "12:00:03.000", block: textBlock, outputTokens: 9)
    ])

    let response = try #require(output.responses.first)
    #expect(response.outputTokens == nil)
    #expect(response.thinkingTokens == nil)
    #expect(response.completedAt == date("12:00:03.000"))
}

@Test func parallelToolCallsAndTurnsSpanToolResults() throws {
    let output = parse([
        prompt("p1", at: "12:00:00.000"),
        assistant("msg_A", at: "12:00:01.000", block: bash("toolu_1", "ls"), outputTokens: 20),
        assistant("msg_A", at: "12:00:02.000", block: read("toolu_2"), outputTokens: 30, stopReason: "tool_use"),
        toolResult("toolu_1", at: "12:00:03.000"),
        toolResult("toolu_2", at: "12:00:04.000"),
        assistant("msg_B", at: "12:00:06.000", block: read("toolu_3"), outputTokens: 8, stopReason: "tool_use"),
        toolResult("toolu_3", at: "12:00:07.000"),
        assistant("msg_C", at: "12:00:09.000", block: textBlock, outputTokens: 15, stopReason: "end_turn"),
        prompt("p2", at: "12:01:00.000"),
        assistant("msg_D", at: "12:01:02.000", block: textBlock, outputTokens: 4, stopReason: "end_turn")
    ])

    let byID = Dictionary(uniqueKeysWithValues: output.responses.map { ($0.responseID, $0) })
    #expect(output.responses.map(\.responseID) == ["msg_A", "msg_B", "msg_C", "msg_D"])
    #expect(byID["msg_A"]?.toolCallCount == 2)
    #expect(byID["msg_A"]?.hasParallelToolCalls == true)
    #expect(byID["msg_B"]?.toolCallCount == 1)
    #expect(byID["msg_B"]?.hasParallelToolCalls == false)
    #expect(byID["msg_B"]?.requestedAt == date("12:00:04.000"))
    #expect(byID["msg_C"]?.requestedAt == date("12:00:07.000"))
    #expect(["msg_A", "msg_B", "msg_C"].map { byID[$0]?.turnID } == ["p1", "p1", "p1"])
    #expect(byID["msg_D"]?.turnID == "p2")
}

@Test func bashCommandsTakeSuccessFromTheMatchingToolResult() {
    let output = parse([
        prompt("p1", at: "12:00:00.000"),
        assistant("msg_A", at: "12:00:01.000", block: bash("toolu_ok", "echo synthetic"), outputTokens: 10),
        assistant("msg_A", at: "12:00:02.000", block: bash("toolu_fail", "false"), outputTokens: 20),
        assistant("msg_A", at: "12:00:03.000", block: bash("toolu_plain", "true"), outputTokens: 30),
        assistant("msg_A", at: "12:00:04.000", block: bash("toolu_pending", "sleep 1"), outputTokens: 40,
                  stopReason: "tool_use"),
        toolResult("toolu_ok", at: "12:00:05.000", isError: false),
        toolResult("toolu_fail", at: "12:00:06.000", isError: true),
        toolResult("toolu_plain", at: "12:00:07.000")
    ])

    let byID = Dictionary(uniqueKeysWithValues: output.commands.map { ($0.commandID, $0) })
    #expect(output.commands.map(\.commandID) == ["toolu_ok", "toolu_fail", "toolu_plain", "toolu_pending"])
    #expect(byID["toolu_ok"]?.succeeded == true)
    #expect(byID["toolu_fail"]?.succeeded == false)
    #expect(byID["toolu_plain"]?.succeeded == true)
    #expect(byID["toolu_pending"]?.succeeded == nil)

    let command = byID["toolu_fail"]
    #expect(command?.provider == .claude)
    #expect(command?.command == "false")
    #expect(command?.responseID == "msg_A")
    #expect(command?.sessionID == "s1")
    #expect(command?.model == "claude-test-1")
    #expect(command?.projectKey == ProjectKey.make(workingDirectory: cwd, salt: salt))
    #expect(command?.executedAt == date("12:00:02.000"))
}

@Test func resumingReemitsTheLastResponseComplete() throws {
    let written = [
        prompt("p1", at: "12:00:00.000"),
        assistant("msg_A", at: "12:00:01.000", block: textBlock, outputTokens: 6, stopReason: "end_turn"),
        prompt("p2", at: "12:01:00.000"),
        assistant("msg_B", at: "12:01:01.000", block: bash("toolu_1", "ls"), outputTokens: 9, stopReason: "tool_use"),
        toolResult("toolu_1", at: "12:01:02.000", isError: false),
        assistant("msg_C", at: "12:01:04.000", block: thinkingBlock, outputTokens: 3)
    ]
    let appended = [
        assistant("msg_C", at: "12:01:05.000", block: bash("toolu_2", "pwd"), outputTokens: 7),
        assistant("msg_C", at: "12:01:06.000", block: read("toolu_3"), outputTokens: 50, thinkingTokens: 12,
                  stopReason: "tool_use"),
        toolResult("toolu_2", at: "12:01:07.000", isError: true)
    ]

    var first = ClaudeLogParser(filePath: "/synthetic/s1.jsonl", projectKeySalt: salt)
    let offsets = feed(written, into: &first)
    let firstOutput = first.finish()
    #expect(firstOutput.responses.last?.outputTokens == nil)
    // The last turn starts at prompt p2, before msg_C's first line.
    #expect(firstOutput.resumeByteOffset == offsets[2])
    #expect(firstOutput.resumeByteOffset <= offsets[5])

    let resumeIndex = try #require(offsets.firstIndex(of: firstOutput.resumeByteOffset))
    var second = ClaudeLogParser(filePath: "/synthetic/s1.jsonl", projectKeySalt: salt)
    feed(Array(written[resumeIndex...]) + appended, into: &second, from: firstOutput.resumeByteOffset)
    let resumed = second.finish()

    let whole = parse(written + appended)
    let complete = try #require(whole.responses.last)
    #expect(resumed.responses.last == complete)
    #expect(complete.responseID == "msg_C")
    #expect(complete.turnID == "p2")
    #expect(complete.requestedAt == date("12:01:02.000"))
    #expect(complete.completedAt == date("12:01:06.000"))
    #expect(complete.outputTokens == 50)
    #expect(complete.thinkingTokens == 12)
    #expect(complete.toolCallCount == 2)
    #expect(resumed.responses.map(\.responseID) == ["msg_B", "msg_C"])
    #expect(resumed.commands == whole.commands)
    #expect(resumed.commands.map(\.succeeded) == [true, false])
}

@Test func sameNamedFoldersInDifferentPathsGetDifferentProjectKeys() {
    let output = parse([
        prompt("p1", at: "12:00:00.000", cwd: "/Users/a/clients/acme/web"),
        assistant("msg_A", at: "12:00:01.000", block: bash("toolu_1", "ls"), outputTokens: 5,
                  stopReason: "end_turn", cwd: "/Users/a/clients/acme/web"),
        prompt("p2", at: "12:01:00.000", cwd: "/Users/a/personal/web"),
        assistant("msg_B", at: "12:01:01.000", block: bash("toolu_2", "ls"), outputTokens: 5,
                  stopReason: "end_turn", cwd: "/Users/a/personal/web")
    ])

    let keys = output.responses.map(\.projectKey)
    #expect(keys == [ProjectKey.make(workingDirectory: "/Users/a/clients/acme/web", salt: salt),
                     ProjectKey.make(workingDirectory: "/Users/a/personal/web", salt: salt)])
    #expect(keys[0] != keys[1])
    #expect(output.commands.map(\.projectKey) == keys)
}

@Test func otherLineTypesAndMalformedLinesAreSkipped() throws {
    let lines = [
        #"{"type":"summary","summary":"synthetic","leafUuid":"x"}"#,
        #"{"type":"assistant","timestamp":"2026-06-09T12:00:00.000Z","message":"#,
        "not json",
        #"{"type":"assistant","uuid":"e","timestamp":"2026-06-09T12:00:00.500Z","sessionId":"s1","message":{"id":"err","model":"<synthetic>","content":[],"stop_reason":"stop_sequence","usage":{"output_tokens":0}}}"#,
        prompt("p1", at: "12:00:01.000"),
        assistant("msg_A", at: "12:00:02.000", block: textBlock, outputTokens: 7, stopReason: "end_turn")
    ]
    let output = parse(lines)
    #expect(output.responses.map(\.responseID) == ["msg_A"])
    #expect(output.responses.first?.outputTokens == 7)

    let empty = parse(Array(lines.prefix(4)))
    let endOfInput = lines.prefix(4).reduce(0) { $0 + Int64($1.utf8.count + 1) }
    #expect(empty.responses.isEmpty)
    #expect(empty.resumeByteOffset == endOfInput)
}
