import Foundation

/// Parses one Codex rollout log, `rollout-<time>-<session id>.jsonl` or its `.jsonl.zst` form, one line at a time.
///
/// A line is `{"timestamp", "type", "payload"}`. Events appear either as their own `type` or as `event_msg` with the
/// event name in `payload.type`. Lines that are not JSON objects with a type and an ISO 8601 timestamp are skipped.
///
/// A response is the run of assistant output items (reasoning, messages, tool calls) after a prompt or tool result,
/// ending with its usage line. Its identifier is the session id and the offset of its first output line, so a moved,
/// compressed, or resumed file produces the same identifiers. Shell commands that complete after a response belong
/// to it. A response is emitted only when the turn's model is known.
///
/// Resuming: the model and turn id are written once per turn, so `resumeByteOffset` is the first line of the last
/// response's turn, at or before the response's first line. The next read emits every response of that turn again,
/// complete, with the same identifiers. The account and working directory are written once per file, in the first
/// line, so a read that starts after offset 0 must first pass the file's first line.
public struct CodexLogParser: Sendable {
    private enum UsageSource: Sendable {
        case tokenCount
        case tokenUsageRecord
    }

    private struct CommandDraft: Sendable {
        let itemID: String
        let position: Int
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
        var completedAt: Date
        var outputTokens: Int?
        var thinkingTokens: Int?
        var usageSource: UsageSource?
        var toolCallCount = 0
        var commands: [CommandDraft] = []
    }

    private let sessionID: String
    private let projectKeySalt: [UInt8]

    private var providerAccountID: String?
    private var projectKey: String?
    private var model: String?
    private var turnID: String?
    private var turnStartOffset: Int64?
    private var isInTask = false
    /// A `turn_context` outside a task started the current turn and no output has followed it yet.
    private var isTurnStartedByContext = false

    private var responses: [ResponseDraft] = []
    private var quotaReadings: [LogQuotaReading] = []
    /// Output items extend the last response until a prompt, tool result, turn change, or usage line ends it.
    private var acceptsOutput = false
    /// Usage lines apply to the last response until a prompt, tool result, or turn change.
    private var acceptsUsage = false
    private var lastInputAt: Date?
    private var firstLineOffset: Int64?

    public init(filePath: String, projectKeySalt: [UInt8]) {
        sessionID = Self.sessionID(filePath: filePath)
        self.projectKeySalt = projectKeySalt
    }

