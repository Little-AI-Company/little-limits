import Foundation

public struct ClaudeLogParser: Sendable {
    private let projectKeySalt: [UInt8]
    private var projectKeys: [String: String] = [:]

    private var responses: [String: ResponseState] = [:]
    private var responseOrder: [String] = []
    private var commands: [CommandState] = []
    private var commandIDs: Set<String> = []
    private var toolResultErrors: [String: Bool] = [:]

    private var lastRequest: (offset: Int64, timestamp: Date)?
    private var turn: Turn?
    private var endOfInput: Int64 = 0

    public init(filePath: String, projectKeySalt: [UInt8]) {
        self.projectKeySalt = projectKeySalt
    }

    public mutating func consume(line: Data, at byteOffset: Int64) {
        endOfInput = max(endOfInput, byteOffset + Int64(line.count) + (line.last == 0x0A ? 0 : 1))
        guard let entry = try? JSONDecoder().decode(LogLine.self, from: line),
              let timestampText = entry.timestamp,
              let timestamp = Self.parseTimestamp(timestampText) else { return }
        switch entry.type {
        case "user": consumeUser(entry, at: byteOffset, timestamp: timestamp)
        case "assistant": consumeAssistant(entry, at: byteOffset, timestamp: timestamp)
        default: return
        }
    }

    public func finish() -> LogParseOutput {
        let outputResponses = responseOrder.compactMap { id -> ModelResponse? in
            guard let state = responses[id] else { return nil }
            return ModelResponse(
                provider: .claude, responseID: id, sessionID: state.sessionID, turnID: state.turnID,
                model: state.model, projectKey: state.projectKey, requestedAt: state.requestedAt,
                completedAt: state.completedAt, outputTokens: state.hasFinalUsage ? state.maxOutputTokens : nil,
                thinkingTokens: state.hasFinalUsage ? state.maxThinkingTokens : nil,
                toolCallCount: state.toolUseIDs.count, hasParallelToolCalls: state.toolUseIDs.count >= 2)
        }
        let outputCommands = commands.map { command in
            ShellCommandEvent(
                provider: .claude, commandID: command.id, responseID: command.responseID,
                sessionID: command.sessionID, model: command.model, projectKey: command.projectKey,
                executedAt: command.executedAt, succeeded: toolResultErrors[command.id].map { !$0 },
                command: command.command)
        }
        return LogParseOutput(responses: outputResponses, commands: outputCommands,
                              resumeByteOffset: turn?.startOffset ?? endOfInput)
    }

    private mutating func consumeUser(_ entry: LogLine, at byteOffset: Int64, timestamp: Date) {
        guard entry.isMeta != true, entry.isCompactSummary != true,
              let content = entry.message?.content else { return }
        let toolResults = content.blocks.filter { $0.type == "tool_result" }
        if toolResults.isEmpty {
            turn = Turn(id: entry.uuid ?? "\(entry.sessionId ?? ""):\(byteOffset)", startOffset: byteOffset)
        } else {
            for result in toolResults {
                guard let id = result.toolUseID else { continue }
                toolResultErrors[id] = result.isError ?? false
            }
        }
        lastRequest = (byteOffset, timestamp)
    }

    private mutating func consumeAssistant(_ entry: LogLine, at byteOffset: Int64, timestamp: Date) {
        guard let message = entry.message, let responseID = message.id, let model = message.model,
              model != Self.syntheticModel, let sessionID = entry.sessionId else { return }
        let projectKey = entry.cwd.map { projectKey(for: $0) }

        var state: ResponseState
        if let existing = responses[responseID] {
            state = existing
        } else {
            let turnID = openTurn(responseID: responseID, at: byteOffset)
            let turnStart = turn?.startOffset ?? byteOffset
            let requestedAt = lastRequest.flatMap { $0.offset >= turnStart ? $0.timestamp : nil }
            state = ResponseState(sessionID: sessionID, turnID: turnID, model: model, projectKey: projectKey,
                                  requestedAt: requestedAt, completedAt: timestamp)
            responseOrder.append(responseID)
        }
        state.completedAt = timestamp
        if let usage = message.usage {
            if let output = usage.outputTokens { state.maxOutputTokens = max(state.maxOutputTokens ?? 0, output) }
            if let thinking = usage.thinkingTokens { state.maxThinkingTokens = max(state.maxThinkingTokens ?? 0, thinking) }
        }
        for block in message.content?.blocks ?? [] where block.type == "tool_use" {
            guard let toolUseID = block.id, state.toolUseIDs.insert(toolUseID).inserted else { continue }
            if block.name == "Bash", let command = block.command, commandIDs.insert(toolUseID).inserted {
                commands.append(CommandState(id: toolUseID, responseID: responseID, sessionID: sessionID,
                                             model: model, projectKey: projectKey, executedAt: timestamp,
                                             command: command))
            }
        }
        if let stopReason = message.stopReason {
            if message.usage?.outputTokens != nil { state.hasFinalUsage = true }
            if stopReason == "end_turn", turn?.id == state.turnID { turn?.closedAtOffset = byteOffset }
        }
        responses[responseID] = state
    }

