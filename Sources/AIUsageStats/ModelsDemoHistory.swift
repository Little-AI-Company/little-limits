import Foundation
import UsageHistory
import UsageHistoryStore

enum ModelsDemoHistory {
    private struct Profile {
        let provider: HistoryProvider
        let model: String
        let responses: Int
        let tokensPerSecond: Double
        let stepsPerTurn: Int
        let thinkingShare: Double
        let parallelShare: Double
        let unknownUsageShare: Double
        let grepShare: Double
        let headOrTailShare: Double
        let gitStatusPerCommit: Double
        let commandLength: Int
        let inlinePythonShare: Double
        let inlineJavaScriptShare: Double
        let savedScriptShare: Double
        let scriptLines: Int
    }

    private static let profiles: [Profile] = [
        Profile(provider: .claude, model: "claude-opus-5-5", responses: 9_200, tokensPerSecond: 62, stepsPerTurn: 9,
                thinkingShare: 0.34, parallelShare: 0.21, unknownUsageShare: 0.25, grepShare: 0.92,
                headOrTailShare: 0.31, gitStatusPerCommit: 2.6, commandLength: 140, inlinePythonShare: 0.07,
                inlineJavaScriptShare: 0.012, savedScriptShare: 0.02, scriptLines: 16),
        Profile(provider: .claude, model: "claude-fable-5-1", responses: 6_400, tokensPerSecond: 88, stepsPerTurn: 7,
                thinkingShare: 0.22, parallelShare: 0.27, unknownUsageShare: 0.2, grepShare: 0.97,
                headOrTailShare: 0.38, gitStatusPerCommit: 3.1, commandLength: 110, inlinePythonShare: 0.05,
                inlineJavaScriptShare: 0.02, savedScriptShare: 0.015, scriptLines: 12),
        Profile(provider: .claude, model: "claude-opus-5", responses: 1_900, tokensPerSecond: 48, stepsPerTurn: 6,
                thinkingShare: 0.41, parallelShare: 0.12, unknownUsageShare: 0.3, grepShare: 0.99,
                headOrTailShare: 0.44, gitStatusPerCommit: 4.0, commandLength: 95, inlinePythonShare: 0.09,
                inlineJavaScriptShare: 0.005, savedScriptShare: 0.03, scriptLines: 21),
        Profile(provider: .codex, model: "gpt-6.1-sol", responses: 7_600, tokensPerSecond: 71, stepsPerTurn: 14,
                thinkingShare: 0.58, parallelShare: 0.17, unknownUsageShare: 0.02, grepShare: 0.015,
                headOrTailShare: 0.52, gitStatusPerCommit: 1.8, commandLength: 210, inlinePythonShare: 0.11,
                inlineJavaScriptShare: 0.006, savedScriptShare: 0.01, scriptLines: 24),
        Profile(provider: .codex, model: "gpt-6-astra", responses: 5_300, tokensPerSecond: 105, stepsPerTurn: 10,
                thinkingShare: 0.46, parallelShare: 0.03, unknownUsageShare: 0.02, grepShare: 0.02,
                headOrTailShare: 0.47, gitStatusPerCommit: 2.2, commandLength: 160, inlinePythonShare: 0.08,
                inlineJavaScriptShare: 0.01, savedScriptShare: 0.012, scriptLines: 18),
        Profile(provider: .codex, model: "gpt-5.5", responses: 1_100, tokensPerSecond: 64, stepsPerTurn: 8,
                thinkingShare: 0.51, parallelShare: 0.02, unknownUsageShare: 0.05, grepShare: 0.06,
                headOrTailShare: 0.4, gitStatusPerCommit: 2.9, commandLength: 130, inlinePythonShare: 0.06,
                inlineJavaScriptShare: 0.004, savedScriptShare: 0.02, scriptLines: 14)
    ]

    private static let purposes: [(InlineScriptPurpose, Double)] = [
        (.editsFileInPlace, 0.38), (.writesFile, 0.17), (.readsJSON, 0.27), (.other, 0.18)
    ]
    private static let projects: [(String, Double)] = [
        ("0000000000000001", 0.5), ("0000000000000002", 0.2), ("0000000000000003", 0.15),
        ("0000000000000004", 0.1), ("0000000000000005", 0.05)
    ]
    private static let historyDays = 120.0

    static func makeDatabase() throws -> HistoryDatabase {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AIUsageStatsDemoHistory")
        try? FileManager.default.removeItem(at: directory)
        let database = try HistoryDatabase(url: directory.appendingPathComponent("history.sqlite"))
        var generator = SeededGenerator(seed: 0x5EED)
        var responses: [ModelResponse] = []
        var commands: [ShellCommandRecord] = []
        let end = Date()
        for profile in profiles {
            generate(profile, end: end, generator: &generator, responses: &responses, commands: &commands)
        }
        try database.pool.write { db in
            for response in responses { try response.insert(db) }
            for command in commands { try command.insert(db) }
        }
        return database
    }

