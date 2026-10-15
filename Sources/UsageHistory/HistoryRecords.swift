import Foundation

public enum HistoryProvider: String, Codable, Sendable, CaseIterable {
    case claude
    case codex
}

public enum QuotaReadingSource: String, Codable, Sendable {
    case claudeOAuth
    case claudeStatusLine
    case codexAppServer
    case codexLogBackfill
}

/// One quota window of one app account at one moment. Missing readings are gaps, never zero.
public struct QuotaReading: Codable, Sendable, Equatable {
    public let provider: HistoryProvider
    public let accountID: UUID
    /// The app's `UsageWindow.id`, such as `seven_day` or `codex_secondary`.
    public let windowID: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let windowDurationMinutes: Int?
    public let observedAt: Date
    public let source: QuotaReadingSource

    public init(provider: HistoryProvider, accountID: UUID, windowID: String, usedPercent: Double, resetsAt: Date?,
                windowDurationMinutes: Int?, observedAt: Date, source: QuotaReadingSource) {
        self.provider = provider
        self.accountID = accountID
        self.windowID = windowID
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowDurationMinutes = windowDurationMinutes
        self.observedAt = observedAt
        self.source = source
    }
}

/// One model API response. Behavior metrics are grouped by model, never by account.
public struct ModelResponse: Codable, Sendable, Equatable {
    public let provider: HistoryProvider
    /// Unique per provider: Claude `message.id`, or the Codex response identifier.
    public let responseID: String
    public let sessionID: String
    /// Groups the responses between a user prompt and the final reply, for steps per turn.
    public let turnID: String
    public let model: String
    /// The working directory's last path component only.
    public let projectName: String?
    /// The previous user prompt or tool result, which starts the approximate output speed interval.
    public let requestedAt: Date?
    /// The response's last log line.
    public let completedAt: Date
    /// Unknown when the log has no final usage line for the response.
    public let outputTokens: Int?
    public let thinkingTokens: Int?
    public let toolCallCount: Int
    /// Claude: two or more tool calls. Codex: also one `exec` call that runs two or more commands.
    public let hasParallelToolCalls: Bool

    public init(provider: HistoryProvider, responseID: String, sessionID: String, turnID: String, model: String,
                projectName: String?, requestedAt: Date?, completedAt: Date, outputTokens: Int?, thinkingTokens: Int?,
                toolCallCount: Int, hasParallelToolCalls: Bool) {
        self.provider = provider
        self.responseID = responseID
        self.sessionID = sessionID
        self.turnID = turnID
        self.model = model
        self.projectName = projectName
        self.requestedAt = requestedAt
        self.completedAt = completedAt
        self.outputTokens = outputTokens
        self.thinkingTokens = thinkingTokens
        self.toolCallCount = toolCallCount
        self.hasParallelToolCalls = hasParallelToolCalls
    }
}

public enum SearchProgram: String, Codable, Sendable {
    case none
    case grep
    case ripgrep
}

public enum InlineInterpreter: String, Codable, Sendable {
    case none
    case python
    case javascript
}

/// Ordered keyword groups for inline Python. The first matching group wins.
public enum InlineScriptPurpose: String, Codable, Sendable {
    case editsFileInPlace
    case writesFile
    case readsJSON
    case other
}

/// Facts derived from one shell command. Contains no command text or arguments.
public struct CommandClassification: Codable, Sendable, Equatable {
    public let searchProgram: SearchProgram
    public let pipesIntoHeadOrTail: Bool
    public let runsGitStatus: Bool
    public let runsGitCommit: Bool
    public let inlineInterpreter: InlineInterpreter
    public let runsSavedScript: Bool
    public let inlineScriptPurpose: InlineScriptPurpose?
    public let inlineScriptLineCount: Int?
    /// Program names with all arguments removed, such as `grep | head` or `python3 <<heredoc`. Only allow-listed
    /// subcommands such as `git status` follow a program name.
    public let programSequence: String

    public init(searchProgram: SearchProgram, pipesIntoHeadOrTail: Bool, runsGitStatus: Bool, runsGitCommit: Bool,
                inlineInterpreter: InlineInterpreter, runsSavedScript: Bool, inlineScriptPurpose: InlineScriptPurpose?,
                inlineScriptLineCount: Int?, programSequence: String) {
        self.searchProgram = searchProgram
        self.pipesIntoHeadOrTail = pipesIntoHeadOrTail
        self.runsGitStatus = runsGitStatus
        self.runsGitCommit = runsGitCommit
        self.inlineInterpreter = inlineInterpreter
        self.runsSavedScript = runsSavedScript
        self.inlineScriptPurpose = inlineScriptPurpose
        self.inlineScriptLineCount = inlineScriptLineCount
        self.programSequence = programSequence
    }
}

/// The stored form of one shell command: event metadata and classification facts, never the command text.
public struct ShellCommandRecord: Codable, Sendable, Equatable {
    public let provider: HistoryProvider
    public let commandID: String
    public let responseID: String
    public let sessionID: String
    public let model: String
    public let projectName: String?
    public let executedAt: Date
    public let succeeded: Bool?
    public let characterCount: Int
    public let lineCount: Int
    public let searchProgram: SearchProgram
    public let pipesIntoHeadOrTail: Bool
    public let runsGitStatus: Bool
    public let runsGitCommit: Bool
    public let inlineInterpreter: InlineInterpreter
    public let runsSavedScript: Bool
    public let inlineScriptPurpose: InlineScriptPurpose?
    public let inlineScriptLineCount: Int?
    public let programSequence: String
    /// Rules change over time. Records whose source logs are gone keep the version that produced them.
    public let classifierVersion: Int

    public init(event: ShellCommandEvent, classification: CommandClassification, classifierVersion: Int) {
        provider = event.provider
        commandID = event.commandID
        responseID = event.responseID
        sessionID = event.sessionID
        model = event.model
        projectName = event.projectName
        executedAt = event.executedAt
        succeeded = event.succeeded
        characterCount = event.command.count
        lineCount = event.command.split(separator: "\n", omittingEmptySubsequences: false).count
        searchProgram = classification.searchProgram
        pipesIntoHeadOrTail = classification.pipesIntoHeadOrTail
        runsGitStatus = classification.runsGitStatus
        runsGitCommit = classification.runsGitCommit
        inlineInterpreter = classification.inlineInterpreter
        runsSavedScript = classification.runsSavedScript
        inlineScriptPurpose = classification.inlineScriptPurpose
        inlineScriptLineCount = classification.inlineScriptLineCount
        programSequence = classification.programSequence
        self.classifierVersion = classifierVersion
    }
}

/// How far ingestion has read one log file. A moved or compressed file is read again from the start;
/// unique record keys make the second read add nothing.
public struct SourceFilePosition: Codable, Sendable, Equatable {
    public let path: String
    public let byteOffset: Int64
    public let fileSize: Int64
    public let modifiedAt: Date

    public init(path: String, byteOffset: Int64, fileSize: Int64, modifiedAt: Date) {
        self.path = path
        self.byteOffset = byteOffset
        self.fileSize = fileSize
        self.modifiedAt = modifiedAt
    }
}
