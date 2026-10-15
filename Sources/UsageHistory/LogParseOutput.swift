import Foundation

/// One shell command read from a log. The command text stays in memory: ingestion classifies it into a
/// `ShellCommandRecord` and discards it. This type is deliberately not `Codable`.
public struct ShellCommandEvent: Sendable, Equatable {
    public let provider: HistoryProvider
    /// Unique per provider: Claude `tool_use` id, or the Codex item id plus the command's position in it.
    public let commandID: String
    public let responseID: String
    public let sessionID: String
    public let model: String
    /// `ProjectKey` of the working directory.
    public let projectKey: String?
    public let executedAt: Date
    /// From the exit code or `is_error`. Unknown when the log has no result.
    public let succeeded: Bool?
    public let command: String

    public init(provider: HistoryProvider, commandID: String, responseID: String, sessionID: String, model: String,
                projectKey: String?, executedAt: Date, succeeded: Bool?, command: String) {
        self.provider = provider
        self.commandID = commandID
        self.responseID = responseID
        self.sessionID = sessionID
        self.model = model
        self.projectKey = projectKey
        self.executedAt = executedAt
        self.succeeded = succeeded
        self.command = command
    }
}

/// A Codex quota reading from `rate_limits` in a rollout log, before it is matched to an app account.
public struct LogQuotaReading: Sendable, Equatable {
    /// `session_meta.payload.creator_account_id`, matched to the account's `providerAccountID` on the Mac.
    public let providerAccountID: String
    /// Same form as the live Codex client: `<limit id>_primary` or `<limit id>_secondary`, with `codex` when the log
    /// has no limit id.
    public let windowID: String
    public let usedPercent: Double
    public let resetsAt: Date?
    public let windowDurationMinutes: Int?
    public let observedAt: Date

    public init(providerAccountID: String, windowID: String, usedPercent: Double, resetsAt: Date?,
                windowDurationMinutes: Int?, observedAt: Date) {
        self.providerAccountID = providerAccountID
        self.windowID = windowID
        self.usedPercent = usedPercent
        self.resetsAt = resetsAt
        self.windowDurationMinutes = windowDurationMinutes
        self.observedAt = observedAt
    }
}

/// What a log parser produces from the bytes it reads. Claude logs never contain quota readings.
public struct LogParseOutput: Sendable, Equatable {
    public var responses: [ModelResponse]
    public var commands: [ShellCommandEvent]
    public var quotaReadings: [LogQuotaReading]
    /// Absolute offset, in the uncompressed file, of the first line of the turn that contains the file's last
    /// response, which may still be growing. This is the line that opened the turn, not the response's own first
    /// line, because a response takes `turnID` from the turn's prompt and `requestedAt` from earlier lines of the
    /// turn. The next read starts here and emits the turn's responses and commands again, complete, replacing the
    /// earlier rows. When a read sees no turn, this is the end of the bytes read.
    public var resumeByteOffset: Int64

    public init(responses: [ModelResponse] = [], commands: [ShellCommandEvent] = [],
                quotaReadings: [LogQuotaReading] = [], resumeByteOffset: Int64) {
        self.responses = responses
        self.commands = commands
        self.quotaReadings = quotaReadings
        self.resumeByteOffset = resumeByteOffset
    }
}
