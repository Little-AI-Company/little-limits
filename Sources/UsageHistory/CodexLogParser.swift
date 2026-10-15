import Foundation

/// Parses one Codex rollout log, `rollout-<time>-<conversation id>.jsonl` or its `.jsonl.zst` form, one line at a time.
///
/// A line is `{"timestamp", "type", "payload"}`. Events appear either as their own `type` or as `event_msg` with the
/// event name in `payload.type`. Lines that are not JSON objects with a type and an ISO 8601 timestamp are skipped.
///
/// A response is the run of assistant output after a prompt or tool result: reasoning, messages, and tool call
/// response items, or completed `AgentMessage` and `Reasoning` items, which older subagent logs write instead. Its
/// usage line can follow its tool results. Its identifier is the conversation id and the offset of its first output
/// line, so a moved, compressed, or resumed file produces the same identifiers. A shell command belongs to the
/// response that was active when it started. A response and its commands are emitted only when the turn's model is
/// known.
///
/// Resuming: the model and turn id are written once per turn, so `resumeByteOffset` is the first line of the last
/// response's turn, or the turn's prompt when that comes first, at or before the response's first line. The next read
/// emits every response of that turn again, complete, with the same identifiers. A read without a response resumes
/// at its open turn, or after its last line.
///
/// The account and working directory are written once per file, in its first line (`session_meta`). A read that
/// starts after offset 0 must first pass the file's first line, then the lines from `resumeByteOffset`; otherwise its
/// quota readings have no account and are skipped. When no complete line follows `resumeByteOffset`, keep the
/// previous offset instead of parsing the first line alone.
public struct CodexLogParser: Sendable {
    private enum UsageSource: Sendable {
        case tokenCount
        case tokenUsageRecord
    }

    private struct CommandDraft: Sendable {
        let itemID: String
        let executedAt: Date
        let succeeded: Bool?
        let command: String
    }

    private struct ResponseDraft: Sendable {
        let responseID: String
        let resumeOffset: Int64
        let turnID: String
        let model: String?
        let projectKey: String?
        let requestedAt: Date?
        /// The time of the first output line.
        let startedAt: Date
        var completedAt: Date
        var outputTokens: Int?
        var thinkingTokens: Int?
        var usageSource: UsageSource?
        var toolCallCount = 0
        var commands: [CommandDraft] = []
    }

    private let sessionID: String
    private let projectKeySalt: [UInt8]

    /// Forked sessions copy the parent's `session_meta` later in the file; only the first one describes this file.
    private var hasReadSessionMeta = false
    private var providerAccountID: String?
    private var projectKey: String?
    private var model: String?
    private var turnID: String?
    /// The current turn's first line, moved back to the earliest prompt or tool result that one of its responses
    /// answers. A prompt that interrupts the previous turn comes before the next turn's first line.
    private var turnResumeOffset: Int64?
    private var isInTask = false
    /// A `turn_context` outside a task started the current turn and no output has followed it yet.
    private var isTurnStartedByContext = false

    private var responses: [ResponseDraft] = []
    private var quotaReadings: [LogQuotaReading] = []
    /// Output items extend the last response until a prompt, tool result, turn change, or usage line ends it.
    private var acceptsOutput = false
    /// Usage lines apply to the last response until the turn changes.
    private var acceptsUsage = false
    /// The prompt or tool result that the next response answers.
    private var lastInput: (offset: Int64, timestamp: Date)?
    /// The offset after the last line read.
    private var endOffset: Int64 = 0

    public init(filePath: String, projectKeySalt: [UInt8]) {
        sessionID = Self.sessionID(filePath: filePath)
        self.projectKeySalt = projectKeySalt
    }

    public mutating func consume(line: Data, at byteOffset: Int64) {
        endOffset = max(endOffset, byteOffset + Int64(line.count) + 1)
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = object["type"] as? String,
              let timestamp = (object["timestamp"] as? String).flatMap(Self.date) else { return }
        let payload = object["payload"] as? [String: Any] ?? [:]
        switch type {
        case "session_meta":
            guard !hasReadSessionMeta else { return }
            hasReadSessionMeta = true
            providerAccountID = payload["creator_account_id"] as? String
            if let cwd = payload["cwd"] as? String { setWorkingDirectory(cwd) }
        case "turn_context":
            if !isInTask && !isTurnStartedByContext {
                turnResumeOffset = byteOffset
                isTurnStartedByContext = true
            }
            model = payload["model"] as? String
            if let cwd = payload["cwd"] as? String { setWorkingDirectory(cwd) }
            endResponse()
        case "response_item":
            readResponseItem(payload, at: byteOffset, timestamp: timestamp)
        case "event_msg":
            readEvent(payload["type"] as? String, payload, at: byteOffset, timestamp: timestamp)
        default:
            readEvent(type, payload, at: byteOffset, timestamp: timestamp)
        }
    }

