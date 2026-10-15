import Foundation
import GRDB
import UsageHistory

/// A count out of a total. The value is unknown, not zero, when the total is zero.
public struct MetricRatio: Sendable, Equatable {
    public let count: Int
    public let total: Int

    public init(count: Int, total: Int) {
        self.count = count
        self.total = total
    }

    public var value: Double? { total > 0 ? Double(count) / Double(total) : nil }
}

/// The median and 90th percentile of a sample. Nil when the sample is empty.
public struct MetricDistribution: Sendable, Equatable {
    public let sampleCount: Int
    public let mean: Double
    public let median: Double
    public let percentile90: Double

    /// Linear interpolation between the closest ranks, so the median of an even sample is the mean of its middle pair.
    public init?(_ values: [Double]) {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        func percentile(_ fraction: Double) -> Double {
            let position = fraction * Double(sorted.count - 1)
            let lower = Int(position.rounded(.down))
            let upper = min(lower + 1, sorted.count - 1)
            return sorted[lower] + (sorted[upper] - sorted[lower]) * (position - Double(lower))
        }
        sampleCount = sorted.count
        mean = sorted.reduce(0, +) / Double(sorted.count)
        median = percentile(0.5)
        percentile90 = percentile(0.9)
    }
}

/// Behavior metrics for one model, M1 to M9 and P1 to P5 in `docs/USAGE-ANALYTICS-PLAN.md`. Never per account.
public struct ModelMetrics: Sendable, Equatable, Identifiable {
    /// M9: below this many responses a model's numbers are noisy.
    public static let reliableResponseCount = 5_000

    public struct ID: Hashable, Sendable {
        public let provider: HistoryProvider
        public let model: String
    }

    public let provider: HistoryProvider
    public let model: String
    public var id: ID { ID(provider: provider, model: model) }

    /// M9: stored responses for the model.
    public let responseCount: Int
    /// M1: output tokens, thinking included, per second from the previous prompt or tool result to the response's
    /// last log line. Approximate: the interval includes the wait before the first token.
    public let outputSpeed: MetricDistribution?
    /// M2: responses per turn, in sessions with at least one tool call.
    public let stepsPerTurn: MetricDistribution?
    /// M7: thinking tokens out of output tokens, over responses whose final usage is known.
    public let thinkingTokens: MetricRatio
    /// M8: responses with parallel tool calls out of all responses.
    public let parallelToolCallResponses: MetricRatio

    /// Shell commands for the model, the base of M4, M6, P1, and P2.
    public let shellCommandCount: Int
    /// M3: grep out of shell searches that use grep or rg.
    public let grepSearches: MetricRatio
    /// M4: commands piped into head or tail out of all shell commands.
    public let headOrTailPipes: MetricRatio
    /// M5: `git status` runs per successful `git commit`.
    public let gitStatusPerCommit: MetricRatio
    /// M6: characters per shell command.
    public let commandLength: MetricDistribution?

    /// P1: commands running inline Python out of all shell commands.
    public let inlinePython: MetricRatio
    /// P1: commands running inline JavaScript out of all shell commands.
    public let inlineJavaScript: MetricRatio
    /// P2: runs of a saved script file, counted apart from inline code.
    public let savedScriptRuns: MetricRatio
    /// P3: commands running inline code out of commands with a known project other than this model's busiest project.
    public let inlineOutsideBusiestProject: MetricRatio
    /// P4: inline Python commands per purpose. Commands without a classified purpose are left out.
    public let inlinePythonPurposes: [InlineScriptPurpose: Int]
    /// P5: lines per inline script, Python and JavaScript.
    public let inlineScriptLines: MetricDistribution?

    public var isSmallSample: Bool { responseCount < Self.reliableResponseCount }
    public var inlineCode: MetricRatio {
        MetricRatio(count: inlinePython.count + inlineJavaScript.count, total: shellCommandCount)
    }
}

public struct ModelMetricsReport: Sendable, Equatable {
    /// Claude models first, then Codex; most responses first within a provider.
    public let models: [ModelMetrics]
    public let firstResponseAt: Date?
    public let lastResponseAt: Date?

    public var isEmpty: Bool { models.isEmpty }
}