    private mutating func openTurn(responseID: String, at byteOffset: Int64) -> String {
        if let turn, turn.closedAtOffset == nil { return turn.id }
        var startOffset = byteOffset
        if let request = lastRequest, request.offset > (turn?.closedAtOffset ?? -1) { startOffset = request.offset }
        turn = Turn(id: responseID, startOffset: startOffset)
        return responseID
    }

    private mutating func projectKey(for workingDirectory: String) -> String {
        if let key = projectKeys[workingDirectory] { return key }
        let key = ProjectKey.make(workingDirectory: workingDirectory, salt: projectKeySalt)
        projectKeys[workingDirectory] = key
        return key
    }

    private static let syntheticModel = "<synthetic>"

    private static func parseTimestamp(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date
        }
        return try? Date(text, strategy: Date.ISO8601FormatStyle())
    }
}

private struct Turn: Sendable {
    let id: String
    let startOffset: Int64
    var closedAtOffset: Int64?
}

private struct ResponseState: Sendable {
    let sessionID: String
    let turnID: String
    let model: String
    let projectKey: String?
    let requestedAt: Date?
    var completedAt: Date
    var maxOutputTokens: Int?
    var maxThinkingTokens: Int?
    var hasFinalUsage = false
    var toolUseIDs: Set<String> = []
}

private struct CommandState: Sendable {
    let id: String
    let responseID: String
    let sessionID: String
    let model: String
    let projectKey: String?
    let executedAt: Date
    let command: String
}

// MARK: - Log line shape

private struct LogLine: Decodable {
    let type: String?
    let uuid: String?
    let timestamp: String?
    let sessionId: String?
    let cwd: String?
    let isMeta: Bool?
    let isCompactSummary: Bool?
    let message: LogMessage?

    private enum CodingKeys: String, CodingKey {
        case type, uuid, timestamp, sessionId, cwd, isMeta, isCompactSummary, message
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = container.lenient(String.self, .type)
        uuid = container.lenient(String.self, .uuid)
        timestamp = container.lenient(String.self, .timestamp)
        sessionId = container.lenient(String.self, .sessionId)
        cwd = container.lenient(String.self, .cwd)
        isMeta = container.lenient(Bool.self, .isMeta)
        isCompactSummary = container.lenient(Bool.self, .isCompactSummary)
        message = container.lenient(LogMessage.self, .message)
    }
}

private struct LogMessage: Decodable {
    let id: String?
    let model: String?
    let stopReason: String?
    let usage: LogUsage?
    let content: LogContent?

    private enum CodingKeys: String, CodingKey {
        case id, model, usage, content
        case stopReason = "stop_reason"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(String.self, .id)
        model = container.lenient(String.self, .model)
        stopReason = container.lenient(String.self, .stopReason)
        usage = container.lenient(LogUsage.self, .usage)
        content = container.lenient(LogContent.self, .content)
    }
}

private struct LogUsage: Decodable {
    let outputTokens: Int?
    let thinkingTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case outputTokens = "output_tokens"
        case outputTokensDetails = "output_tokens_details"
    }

    private enum DetailKeys: String, CodingKey {
        case thinkingTokens = "thinking_tokens"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        outputTokens = container.lenient(Int.self, .outputTokens)
        let details = try? container.nestedContainer(keyedBy: DetailKeys.self, forKey: .outputTokensDetails)
        thinkingTokens = details?.lenient(Int.self, .thinkingTokens)
    }
}

private struct LogContent: Decodable {
    let blocks: [LogContentBlock]

    init(from decoder: any Decoder) throws {
        blocks = (try? decoder.singleValueContainer().decode([LogContentBlock].self)) ?? []
    }
}

private struct LogContentBlock: Decodable {
    let type: String?
    let id: String?
    let name: String?
    let command: String?
    let toolUseID: String?
    let isError: Bool?

    private enum CodingKeys: String, CodingKey {
        case type, id, name, input
        case toolUseID = "tool_use_id"
        case isError = "is_error"
    }

    private enum InputKeys: String, CodingKey {
        case command
    }

    init(from decoder: any Decoder) throws {
        let container = try? decoder.container(keyedBy: CodingKeys.self)
        type = container?.lenient(String.self, .type)
        id = container?.lenient(String.self, .id)
        name = container?.lenient(String.self, .name)
        toolUseID = container?.lenient(String.self, .toolUseID)
        isError = container?.lenient(Bool.self, .isError)
        let input = try? container?.nestedContainer(keyedBy: InputKeys.self, forKey: .input)
        command = input?.lenient(String.self, .command)
    }
}

private extension KeyedDecodingContainer {
    func lenient<Value: Decodable>(_ type: Value.Type, _ key: Key) -> Value? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }
}