    public func finish() -> LogParseOutput {
        // Without a response, an open turn may still produce one; otherwise the read resumes after its last line.
        let isTurnOpen = isInTask || isTurnStartedByContext
        let pendingTurnOffset = isTurnOpen ? [turnResumeOffset, lastInput?.offset].compactMap { $0 }.min() : nil
        let resumeOffset = responses.last?.resumeOffset ?? pendingTurnOffset ?? endOffset
        var output = LogParseOutput(quotaReadings: quotaReadings, resumeByteOffset: resumeOffset)
        for draft in responses {
            guard let model = draft.model else { continue }
            output.responses.append(ModelResponse(
                provider: .codex, responseID: draft.responseID, sessionID: sessionID, turnID: draft.turnID,
                model: model, projectKey: draft.projectKey, requestedAt: draft.requestedAt,
                completedAt: draft.completedAt, outputTokens: draft.outputTokens, thinkingTokens: draft.thinkingTokens,
                toolCallCount: draft.toolCallCount,
                hasParallelToolCalls: draft.toolCallCount >= 2 || draft.commands.count >= 2))
            output.commands += draft.commands.map { command in
                ShellCommandEvent(provider: .codex, commandID: "\(sessionID):\(command.itemID)",
                                  responseID: draft.responseID, sessionID: sessionID, model: model,
                                  projectKey: draft.projectKey, executedAt: command.executedAt,
                                  succeeded: command.succeeded, command: command.command)
            }
        }
        return output
    }

    private mutating func readResponseItem(_ payload: [String: Any], at byteOffset: Int64, timestamp: Date) {
        switch payload["type"] as? String {
        case "message":
            switch payload["role"] as? String {
            case "assistant": addOutput(at: byteOffset, timestamp: timestamp, isToolCall: false)
            case "user": receiveInput(at: byteOffset, timestamp: timestamp)
            default: break
            }
        case "reasoning":
            addOutput(at: byteOffset, timestamp: timestamp, isToolCall: false)
        case "function_call", "custom_tool_call", "local_shell_call", "web_search_call", "tool_search_call",
             "image_generation_call":
            addOutput(at: byteOffset, timestamp: timestamp, isToolCall: true)
        case "function_call_output", "custom_tool_call_output", "tool_search_output":
            receiveInput(at: byteOffset, timestamp: timestamp)
        case "agent_message":
            // A message from another agent in a multi-agent session. It can arrive while a response streams, so it
            // is input for the next response without ending the current one.
            lastInput = (byteOffset, timestamp)
        default:
            break
        }
    }

    private mutating func readEvent(_ event: String?, _ payload: [String: Any], at byteOffset: Int64, timestamp: Date) {
        switch event {
        case "task_started":
            if isInTask || !isTurnStartedByContext {
                turnResumeOffset = byteOffset
            }
            isTurnStartedByContext = false
            isInTask = true
            turnID = payload["turn_id"] as? String ?? "\(sessionID):\(byteOffset)"
            endResponse()
        case "task_complete", "turn_aborted":
            isInTask = false
            isTurnStartedByContext = false
            turnID = nil
            endResponse()
        case "user_message":
            receiveInput(at: byteOffset, timestamp: timestamp)
        case "token_usage_record":
            readUsage(payload["usage"] as? [String: Any], source: .tokenUsageRecord, timestamp: timestamp)
        case "token_count":
            let info = payload["info"] as? [String: Any]
            readUsage(info?["last_token_usage"] as? [String: Any], source: .tokenCount, timestamp: timestamp)
            readRateLimits(payload["rate_limits"] as? [String: Any], observedAt: timestamp)
        case "item_completed":
            readCompletedItem(payload["item"] as? [String: Any], at: byteOffset, timestamp: timestamp)
        default:
            break
        }
    }

    private mutating func addOutput(at byteOffset: Int64, timestamp: Date, isToolCall: Bool) {
        if !acceptsOutput {
            let responseID = "\(sessionID):\(byteOffset)"
            let resumeOffset = min(turnResumeOffset ?? byteOffset, lastInput?.offset ?? byteOffset)
            if turnResumeOffset != nil { turnResumeOffset = resumeOffset }
            responses.append(ResponseDraft(responseID: responseID, resumeOffset: resumeOffset,
                                           turnID: turnID ?? responseID, model: model, projectKey: projectKey,
                                           requestedAt: lastInput?.timestamp, startedAt: timestamp,
                                           completedAt: timestamp))
            lastInput = nil
            acceptsOutput = true
        }
        acceptsUsage = true
        isTurnStartedByContext = false
        responses[responses.count - 1].completedAt = timestamp
        if isToolCall { responses[responses.count - 1].toolCallCount += 1 }
    }

    /// A usage line can follow the response's tool results, so it applies to the last response until that response
    /// has usage or the turn changes. Newer logs write `token_usage_record` and may also write `token_count`; the
    /// record wins. A repeated `token_count` is ignored.
    private mutating func readUsage(_ usage: [String: Any]?, source: UsageSource, timestamp: Date) {
        guard let usage, acceptsUsage, let index = responses.indices.last else { return }
        switch (responses[index].usageSource, source) {
        case (nil, _), (.tokenCount, .tokenUsageRecord): break
        default: return
        }
        responses[index].outputTokens = Self.integer(usage["output_tokens"])
        responses[index].thinkingTokens = Self.integer(usage["reasoning_output_tokens"])
        responses[index].usageSource = source
        responses[index].completedAt = timestamp
        acceptsOutput = false
    }

