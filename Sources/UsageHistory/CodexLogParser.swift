import Foundation

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

    private var hasReadSessionMeta = false
    private var providerAccountID: String?
    private var projectKey: String?
    private var model: String?
    private var turnID: String?
    private var turnResumeOffset: Int64?
    private var isInTask = false
    private var isTurnStartedByContext = false

    private var responses: [ResponseDraft] = []
    private var quotaReadings: [LogQuotaReading] = []
    private var acceptsOutput = false
    private var acceptsUsage = false
    private var lastInput: (offset: Int64, timestamp: Date)?
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

    private mutating func readCompletedItem(_ item: [String: Any]?, at byteOffset: Int64, timestamp: Date) {
        switch item?["type"] as? String {
        case "AgentMessage", "Reasoning": addOutput(at: byteOffset, timestamp: timestamp, isToolCall: false)
        default: break
        }
        guard let item, item["source"] as? String != "user_shell", let command = Self.commandText(item["command"]),
              let itemID = item["id"] as? String, let index = commandOwnerIndex(item, completedAt: timestamp)
        else { return }
        responses[index].commands.append(CommandDraft(itemID: itemID, executedAt: timestamp,
                                                      succeeded: Self.integer(item["exit_code"]).map { $0 == 0 },
                                                      command: command))
    }

    private func commandOwnerIndex(_ item: [String: Any], completedAt: Date) -> Int? {
        guard let duration = item["duration"] as? [String: Any],
              let seconds = Self.number(duration["secs"]) else { return responses.indices.last }
        let startedAt = completedAt.addingTimeInterval(-(seconds + (Self.number(duration["nanos"]) ?? 0) / 1e9))
        return responses.lastIndex { $0.startedAt <= startedAt.addingTimeInterval(Self.commandStartTolerance) }
    }

    private static let commandStartTolerance: TimeInterval = 1

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
