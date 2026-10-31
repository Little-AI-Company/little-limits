import Foundation

public struct ShellCommandEvent: Sendable, Equatable {
    public let provider: HistoryProvider
    public let commandID: String
    public let responseID: String
    public let sessionID: String
    public let model: String
    public let projectKey: String?
    public let executedAt: Date
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

public struct LogQuotaReading: Sendable, Equatable {
    public let providerAccountID: String
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

public struct LogParseOutput: Sendable, Equatable {
    public var responses: [ModelResponse]
    public var commands: [ShellCommandEvent]
    public var quotaReadings: [LogQuotaReading]
    public var resumeByteOffset: Int64

    public init(responses: [ModelResponse] = [], commands: [ShellCommandEvent] = [],
                quotaReadings: [LogQuotaReading] = [], resumeByteOffset: Int64) {
        self.responses = responses
        self.commands = commands
        self.quotaReadings = quotaReadings
        self.resumeByteOffset = resumeByteOffset
    }
}