    public mutating func consume(line: Data, at byteOffset: Int64) {
        if firstLineOffset == nil { firstLineOffset = byteOffset }
        guard let object = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = object["type"] as? String,
              let timestamp = (object["timestamp"] as? String).flatMap(Self.date) else { return }
        let payload = object["payload"] as? [String: Any] ?? [:]
        switch type {
        case "session_meta":
            providerAccountID = payload["creator_account_id"] as? String
            if let cwd = payload["cwd"] as? String { setWorkingDirectory(cwd) }
        case "turn_context":
            if !isInTask && !isTurnStartedByContext {
                turnStartOffset = byteOffset
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
        var output = LogParseOutput(quotaReadings: quotaReadings,
                                    resumeByteOffset: responses.last?.resumeOffset ?? firstLineOffset ?? 0)
        for draft in responses {
            guard let model = draft.model else { continue }
            output.responses.append(ModelResponse(
                provider: .codex, responseID: draft.responseID, sessionID: sessionID, turnID: draft.turnID,
                model: model, projectKey: draft.projectKey, requestedAt: draft.requestedAt,
                completedAt: draft.completedAt, outputTokens: draft.outputTokens, thinkingTokens: draft.thinkingTokens,
                toolCallCount: draft.toolCallCount,
                hasParallelToolCalls: draft.toolCallCount >= 2 || draft.commands.count >= 2))
            output.commands += draft.commands.map { command in
                ShellCommandEvent(provider: .codex, commandID: "\(command.itemID):\(command.position)",
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
            case "user": receiveInput(at: timestamp)
            default: break
            }
        case "reasoning":
            addOutput(at: byteOffset, timestamp: timestamp, isToolCall: false)
        case "function_call", "custom_tool_call", "local_shell_call", "web_search_call":
            addOutput(at: byteOffset, timestamp: timestamp, isToolCall: true)
        case "function_call_output", "custom_tool_call_output":
            receiveInput(at: timestamp)
        default:
            break
        }
    }

    private mutating func readEvent(_ event: String?, _ payload: [String: Any], at byteOffset: Int64, timestamp: Date) {
        switch event {
        case "task_started":
            if isInTask || !isTurnStartedByContext { turnStartOffset = byteOffset }
            isTurnStartedByContext = false
            isInTask = true
            turnID = payload["turn_id"] as? String ?? "\(sessionID):\(byteOffset)"
            endResponse()
        case "task_complete":
            isInTask = false
            isTurnStartedByContext = false
            turnID = nil
            endResponse()
        case "user_message":
            receiveInput(at: timestamp)
        case "token_usage_record":
            readUsage(payload["usage"] as? [String: Any], source: .tokenUsageRecord, timestamp: timestamp)
        case "token_count":
            let info = payload["info"] as? [String: Any]
            readUsage(info?["last_token_usage"] as? [String: Any], source: .tokenCount, timestamp: timestamp)
            readRateLimits(payload["rate_limits"] as? [String: Any], observedAt: timestamp)
        case "item_completed":
            readCompletedItem(payload["item"] as? [String: Any], timestamp: timestamp)
        default:
            break
        }
    }

    private mutating func addOutput(at byteOffset: Int64, timestamp: Date, isToolCall: Bool) {
        if !acceptsOutput {
            let responseID = "\(sessionID):\(byteOffset)"
            responses.append(ResponseDraft(responseID: responseID, resumeOffset: turnStartOffset ?? byteOffset,
                                           turnID: turnID ?? responseID, model: model, projectKey: projectKey,
                                           requestedAt: lastInputAt, completedAt: timestamp))
            lastInputAt = nil
            acceptsOutput = true
        }
        acceptsUsage = true
        isTurnStartedByContext = false
        responses[responses.count - 1].completedAt = timestamp
        if isToolCall { responses[responses.count - 1].toolCallCount += 1 }
    }

    /// Newer logs write `token_usage_record` and may also write `token_count`; the record wins.
    private mutating func readUsage(_ usage: [String: Any]?, source: UsageSource, timestamp: Date) {
        guard let usage, acceptsUsage, let index = responses.indices.last,
              !(source == .tokenCount && responses[index].usageSource == .tokenUsageRecord) else { return }
        responses[index].outputTokens = Self.integer(usage["output_tokens"])
        responses[index].thinkingTokens = Self.integer(usage["reasoning_output_tokens"])
        responses[index].usageSource = source
        responses[index].completedAt = timestamp
        acceptsOutput = false
    }

    private mutating func readCompletedItem(_ item: [String: Any]?, timestamp: Date) {
        guard let item, let command = item["command"] as? String else { return }
        receiveInput(at: timestamp)
        // On a resumed read, a command can complete before any response of the read; it was emitted earlier.
        guard let itemID = item["id"] as? String, let index = responses.indices.last else { return }
        let position = responses[index].commands.count { $0.itemID == itemID }
        responses[index].commands.append(CommandDraft(itemID: itemID, position: position, executedAt: timestamp,
                                                      succeeded: Self.integer(item["exit_code"]).map { $0 == 0 },
                                                      command: command))
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

    private mutating func receiveInput(at timestamp: Date) {
        lastInputAt = timestamp
        endResponse()
    }

    private mutating func endResponse() {
        acceptsOutput = false
        acceptsUsage = false
    }

    private mutating func setWorkingDirectory(_ path: String) {
        projectKey = ProjectKey.make(workingDirectory: path, salt: projectKeySalt)
    }

    /// The UUID at the end of a rollout file name, which stays the same when Codex moves or compresses the file.
    private static func sessionID(filePath: String) -> String {
        var name = filePath.split(separator: "/").last ?? Substring(filePath)
        for suffix in [".zst", ".jsonl"] where name.hasSuffix(suffix) { name = name.dropLast(suffix.count) }
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