/// Reads per-model behavior metrics from the `modelResponse` and `shellCommand` tables. SQL groups counts and sums;
/// medians and percentiles are computed in Swift. Unknown token counts are left out, never read as zero.
public enum ModelMetricsQuery {
    public static func fetch(_ db: Database) throws -> ModelMetricsReport {
        var responses: [ModelMetrics.ID: ResponseTotals] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT provider, model, COUNT(*) AS responses, SUM(hasParallelToolCalls) AS parallel,
                   SUM(CASE WHEN outputTokens IS NOT NULL AND thinkingTokens IS NOT NULL THEN outputTokens END) AS output,
                   SUM(CASE WHEN outputTokens IS NOT NULL AND thinkingTokens IS NOT NULL THEN thinkingTokens END) AS thinking
            FROM modelResponse GROUP BY provider, model
            """) {
            responses[try id(row)] = ResponseTotals(responses: row["responses"], parallel: row["parallel"],
                                                output: row["output"] ?? 0, thinking: row["thinking"] ?? 0)
        }

        var speeds: [ModelMetrics.ID: [Double]] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT provider, model, outputTokens, requestedAt, completedAt FROM modelResponse
            WHERE outputTokens > 0 AND requestedAt IS NOT NULL
            """) {
            let requestedAt: Date = row["requestedAt"]
            let completedAt: Date = row["completedAt"]
            let seconds = completedAt.timeIntervalSince(requestedAt)
            guard seconds > 0 else { continue }
            let tokens: Int = row["outputTokens"]
            speeds[try id(row), default: []].append(Double(tokens) / seconds)
        }

        var steps: [ModelMetrics.ID: [Double]] = [:]
        for row in try Row.fetchAll(db, sql: """
            WITH toolSession AS (SELECT DISTINCT provider, sessionID FROM modelResponse WHERE toolCallCount > 0)
            SELECT response.provider, response.model, COUNT(*) AS steps
            FROM modelResponse AS response
            JOIN toolSession USING (provider, sessionID)
            GROUP BY response.provider, response.sessionID, response.turnID, response.model
            """) {
            let count: Int = row["steps"]
            steps[try id(row), default: []].append(Double(count))
        }

        // P3 compares each model with its own busiest project, so one model's main project does not set another's.
        var commands: [ModelMetrics.ID: CommandTotals] = [:]
        for row in try Row.fetchAll(db, sql: """
            WITH projectCommands AS (
                SELECT provider, model, projectKey, COUNT(*) AS commands FROM shellCommand
                WHERE projectKey IS NOT NULL GROUP BY provider, model, projectKey
            ), busiest AS (
                SELECT provider, model, projectKey AS busiestKey FROM (
                    SELECT provider, model, projectKey,
                           ROW_NUMBER() OVER (PARTITION BY provider, model ORDER BY commands DESC, projectKey) AS position
                    FROM projectCommands
                ) WHERE position = 1
            )
            SELECT provider, model, COUNT(*) AS commands,
                   SUM(searchProgram = 'grep') AS grep, SUM(searchProgram = 'ripgrep') AS ripgrep,
                   SUM(pipesIntoHeadOrTail) AS headOrTail, SUM(runsGitStatus) AS gitStatus,
                   SUM(runsGitCommit AND succeeded = 1) AS gitCommit,
                   SUM(inlineInterpreter = 'python') AS python, SUM(inlineInterpreter = 'javascript') AS javascript,
                   SUM(runsSavedScript) AS savedScript,
                   SUM(projectKey IS NOT NULL AND projectKey IS NOT busiestKey) AS otherProject,
                   SUM(projectKey IS NOT NULL AND projectKey IS NOT busiestKey AND inlineInterpreter != 'none')
                       AS otherProjectInline
            FROM shellCommand LEFT JOIN busiest USING (provider, model)
            GROUP BY provider, model
            """) {
            commands[try id(row)] = CommandTotals(
                commands: row["commands"], grep: row["grep"], ripgrep: row["ripgrep"], headOrTail: row["headOrTail"],
                gitStatus: row["gitStatus"], gitCommit: row["gitCommit"], python: row["python"],
                javascript: row["javascript"], savedScript: row["savedScript"], otherProject: row["otherProject"],
                otherProjectInline: row["otherProjectInline"])
        }