    /// A completed command is not model input: its tool result follows as a response item.
    private mutating func readCompletedItem(_ item: [String: Any]?, at byteOffset: Int64, timestamp: Date) {
        switch item?["type"] as? String {
        case "AgentMessage", "Reasoning": addOutput(at: byteOffset, timestamp: timestamp, isToolCall: false)
        default: break
        }
        // A command the user runs with `/shell` is not a model command.
        guard let item, item["source"] as? String != "user_shell", let command = Self.commandText(item["command"]),
              let itemID = item["id"] as? String, let index = commandOwnerIndex(item, completedAt: timestamp)
        else { return }
        responses[index].commands.append(CommandDraft(itemID: itemID, executedAt: timestamp,
                                                      succeeded: Self.integer(item["exit_code"]).map { $0 == 0 },
                                                      command: command))
    }

    /// A command belongs to the response that was active when it started, even when it completes after a later
    /// response or turn has started. Without a duration, it belongs to the last response. On a resumed read, a
    /// command can start before any response of the read; it was emitted earlier.
    ///
    /// The start is the completion time minus the duration, so it is compared with log line timestamps, which Codex
    /// writes when it saves a line, not when the event happens. A tool-call-only response's first line can carry the
    /// same millisecond as the command it starts, or a slightly later one. Ordering by file position is not
    /// possible: the logs have no command start line. So a response that starts up to `commandStartTolerance` after
    /// the command still owns it. A later response cannot start that soon: it waits for the tool result and the
    /// model's first output.
    private func commandOwnerIndex(_ item: [String: Any], completedAt: Date) -> Int? {
        guard let duration = item["duration"] as? [String: Any],
              let seconds = Self.number(duration["secs"]) else { return responses.indices.last }
        let startedAt = completedAt.addingTimeInterval(-(seconds + (Self.number(duration["nanos"]) ?? 0) / 1e9))
        return responses.lastIndex { $0.startedAt <= startedAt.addingTimeInterval(Self.commandStartTolerance) }
    }

    private static let commandStartTolerance: TimeInterval = 1

    /// Codex writes `command` as an argument list, `[zsh, -lc, script]` for a shell script. A shell script gives the
    /// script; other lists join their arguments with spaces. A plain string is used as it is.
    private static func commandText(_ value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let arguments = value as? [String], !arguments.isEmpty else { return nil }
        let shell = arguments[0].split(separator: "/").last.map(String.init)
        if arguments.count == 3, let shell, ["bash", "sh", "zsh"].contains(shell),
           ["-c", "-lc"].contains(arguments[1]) {
            return arguments[2]
        }
        return arguments.joined(separator: " ")
    }

    /// Window identifiers match `CodexClient`: `<limit id>_primary`, with `codex` when the log has no limit id.
    private mutating func readRateLimits(_ rateLimits: [String: Any]?, observedAt: Date) {
        guard let rateLimits, let providerAccountID else { return }
        let limitID = rateLimits["limit_id"] as? String ?? "codex"
        for position in ["primary", "secondary"] {
            guard let window = rateLimits[position] as? [String: Any],
                  let usedPercent = Self.number(window["used_percent"]) else { continue }
            quotaReadings.append(LogQuotaReading(
                providerAccountID: providerAccountID, windowID: limitID + "_" + position, usedPercent: usedPercent,
                resetsAt: Self.number(window["resets_at"]).map(Date.init(timeIntervalSince1970:)),
                windowDurationMinutes: Self.integer(window["window_minutes"]), observedAt: observedAt))
        }
    }

    private mutating func receiveInput(at byteOffset: Int64, timestamp: Date) {
        lastInput = (byteOffset, timestamp)
        acceptsOutput = false
    }

    private mutating func endResponse() {
        acceptsOutput = false
        acceptsUsage = false
    }

    private mutating func setWorkingDirectory(_ path: String) {
        projectKey = ProjectKey.make(workingDirectory: path, salt: projectKeySalt)
    }

    /// The conversation UUID in `rollout-<time>-<conversation id>.jsonl`, which stays the same when Codex moves or
    /// compresses the file. A reverted thread's file, `rollout-<time>-<conversation id>_<rollout id>.jsonl`, keeps
    /// the conversation id.
    private static func sessionID(filePath: String) -> String {
        var name = filePath.split(separator: "/").last ?? Substring(filePath)
        for suffix in [".zst", ".jsonl"] where name.hasSuffix(suffix) { name = name.dropLast(suffix.count) }
        if let separator = name.lastIndex(of: "_"),
           UUID(uuidString: String(name[name.index(after: separator)...])) != nil {
            name = name[..<separator]
        }
        let identifier = String(name.suffix(36))
        return UUID(uuidString: identifier) == nil ? String(name) : identifier
    }

    private static func date(_ text: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(text))
            ?? (try? Date.ISO8601FormatStyle().parse(text))
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func integer(_ value: Any?) -> Int? {
        (value as? NSNumber).flatMap { Int(exactly: $0.doubleValue) }
    }
}