    private static func generate(_ profile: Profile, end: Date, generator: inout SeededGenerator,
                                 responses: inout [ModelResponse], commands: inout [ShellCommandRecord]) {
        var remaining = profile.responses
        var session = 0
        while remaining > 0 {
            session += 1
            let sessionID = "\(profile.model)-session-\(session)"
            let project = weighted(projects, &generator)
            var time = end.addingTimeInterval(-Double.random(in: 0..<historyDays * 86_400, using: &generator))
            for turn in 0..<Int.random(in: 2...8, using: &generator) where remaining > 0 {
                let steps = min(remaining, max(1, profile.stepsPerTurn + Int.random(in: -4...4, using: &generator)))
                for step in 0..<steps {
                    remaining -= 1
                    let responseID = "\(sessionID)-\(turn)-\(step)"
                    let isFinal = step == steps - 1
                    let isParallel = !isFinal && Double.random(in: 0..<1, using: &generator) < profile.parallelShare
                    let toolCalls = isFinal ? 0 : isParallel ? Int.random(in: 2...3, using: &generator) : 1
                    let output = Int.random(in: 40...1_600, using: &generator)
                    let speed = profile.tokensPerSecond * Double.random(in: 0.6...1.4, using: &generator)
                    let duration = Double(output) / speed
                    let isUnknown = Double.random(in: 0..<1, using: &generator) < profile.unknownUsageShare
                    let thinking = Int(Double(output) * min(0.95, profile.thinkingShare
                                                                * Double.random(in: 0.5...1.5, using: &generator)))
                    let completedAt = time.addingTimeInterval(duration)
                    responses.append(ModelResponse(provider: profile.provider, responseID: responseID, sessionID: sessionID,
                                      turnID: "\(sessionID)-\(turn)", model: profile.model, projectKey: project,
                                      requestedAt: time, completedAt: completedAt,
                                      outputTokens: isUnknown ? nil : output, thinkingTokens: isUnknown ? nil : thinking,
                                      toolCallCount: toolCalls, hasParallelToolCalls: isParallel))
                    for call in 0..<toolCalls where Double.random(in: 0..<1, using: &generator) < 0.7 {
                        commands.append(command(profile, id: "\(responseID)-\(call)", responseID: responseID,
                                                sessionID: sessionID, project: project, at: completedAt,
                                                generator: &generator))
                    }
                    time = completedAt.addingTimeInterval(Double.random(in: 1...20, using: &generator))
                }
            }
        }
    }

    private static func command(_ profile: Profile, id: String, responseID: String, sessionID: String, project: String,
                                at date: Date, generator: inout SeededGenerator) -> ShellCommandRecord {
        func chance(_ share: Double) -> Bool { Double.random(in: 0..<1, using: &generator) < share }
        let interpreterRoll = Double.random(in: 0..<1, using: &generator)
        let interpreter: InlineInterpreter = interpreterRoll < profile.inlinePythonShare ? .python
            : interpreterRoll < profile.inlinePythonShare + profile.inlineJavaScriptShare ? .javascript : .none
        let isSearch = interpreter == .none && chance(0.22)
        let gitRoll = Double.random(in: 0..<1, using: &generator)
        let commitShare = 0.06 / (1 + profile.gitStatusPerCommit)
        let runsGitCommit = interpreter == .none && !isSearch && gitRoll < commitShare
        let runsGitStatus = interpreter == .none && !isSearch && !runsGitCommit
            && gitRoll < commitShare * (1 + profile.gitStatusPerCommit)
        let scriptLines = interpreter == .none ? nil
            : max(2, Int(Double(profile.scriptLines) * Double.random(in: 0.3...2.6, using: &generator)))
        let length = scriptLines.map { $0 * 38 }
            ?? max(4, Int(Double(profile.commandLength) * Double.random(in: 0.2...1.8, using: &generator)))
        let lines = (scriptLines ?? 0) + 1
        let text = String(repeating: String(repeating: "x", count: max(1, length / lines)) + "\n", count: lines - 1)
            + String(repeating: "x", count: max(1, length / lines))
        let classification = CommandClassification(
            searchProgram: isSearch ? (chance(profile.grepShare) ? .grep : .ripgrep) : .none,
            pipesIntoHeadOrTail: chance(profile.headOrTailShare), runsGitStatus: runsGitStatus,
            runsGitCommit: runsGitCommit, inlineInterpreter: interpreter,
            runsSavedScript: interpreter == .none && chance(profile.savedScriptShare),
            inlineScriptPurpose: interpreter == .python ? weighted(purposes, &generator) : nil,
            inlineScriptLineCount: scriptLines, programSequence: "")
        let event = ShellCommandEvent(provider: profile.provider, commandID: id, responseID: responseID,
                                      sessionID: sessionID, model: profile.model, projectKey: project, executedAt: date,
                                      succeeded: chance(0.93), command: text)
        return ShellCommandRecord(event: event, classification: classification, classifierVersion: 1)
    }

    private static func weighted<Value>(_ choices: [(Value, Double)], _ generator: inout SeededGenerator) -> Value {
        var roll = Double.random(in: 0..<1, using: &generator)
        for (value, weight) in choices {
            if roll < weight { return value }
            roll -= weight
        }
        return choices[choices.count - 1].0
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