        var lengths: [ModelMetrics.ID: [Double]] = [:]
        var scriptLines: [ModelMetrics.ID: [Double]] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT provider, model, characterCount,
                   CASE WHEN inlineInterpreter != 'none' THEN inlineScriptLineCount END AS scriptLines
            FROM shellCommand
            """) {
            let key = try id(row)
            let length: Int = row["characterCount"]
            lengths[key, default: []].append(Double(length))
            if let lines: Int = row["scriptLines"] { scriptLines[key, default: []].append(Double(lines)) }
        }

        var purposes: [ModelMetrics.ID: [InlineScriptPurpose: Int]] = [:]
        for row in try Row.fetchAll(db, sql: """
            SELECT provider, model, inlineScriptPurpose AS purpose, COUNT(*) AS commands FROM shellCommand
            WHERE inlineInterpreter = 'python' AND inlineScriptPurpose IS NOT NULL
            GROUP BY provider, model, inlineScriptPurpose
            """) {
            guard let purpose = InlineScriptPurpose(rawValue: row["purpose"]) else { continue }
            purposes[try id(row), default: [:]][purpose] = row["commands"]
        }

        let providerOrder = Dictionary(uniqueKeysWithValues: HistoryProvider.allCases.enumerated().map { ($1, $0) })
        let models = Set(responses.keys).union(commands.keys).map { key in
            let response = responses[key] ?? ResponseTotals(responses: 0, parallel: 0, output: 0, thinking: 0)
            let command = commands[key] ?? CommandTotals()
            return ModelMetrics(
                provider: key.provider, model: key.model, responseCount: response.responses,
                outputSpeed: MetricDistribution(speeds[key] ?? []), stepsPerTurn: MetricDistribution(steps[key] ?? []),
                thinkingTokens: MetricRatio(count: response.thinking, total: response.output),
                parallelToolCallResponses: MetricRatio(count: response.parallel, total: response.responses),
                shellCommandCount: command.commands,
                grepSearches: MetricRatio(count: command.grep, total: command.grep + command.ripgrep),
                headOrTailPipes: MetricRatio(count: command.headOrTail, total: command.commands),
                gitStatusPerCommit: MetricRatio(count: command.gitStatus, total: command.gitCommit),
                commandLength: MetricDistribution(lengths[key] ?? []),
                inlinePython: MetricRatio(count: command.python, total: command.commands),
                inlineJavaScript: MetricRatio(count: command.javascript, total: command.commands),
                savedScriptRuns: MetricRatio(count: command.savedScript, total: command.commands),
                inlineOutsideBusiestProject: MetricRatio(count: command.otherProjectInline, total: command.otherProject),
                inlinePythonPurposes: purposes[key] ?? [:], inlineScriptLines: MetricDistribution(scriptLines[key] ?? []))
        }.sorted {
            if $0.provider != $1.provider { return providerOrder[$0.provider, default: 0] < providerOrder[$1.provider, default: 0] }
            if $0.responseCount != $1.responseCount { return $0.responseCount > $1.responseCount }
            return $0.model < $1.model
        }

        let range = try Row.fetchOne(db, sql: "SELECT MIN(completedAt) AS first, MAX(completedAt) AS last FROM modelResponse")
        return ModelMetricsReport(models: models, firstResponseAt: range?["first"], lastResponseAt: range?["last"])
    }

    private static func id(_ row: Row) throws -> ModelMetrics.ID {
        let value: String = row["provider"]
        guard let provider = HistoryProvider(rawValue: value) else {
            throw DatabaseError(message: "The usage history has an unknown provider: \(value).")
        }
        return ModelMetrics.ID(provider: provider, model: row["model"])
    }

    private struct ResponseTotals {
        let responses: Int
        let parallel: Int
        let output: Int
        let thinking: Int
    }

    private struct CommandTotals {
        var commands = 0, grep = 0, ripgrep = 0, headOrTail = 0, gitStatus = 0, gitCommit = 0
        var python = 0, javascript = 0, savedScript = 0, otherProject = 0, otherProjectInline = 0
    }
}

extension HistoryDatabase {
    /// Reads the per-model report on a reader connection, off the caller's thread.
    public func modelMetrics() async throws -> ModelMetricsReport {
        try await pool.read(ModelMetricsQuery.fetch)
    }

    /// The current report, then a fresh one after each committed change to responses or shell commands, such as a
    /// log ingestion batch. Unchanged reports are skipped, and a slow reader receives only the newest report.
    public func modelMetricsUpdates() -> AsyncValueObservation<ModelMetricsReport> {
        ValueObservation.tracking(ModelMetricsQuery.fetch).removeDuplicates()
            .values(in: pool, bufferingPolicy: .bufferingNewest(1))
    }
}
