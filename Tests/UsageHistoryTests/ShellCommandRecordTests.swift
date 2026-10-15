import Foundation
import Testing
import UsageHistory

@Test func storedShellCommandKeepsLengthsButNotText() throws {
    let command = "python3 - <<'EOF'\nprint(open('secret-token.txt').read())\nEOF"
    let event = ShellCommandEvent(provider: .codex, commandID: "item_1:0", responseID: "response", sessionID: "session",
                                  model: "gpt-6.1-sol", projectName: "project", executedAt: Date(timeIntervalSince1970: 0),
                                  succeeded: true, command: command)
    let classification = CommandClassification(searchProgram: .none, pipesIntoHeadOrTail: false, runsGitStatus: false,
                                               runsGitCommit: false, inlineInterpreter: .python, runsSavedScript: false,
                                               inlineScriptPurpose: .other, inlineScriptLineCount: 1,
                                               programSequence: "python3 <<heredoc")
    let record = ShellCommandRecord(event: event, classification: classification, classifierVersion: 1)

    #expect(record.characterCount == command.count)
    #expect(record.lineCount == 3)
    let encoded = String(decoding: try JSONEncoder().encode(record), as: UTF8.self)
    #expect(!encoded.contains("secret-token"))
    #expect(!encoded.contains("print("))
}
