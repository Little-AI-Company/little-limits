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

public struct QuotaReading: Codable, Sendable, Equatable {
    public let provider: HistoryProvider
    public let accountID: UUID
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

public struct ModelResponse: Codable, Sendable, Equatable {
    public let provider: HistoryProvider
    public let responseID: String
    public let sessionID: String
    public let turnID: String
    public let model: String
    public let projectKey: String?
    public let requestedAt: Date?
    public let completedAt: Date
    public let outputTokens: Int?
    public let thinkingTokens: Int?
    public let toolCallCount: Int
    public let hasParallelToolCalls: Bool

    public init(provider: HistoryProvider, responseID: String, sessionID: String, turnID: String, model: String,
                projectKey: String?, requestedAt: Date?, completedAt: Date, outputTokens: Int?, thinkingTokens: Int?,
                toolCallCount: Int, hasParallelToolCalls: Bool) {
        self.provider = provider
        self.responseID = responseID
        self.sessionID = sessionID
        self.turnID = turnID
        self.model = model
        self.projectKey = projectKey
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

public enum InlineScriptPurpose: String, Codable, Sendable {
    case editsFileInPlace
    case writesFile
    case readsJSON
    case other
}

public struct CommandClassification: Codable, Sendable, Equatable {
    public let searchProgram: SearchProgram
    public let pipesIntoHeadOrTail: Bool
    public let runsGitStatus: Bool
    public let runsGitCommit: Bool
    public let inlineInterpreter: InlineInterpreter
    public let runsSavedScript: Bool
    public let inlineScriptPurpose: InlineScriptPurpose?
    public let inlineScriptLineCount: Int?
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

public struct ShellCommandRecord: Codable, Sendable, Equatable {
    public let provider: HistoryProvider
    public let commandID: String
    public let responseID: String
    public let sessionID: String
    public let model: String
    public let projectKey: String?
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
    public let classifierVersion: Int

    public init(event: ShellCommandEvent, classification: CommandClassification, classifierVersion: Int) {
        provider = event.provider
        commandID = event.commandID
        responseID = event.responseID
        sessionID = event.sessionID
        model = event.model
        projectKey = event.projectKey
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
