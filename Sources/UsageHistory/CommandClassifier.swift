import Foundation

public enum CommandClassifier {
    public static let version = 2

    public static func classify(_ command: String) -> CommandClassification {
        let elements = ShellParser(command).parse()

        var searchProgram = SearchProgram.none
        var pipesIntoHeadOrTail = false
        var runsGitStatus = false
        var runsGitCommit = false
        var runsSavedScript = false
        var inlineScript: (interpreter: InlineInterpreter, body: String)?
        var programSequence = ""
        var pendingSeparator: Separator?
        var pipelineCommands: [ParsedCommand] = []

        for element in elements {
            switch element {
            case .separator(let separator):
                switch separator {
                case .group:
                    break
                case .newline:
                    if pendingSeparator == nil { pendingSeparator = .newline }
                default:
                    pendingSeparator = separator
                }
            case .command(let command):
                guard let invocation = Invocation(command) else { continue }
                var readsPipe = false
                if programSequence.isEmpty {
                    pipelineCommands = []
                } else {
                    let separator = pendingSeparator ?? .sequence
                    readsPipe = separator == .pipe
                    if separator != .pipe { pipelineCommands = [] }
                    programSequence += separator.rendered
                    if separator == .pipe, invocation.program == "head" || invocation.program == "tail" {
                        pipesIntoHeadOrTail = true
                    }
                }
                programSequence += invocation.display
                pendingSeparator = nil

                let readsStandardInput = readsPipe || invocation.command.standardInputBody != nil
                if searchProgram == .none, invocation.searchesFiles(readsStandardInput: readsStandardInput) {
                    searchProgram = invocation.searchProgram
                }
                if invocation.program == "git" {
                    let subcommand = gitSubcommand(invocation.arguments)
                    if subcommand == "status" { runsGitStatus = true }
                    if subcommand == "commit" { runsGitCommit = true }
                }
                if let interpreter = invocation.interpreter {
                    let pipedBody = pipelineCommands.reversed().lazy.compactMap(\.standardInputBody).first
                    switch interpreterInput(interpreter, invocation: invocation, pipedBody: pipedBody) {
                    case .inline(let body):
                        if inlineScript == nil { inlineScript = (interpreter, body) }
                    case .savedScript:
                        runsSavedScript = true
                    case .none:
                        break
                    }
                }
                pipelineCommands.append(command)
            }
        }

        let isInlinePython = inlineScript?.interpreter == .python
        return CommandClassification(
            searchProgram: searchProgram,
            pipesIntoHeadOrTail: pipesIntoHeadOrTail,
            runsGitStatus: runsGitStatus,
            runsGitCommit: runsGitCommit,
            inlineInterpreter: inlineScript?.interpreter ?? .none,
            runsSavedScript: runsSavedScript,
            inlineScriptPurpose: isInlinePython ? inlineScript.map { PythonSource($0.body).purpose } : nil,
            inlineScriptLineCount: inlineScript.map { lineCount(of: $0.body) },
            programSequence: programSequence)
    }
}

// MARK: - Program resolution

private struct Invocation {
    let program: String?
    let display: String
    let arguments: ArraySlice<ShellWord>
    let command: ParsedCommand

    init?(_ command: ParsedCommand) {
        var words = command.words[...]
        stripping: while let first = words.first {
            if first.isAssignment {
                words.removeFirst()
                continue
            }
            if first.isUnquoted {
                if shellKeywords.contains(first.text) {
                    words.removeFirst()
                    continue
                }
                if compoundHeaderKeywords.contains(first.text) { return nil }
            }
            switch Self.identity(of: first).program {
            case "sudo":
                words.removeFirst()
                skipOptions(&words, takingArguments: [
                    "-u", "--user", "-g", "--group", "-h", "--host", "-p", "--prompt", "-C", "--close-from",
                    "-D", "--chdir", "-R", "--chroot", "-r", "--role", "-t", "--type", "-T", "--command-timeout",
                    "-U", "--other-user"
                ])
            case "env":
                words.removeFirst()
                skipOptions(&words, takingArguments: ["-u", "--unset", "-C", "--chdir", "-S", "--split-string"])
            case "time":
                words.removeFirst()
                skipOptions(&words, takingArguments: ["-f", "--format", "-o", "--output"])
            case "command":
                let options = words.dropFirst().prefix { $0.text.hasPrefix("-") }
                if options.contains(where: { $0.text.contains("v") || $0.text.contains("V") }) { break stripping }
                words.removeFirst()
                skipOptions(&words, takingArguments: [])
            default:
                break stripping
            }
        }
        guard let programWord = words.popFirst() else { return nil }

        let identity = Self.identity(of: programWord)
        var display = identity.display
        if let subcommand = Self.allowListedSubcommand(program: identity.program, arguments: words) {
            display += " " + subcommand
        }
        for redirection in command.redirections {
            switch redirection.kind {
            case .hereDocument: display += " <<heredoc"
            case .hereString: display += " <<<string"
            case .input, .other: break
            }
        }
        program = identity.program
        self.display = display
        arguments = words
        self.command = command
    }

    var searchProgram: SearchProgram {
        switch program {
        case "grep", "egrep", "fgrep": .grep
        case "rg": .ripgrep
        default: .none
        }
    }

    func searchesFiles(readsStandardInput: Bool) -> Bool {
        let optionsTakingArguments: Set<String>
        switch searchProgram {
        case .grep: optionsTakingArguments = grepOptionsTakingArguments
        case .ripgrep: optionsTakingArguments = ripgrepOptionsTakingArguments
        case .none: return false
        }
        var remaining = arguments
        var patternIsOption = false
        var isRecursiveGrep = false
        var operands: [String] = []
        while let argument = remaining.popFirst() {
            let text = argument.text
            if text == "--" {
                operands += remaining.map(\.text)
                break
            }
            guard text.hasPrefix("-"), text != "-" else {
                operands.append(text)
                continue
            }
            if text.hasPrefix("--") {
                let name = text.split(separator: "=", maxSplits: 1).first.map(String.init) ?? text
                if patternOptions.contains(name) { patternIsOption = true }
                if searchProgram == .grep, recursiveGrepOptions.contains(name) { isRecursiveGrep = true }
                if optionsTakingArguments.contains(text) { _ = remaining.popFirst() }
                continue
            }
            var group = text.dropFirst()
            while let letter = group.popFirst() {
                let option = "-" + String(letter)
                if searchProgram == .grep, recursiveGrepOptions.contains(option) { isRecursiveGrep = true }
                guard optionsTakingArguments.contains(option) else { continue }
                if patternOptions.contains(option) { patternIsOption = true }
                if group.isEmpty { _ = remaining.popFirst() }
                break
            }
        }
        let paths = operands.dropFirst(patternIsOption ? 0 : 1)
        if paths.contains(where: { $0 != "-" }) { return true }
        if !paths.isEmpty { return false }
        return isRecursiveGrep || !readsStandardInput
    }

    var interpreter: InlineInterpreter? {
        guard let program else { return nil }
        if isPythonName(program) { return .python }
        if program == "node" { return .javascript }
        return nil
    }

    private static func identity(of word: ShellWord) -> (program: String?, display: String) {
        guard word.isLiteral, let name = word.text.split(separator: "/").last.map(String.init),
              isAllowListedProgram(name) else { return (nil, "<other>") }
        return (name, name)
    }

    private static func allowListedSubcommand(program: String?, arguments: ArraySlice<ShellWord>) -> String? {
        let subcommand: String?
        let allowed: Set<String>
        switch program {
        case "git":
            subcommand = gitSubcommand(arguments)
            allowed = ["status", "commit", "diff", "log", "add", "push", "pull", "checkout", "switch", "rebase", "grep"]
        case "npm":
            subcommand = firstOperand(arguments, optionsTakingArguments: ["--prefix", "-w", "--workspace"])
            allowed = ["run", "test"]
        case "swift":
            subcommand = firstOperand(arguments, optionsTakingArguments: [])
            allowed = ["build", "test"]
        case "cargo":
            subcommand = firstOperand(arguments.drop { $0.text.hasPrefix("+") },
                                      optionsTakingArguments: ["--config", "-Z", "--color", "-C"])
            allowed = ["build", "test"]
        default:
            return nil
        }
        guard let subcommand, allowed.contains(subcommand) else { return nil }
        return subcommand
    }
}

private let shellKeywords: Set<String> = [
    "!", "{", "}", "if", "then", "else", "elif", "fi", "do", "done", "while", "until", "esac"
]

private let compoundHeaderKeywords: Set<String> = ["for", "select", "function"]

private let patternOptions: Set<String> = ["-e", "-f", "--regexp", "--file"]

private let recursiveGrepOptions: Set<String> = ["-r", "-R", "--recursive", "--dereference-recursive"]

private let grepOptionsTakingArguments: Set<String> = [
    "-e", "-f", "-A", "-B", "-C", "-m", "-d", "-D", "--regexp", "--file", "--after-context", "--before-context",
    "--context", "--max-count", "--directories", "--devices", "--label", "--include", "--exclude", "--exclude-dir",
    "--binary-files"
]

private let ripgrepOptionsTakingArguments: Set<String> = [
    "-e", "-f", "-g", "-t", "-T", "-A", "-B", "-C", "-m", "-M", "-j", "-r", "-E", "-d", "--regexp", "--file",
    "--glob", "--iglob", "--type", "--type-not", "--type-add", "--after-context", "--before-context", "--context",
    "--max-count", "--max-columns", "--threads", "--replace", "--encoding", "--max-depth", "--max-filesize",
    "--sort", "--sortr", "--color", "--colors", "--path-separator", "--pre", "--pre-glob", "--context-separator",
    "--field-match-separator", "--field-context-separator", "--ignore-file", "--engine", "--dfa-size-limit",
    "--regex-size-limit"
]

private func skipOptions(_ words: inout ArraySlice<ShellWord>, takingArguments: Set<String>) {
    while let option = words.first, option.text.hasPrefix("-") {
        words.removeFirst()
        if option.text == "--" { return }
        if takingArguments.contains(option.text) { _ = words.popFirst() }
    }
}

private func gitSubcommand(_ arguments: ArraySlice<ShellWord>) -> String? {
    firstOperand(arguments, optionsTakingArguments: [
        "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--super-prefix", "--config-env"
    ])
}

private func firstOperand(_ arguments: ArraySlice<ShellWord>, optionsTakingArguments: Set<String>) -> String? {
    var remaining = arguments
    while let argument = remaining.popFirst() {
        if optionsTakingArguments.contains(argument.text) {
            _ = remaining.popFirst()
        } else if !argument.text.hasPrefix("-") {
            return argument.text
        }
    }
    return nil
}

private func isPythonName(_ name: String) -> Bool {
    guard name.hasPrefix("python") else { return false }
    let version = name.dropFirst("python".count)
    let parts = version.split(separator: ".", omittingEmptySubsequences: false)
    return parts.count <= 2 && parts.enumerated().allSatisfy { index, part in
        (index == 0 || !part.isEmpty) && part.allSatisfy(\.isASCIIDigit)
    }
}

private let allowListedPrograms: Set<String> = [
    "sh", "bash", "zsh", "fish", "dash", "cd", "pwd", "echo", "printf", "test", "[", "true", "false", "export",
    "source", ".", "exec", "exit", "read", "set", "unset", "type", "command", "wait", "trap", "pushd", "popd",
    "which",
    "sudo", "env", "time", "timeout", "nohup", "xargs", "watch", "kill", "killall", "pkill", "pgrep", "ps",
    "top", "lsof", "sleep",
    "ls", "cat", "head", "tail", "wc", "sort", "uniq", "cut", "tr", "tee", "diff", "cmp", "comm", "paste",
    "column", "basename", "dirname", "realpath", "readlink", "stat", "file", "du", "df", "find", "fd", "tree",
    "mkdir", "rmdir", "rm", "cp", "mv", "touch", "chmod", "chown", "ln", "date", "seq", "mktemp", "shasum",
    "base64", "xxd", "od", "hexdump", "strings", "less", "patch", "ditto",
    "grep", "egrep", "fgrep", "rg", "ag", "sed", "awk", "gawk", "jq", "yq", "perl",
    "tar", "zip", "unzip", "gzip", "gunzip", "zstd", "xz",
    "curl", "wget", "ssh", "scp", "rsync",
    "git", "gh", "make", "cmake", "ninja",
    "pip", "pip3", "uv", "uvx", "pytest", "node", "npm", "npx", "pnpm", "yarn", "bun", "deno", "tsc", "ruby",
    "gem", "bundle", "swift", "swiftc", "xcodebuild", "xcrun", "cargo", "rustc", "rustup", "go", "java",
    "clang", "gcc", "docker", "brew",
    "open", "osascript", "defaults", "plutil", "sqlite3", "pbcopy", "pbpaste", "launchctl", "log", "mdfind",
    "sw_vers", "uname", "codesign", "lipo", "otool", "hdiutil",
    "claude", "codex",
]

private func isAllowListedProgram(_ name: String) -> Bool {
    allowListedPrograms.contains(name) || isPythonName(name)
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isWholeNumber }
}

// MARK: - Interpreter input

private enum InterpreterInput {
    case inline(String)
    case savedScript
    case none
}

private func interpreterInput(_ interpreter: InlineInterpreter, invocation: Invocation,
                              pipedBody: String?) -> InterpreterInput {
    let operand: InterpreterOperand
    switch interpreter {
    case .python: operand = pythonOperand(invocation.arguments)
    case .javascript: operand = nodeOperand(invocation.arguments)
    case .none: return .none
    }
    switch operand {
    case .code(let code):
        return .inline(code)
    case .module:
        return .none
    case .script:
        return .savedScript
    case .standardInput:
        if let body = invocation.command.standardInputBody ?? pipedBody { return .inline(body) }
        if invocation.command.redirections.contains(where: { $0.kind == .input }) { return .savedScript }
        return .none
    }
}

private enum InterpreterOperand {
    case code(String)
    case module
    case script
    case standardInput
}

private func pythonOperand(_ arguments: ArraySlice<ShellWord>) -> InterpreterOperand {
    var remaining = arguments
    while let argument = remaining.popFirst() {
        let text = argument.text
        if text == "-" { return .standardInput }
        if text == "--" { return remaining.isEmpty ? .standardInput : .script }
        if text == "--check-hash-based-pycs" {
            _ = remaining.popFirst()
            continue
        }
        if text.hasPrefix("--") { continue }
        guard text.hasPrefix("-") else { return .script }
        var options = text.dropFirst()
        while let option = options.popFirst() {
            switch option {
            case "c":
                return .code(options.isEmpty ? remaining.first?.text ?? "" : String(options))
            case "m":
                return .module
            case "W", "X":
                if options.isEmpty { _ = remaining.popFirst() }
                options = ""
            default:
                break
            }
        }
    }
    return .standardInput
}

private func nodeOperand(_ arguments: ArraySlice<ShellWord>) -> InterpreterOperand {
    let codeOptions: Set<String> = ["-e", "--eval", "-p", "--print"]
    let optionsTakingArguments: Set<String> = [
        "-r", "--require", "--import", "--loader", "--experimental-loader", "-C", "--conditions", "--input-type",
        "--env-file", "--title", "--inspect-port", "--debug-port"
    ]
    var remaining = arguments
    while let argument = remaining.popFirst() {
        let text = argument.text
        if codeOptions.contains(text) { return .code(remaining.first?.text ?? "") }
        if let equals = text.firstIndex(of: "="), codeOptions.contains(String(text[..<equals])) {
            return .code(String(text[text.index(after: equals)...]))
        }
        if text == "-" { return .standardInput }
        if text == "--" { return remaining.isEmpty ? .standardInput : .script }
        if optionsTakingArguments.contains(text) {
            _ = remaining.popFirst()
        } else if !text.hasPrefix("-") {
            return .script
        }
    }
    return .standardInput
}

private func lineCount(of body: String) -> Int {
    let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
    let isBlank: (Substring) -> Bool = { $0.allSatisfy(\.isWhitespace) }
    guard let first = lines.firstIndex(where: { !isBlank($0) }),
          let last = lines.lastIndex(where: { !isBlank($0) }) else { return 0 }
    return last - first + 1
}

// MARK: - Inline Python purpose

private struct PythonSource {
    private struct Call {
        let receiver: String?
        let arguments: [String]
    }

    private let scalars: [Unicode.Scalar]
    private let isCode: [Bool]

    init(_ text: String) {
        let scalars = Array(text.unicodeScalars)
        var isCode = Array(repeating: true, count: scalars.count)
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "#" {
                while index < scalars.count, scalars[index] != "\n" {
                    isCode[index] = false
                    index += 1
                }
            } else if scalar == "'" || scalar == "\"" {
                let start = index
                let isTriple = index + 2 < scalars.count && scalars[index + 1] == scalar && scalars[index + 2] == scalar
                index += isTriple ? 3 : 1
                while index < scalars.count {
                    if scalars[index] == "\\" {
                        index += 2
                    } else if isTriple {
                        if index + 2 < scalars.count, scalars[index] == scalar, scalars[index + 1] == scalar,
                           scalars[index + 2] == scalar {
                            index += 3
                            break
                        }
                        index += 1
                    } else if scalars[index] == scalar {
                        index += 1
                        break
                    } else if scalars[index] == "\n" {
                        break
                    } else {
                        index += 1
                    }
                }
                for masked in start..<min(index, scalars.count) { isCode[masked] = false }
            } else {
                index += 1
            }
        }
        self.scalars = scalars
        self.isCode = isCode
    }

    var purpose: InlineScriptPurpose {
        var readTargets: Set<String> = []
        var writeTargets: Set<String> = []

        for call in calls(named: "open") {
            let target: String?
            let mode: String?
            if let receiver = call.receiver, !["io", "os", "codecs", "builtins"].contains(receiver) {
                target = receiver
                mode = Self.mode(of: call.arguments, positionalIndex: 0)
            } else {
                target = Self.argument(call.arguments, keyword: "file", position: 0)
                mode = Self.mode(of: call.arguments, positionalIndex: 1)
            }
            guard let target, let mode else { continue }
            let key = Self.normalizedTarget(target)
            if mode.contains("r") || mode.contains("+") { readTargets.insert(key) }
            if mode.contains(where: { "wax+".contains($0) }) { writeTargets.insert(key) }
        }
        for name in ["read_text", "read_bytes"] {
            for call in calls(named: name) {
                if let receiver = call.receiver { readTargets.insert(Self.normalizedTarget(receiver)) }
            }
        }
        for name in ["write_text", "write_bytes"] {
            for call in calls(named: name) {
                if let receiver = call.receiver { writeTargets.insert(Self.normalizedTarget(receiver)) }
            }
        }

        if !readTargets.isDisjoint(with: writeTargets) { return .editsFileInPlace }
        if !writeTargets.isEmpty || calls(named: "dump").contains(where: { $0.receiver == "json" }) {
            return .writesFile
        }
        if (calls(named: "load") + calls(named: "loads")).contains(where: { $0.receiver == "json" }) {
            return .readsJSON
        }
        return .other
    }

    private func calls(named name: String) -> [Call] {
        let nameScalars = Array(name.unicodeScalars)
        var result: [Call] = []
        var index = 0
        while index + nameScalars.count <= scalars.count {
            defer { index += 1 }
            let end = index + nameScalars.count
            guard isCode[index], Array(scalars[index..<end]) == nameScalars,
                  index == 0 || !Self.isIdentifierScalar(scalars[index - 1]),
                  end == scalars.count || !Self.isIdentifierScalar(scalars[end]) else { continue }
            var open = end
            while open < scalars.count, scalars[open] == " " { open += 1 }
            guard open < scalars.count, scalars[open] == "(", isCode[open] else { continue }

            var dot = index - 1
            while dot >= 0, scalars[dot] == " " { dot -= 1 }
            let receiver = dot >= 0 && scalars[dot] == "." && isCode[dot] ? receiverExpression(before: dot) : nil
            result.append(Call(receiver: receiver, arguments: arguments(openingAt: open)))
        }
        return result
    }

    private func arguments(openingAt open: Int) -> [String] {
        var arguments: [String] = []
        var depth = 0
        var start = open + 1
        for index in open..<scalars.count where isCode[index] {
            switch scalars[index] {
            case "(", "[", "{":
                depth += 1
            case ")", "]", "}":
                depth -= 1
                if depth == 0 {
                    arguments.append(text(start..<index))
                    return arguments.filter { !$0.isEmpty }
                }
            case "," where depth == 1:
                arguments.append(text(start..<index))
                start = index + 1
            default:
                break
            }
        }
        arguments.append(text(start..<scalars.count))
        return arguments.filter { !$0.isEmpty }
    }

    private func receiverExpression(before dot: Int) -> String? {
        var index = dot - 1
        while index >= 0, scalars[index] == " " { index -= 1 }
        let end = index + 1
        while index >= 0, isCode[index] {
            let scalar = scalars[index]
            if scalar == ")" || scalar == "]" {
                var depth = 0
                while index >= 0 {
                    if isCode[index] {
                        if scalars[index] == ")" || scalars[index] == "]" { depth += 1 }
                        if scalars[index] == "(" || scalars[index] == "[" { depth -= 1 }
                    }
                    index -= 1
                    if depth == 0 { break }
                }
            } else if Self.isIdentifierScalar(scalar) || scalar == "." {
                index -= 1
            } else {
                break
            }
        }
        let receiver = text(index + 1..<end)
        return receiver.isEmpty ? nil : receiver
    }

    private func text(_ range: Range<Int>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars[range])
        return String(view).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func argument(_ arguments: [String], keyword: String, position: Int) -> String? {
        var positional: [String] = []
        for argument in arguments {
            if let (name, value) = keywordArgument(argument) {
                if name == keyword { return value }
            } else {
                positional.append(argument)
            }
        }
        return position < positional.count ? positional[position] : nil
    }

    private static func mode(of arguments: [String], positionalIndex: Int) -> String? {
        guard let mode = argument(arguments, keyword: "mode", position: positionalIndex) else { return "r" }
        return literalValue(mode)
    }

    private static func keywordArgument(_ argument: String) -> (String, String)? {
        guard let equals = argument.firstIndex(of: "=") else { return nil }
        let name = argument[..<equals].trimmingCharacters(in: .whitespaces)
        let value = argument[argument.index(after: equals)...]
        guard !name.isEmpty, !value.hasPrefix("="),
              name.unicodeScalars.allSatisfy(isIdentifierScalar),
              !(name.first?.isNumber ?? true) else { return nil }
        return (name, value.trimmingCharacters(in: .whitespaces))
    }

    private static func normalizedTarget(_ expression: String) -> String {
        var target = expression.filter { !$0.isWhitespace }
        unwrapping: while true {
            for wrapper in ["pathlib.Path(", "Path("] where target.hasPrefix(wrapper) && target.hasSuffix(")") {
                target = String(target.dropFirst(wrapper.count).dropLast())
                continue unwrapping
            }
            break
        }
        if let literal = literalValue(target) { return "literal:" + literal }
        return target
    }

    private static func literalValue(_ expression: String) -> String? {
        let body = expression.drop { "rRbBuU".contains($0) }
        for quote in ["\"\"\"", "'''", "\"", "'"] where body.count >= 2 * quote.count
            && body.hasPrefix(quote) && body.hasSuffix(quote) {
            return String(body.dropFirst(quote.count).dropLast(quote.count))
        }
        return nil
    }

    private static func isIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || scalar.properties.isAlphabetic || ("0"..."9").contains(scalar)
    }
}

// MARK: - Shell parsing

private struct ShellWord {
    var text = ""
    var isLiteral = true
    var isUnquoted = true
    var unquotedPrefix = ""

    var isAssignment: Bool {
        guard let equals = unquotedPrefix.firstIndex(of: "=") else { return false }
        var name = unquotedPrefix[..<equals]
        if name.hasSuffix("+") { name = name.dropLast() }
        guard let first = name.unicodeScalars.first, first == "_" || first.properties.isAlphabetic else {
            return false
        }
        return name.unicodeScalars.allSatisfy { $0 == "_" || $0.isASCII && $0.properties.isAlphabetic
            || ("0"..."9").contains($0) }
    }
}

private enum RedirectionKind: Equatable {
    case input
    case hereDocument(stripsTabs: Bool)
    case hereString
    case other
}

private final class Redirection {
    let kind: RedirectionKind
    var body: String?

    init(kind: RedirectionKind) {
        self.kind = kind
    }
}

private final class ParsedCommand {
    var words: [ShellWord] = []
    var redirections: [Redirection] = []

    var isEmpty: Bool { words.isEmpty && redirections.isEmpty }

    var standardInputBody: String? {
        redirections.last { $0.kind != .other }?.body
    }
}

private enum Separator: Equatable {
    case pipe
    case and
    case or
    case sequence
    case background
    case newline
    case group

    var rendered: String {
        switch self {
        case .pipe: " | "
        case .and: " && "
        case .or: " || "
        case .sequence, .newline, .group: "; "
        case .background: " & "
        }
    }
}

private enum ShellElement {
    case command(ParsedCommand)
    case separator(Separator)
}

private final class ShellParser {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    private var pendingHereDocuments: [(delimiter: String, stripsTabs: Bool, redirection: Redirection)] = []

    init(_ text: String) {
        scalars = Array(text.unicodeScalars)
    }

    func parse() -> [ShellElement] {
        let elements = parseList(isNested: false)
        for pending in pendingHereDocuments { pending.redirection.body = "" }
        pendingHereDocuments = []
        return elements
    }

    private var current: Unicode.Scalar? { index < scalars.count ? scalars[index] : nil }

    private func scalar(at offset: Int) -> Unicode.Scalar? {
        index + offset < scalars.count ? scalars[index + offset] : nil
    }

    private func parseList(isNested: Bool) -> [ShellElement] {
        var elements: [ShellElement] = []
        var command = ParsedCommand()
        var redirectionAwaitingTarget: Redirection?
        var depth = 0
        var openCaseCount = 0

        func separate(_ separator: Separator) {
            if !command.isEmpty { elements.append(.command(command)) }
            command = ParsedCommand()
            redirectionAwaitingTarget = nil
            elements.append(.separator(separator))
        }

        while let scalar = current {
            switch scalar {
            case " ", "\t", "\r":
                index += 1
            case "\n":
                index += 1
                separate(.newline)
                readHereDocumentBodies()
            case "#":
                while let next = current, next != "\n" { index += 1 }
            case ";":
                index += 1
                let endsCaseArm = current == ";" || current == "&"
                if endsCaseArm { index += 1 }
                if endsCaseArm, current == "&" { index += 1 }
                separate(.sequence)
                if endsCaseArm, openCaseCount > 0, !skipCasePattern() { openCaseCount -= 1 }
            case "|":
                index += 1
                if current == "|" {
                    index += 1
                    separate(.or)
                } else {
                    if current == "&" { index += 1 }
                    separate(.pipe)
                }
            case "&":
                index += 1
                if current == "&" {
                    index += 1
                    separate(.and)
                } else if current == ">" {
                    index += 1
                    if current == ">" { index += 1 }
                    redirectionAwaitingTarget = addRedirection(.other, to: command)
                } else {
                    separate(.background)
                }
            case "(":
                index += 1
                depth += 1
                separate(.group)
            case ")":
                index += 1
                if depth > 0 {
                    depth -= 1
                    separate(.group)
                } else if isNested {
                    if !command.isEmpty { elements.append(.command(command)) }
                    return elements
                } else {
                    command = ParsedCommand()
                    redirectionAwaitingTarget = nil
                }
            case "<", ">":
                if self.scalar(at: 1) == "(" {
                    index += 2
                    _ = parseList(isNested: true)
                    command.words.append(ShellWord(text: "", isLiteral: false, isUnquoted: false))
                } else {
                    redirectionAwaitingTarget = readRedirectionOperator(into: command)
                }
            default:
                let word = readWord()
                if let redirection = redirectionAwaitingTarget {
                    redirectionAwaitingTarget = nil
                    switch redirection.kind {
                    case .hereDocument(let stripsTabs):
                        pendingHereDocuments.append((word.text, stripsTabs, redirection))
                    case .hereString:
                        redirection.body = word.text
                    case .input, .other:
                        break
                    }
                } else if word.isUnquoted, word.text == "case", isInCommandPosition(command) {
                    skipCaseSubject()
                    separate(.group)
                    if skipCasePattern() { openCaseCount += 1 }
                } else if !isRedirectionFileDescriptor(word) {
                    if word.isUnquoted, word.text == "esac", openCaseCount > 0, isInCommandPosition(command) {
                        openCaseCount -= 1
                    }
                    command.words.append(word)
                }
            }
        }
        if !command.isEmpty { elements.append(.command(command)) }
        return elements
    }

    private func isRedirectionFileDescriptor(_ word: ShellWord) -> Bool {
        word.isUnquoted && word.text.allSatisfy(\.isASCIIDigit) && (current == "<" || current == ">")
    }

    private func isInCommandPosition(_ command: ParsedCommand) -> Bool {
        command.redirections.isEmpty && command.words.allSatisfy { $0.isUnquoted && shellKeywords.contains($0.text) }
    }

    private func skipCaseSubject() {
        var hasSubject = false
        while let scalar = current {
            switch scalar {
            case " ", "\t", "\r", "\n":
                index += 1
            default:
                let start = index
                let word = readWord()
                if index == start { index += 1 }
                if hasSubject, word.isUnquoted, word.text == "in" { return }
                hasSubject = true
            }
        }
    }

    private func skipCasePattern() -> Bool {
        var isAtPatternStart = true
        while let scalar = current {
            switch scalar {
            case " ", "\t", "\r":
                index += 1
            case "\n":
                index += 1
                readHereDocumentBodies()
            case "#" where isAtPatternStart:
                while let next = current, next != "\n" { index += 1 }
            case "(", "|":
                index += 1
                isAtPatternStart = false
            case ")":
                index += 1
                return true
            default:
                let start = index
                let word = readWord()
                if index == start { index += 1 }
                if isAtPatternStart, word.isUnquoted, word.text == "esac" { return false }
                isAtPatternStart = false
            }
        }
        return false
    }

    private func addRedirection(_ kind: RedirectionKind, to command: ParsedCommand) -> Redirection {
        let redirection = Redirection(kind: kind)
        command.redirections.append(redirection)
        return redirection
    }

    private func readRedirectionOperator(into command: ParsedCommand) -> Redirection {
        let isInput = current == "<"
        index += 1
        guard isInput else {
            if current == ">" || current == "|" || current == "&" { index += 1 }
            return addRedirection(.other, to: command)
        }
        switch current {
        case "<":
            index += 1
            if current == "<" {
                index += 1
                return addRedirection(.hereString, to: command)
            }
            let stripsTabs = current == "-"
            if stripsTabs { index += 1 }
            return addRedirection(.hereDocument(stripsTabs: stripsTabs), to: command)
        case "&", ">":
            index += 1
            return addRedirection(.other, to: command)
        default:
            return addRedirection(.input, to: command)
        }
    }

    private func readHereDocumentBodies() {
        let pending = pendingHereDocuments
        pendingHereDocuments = []
        for hereDocument in pending {
            var lines: [String] = []
            while index < scalars.count {
                let start = index
                while index < scalars.count, scalars[index] != "\n" { index += 1 }
                var line = String.UnicodeScalarView()
                line.append(contentsOf: scalars[start..<index])
                if index < scalars.count { index += 1 }
                var text = String(line)
                if hereDocument.stripsTabs { text = String(text.drop { $0 == "\t" }) }
                if text.hasSuffix("\r") { text.removeLast() }
                if text == hereDocument.delimiter { break }
                lines.append(text)
            }
            hereDocument.redirection.body = lines.joined(separator: "\n")
        }
    }

    private func readWord() -> ShellWord {
        var word = ShellWord()
        var isPrefixOpen = true

        func closePrefix(quoted: Bool) {
            isPrefixOpen = false
            if quoted { word.isUnquoted = false }
        }

        while let scalar = current {
            switch scalar {
            case "(" where isPrefixOpen && word.isAssignment && word.unquotedPrefix.hasSuffix("="):
                let start = index
                index += 1
                _ = parseList(isNested: true)
                appendSource(from: start, to: &word)
                closePrefix(quoted: false)
                word.isLiteral = false
            case " ", "\t", "\r", "\n", ";", "&", "|", "<", ">", "(", ")":
                return word
            case "\\":
                closePrefix(quoted: true)
                index += 1
                if let escaped = current {
                    index += 1
                    if escaped != "\n" { word.text.unicodeScalars.append(escaped) }
                }
            case "'":
                closePrefix(quoted: true)
                index += 1
                while let next = current, next != "'" {
                    word.text.unicodeScalars.append(next)
                    index += 1
                }
                index += 1
            case "\"":
                closePrefix(quoted: true)
                index += 1
                readDoubleQuoted(into: &word)
            case "$":
                closePrefix(quoted: false)
                readDollar(into: &word, isInDoubleQuotes: false)
            case "`":
                closePrefix(quoted: false)
                readBackquote(into: &word)
            default:
                word.text.unicodeScalars.append(scalar)
                if isPrefixOpen { word.unquotedPrefix.unicodeScalars.append(scalar) }
                index += 1
            }
        }
        return word
    }

    private func readDoubleQuoted(into word: inout ShellWord) {
        while let scalar = current {
            switch scalar {
            case "\"":
                index += 1
                return
            case "\\":
                if let escaped = self.scalar(at: 1), "$`\"\\\n".unicodeScalars.contains(escaped) {
                    index += 2
                    if escaped != "\n" { word.text.unicodeScalars.append(escaped) }
                } else {
                    word.text.unicodeScalars.append(scalar)
                    index += 1
                }
            case "$":
                readDollar(into: &word, isInDoubleQuotes: true)
            case "`":
                readBackquote(into: &word)
            default:
                word.text.unicodeScalars.append(scalar)
                index += 1
            }
        }
    }

    private func readDollar(into word: inout ShellWord, isInDoubleQuotes: Bool) {
        let start = index
        index += 1
        switch current {
        case "(":
            index += 1
            _ = parseList(isNested: true)
            word.isLiteral = false
            appendSource(from: start, to: &word)
        case "{":
            var depth = 0
            while let scalar = current {
                index += 1
                if scalar == "{" { depth += 1 }
                if scalar == "}" {
                    depth -= 1
                    if depth == 0 { break }
                }
            }
            word.isLiteral = false
            appendSource(from: start, to: &word)
        case "'" where !isInDoubleQuotes:
            word.isUnquoted = false
            index += 1
            while let scalar = current, scalar != "'" {
                if scalar == "\\", let escaped = self.scalar(at: 1) {
                    word.text.unicodeScalars.append(escaped == "n" ? "\n" : escaped == "t" ? "\t" : escaped)
                    index += 2
                } else {
                    word.text.unicodeScalars.append(scalar)
                    index += 1
                }
            }
            index += 1
        case let scalar? where scalar == "_" || scalar.properties.isAlphabetic:
            while let next = current, next == "_" || next.properties.isAlphabetic || ("0"..."9").contains(next) {
                index += 1
            }
            word.isLiteral = false
            appendSource(from: start, to: &word)
        case let scalar? where "0123456789?#@*!$-".unicodeScalars.contains(scalar):
            index += 1
            word.isLiteral = false
            appendSource(from: start, to: &word)
        default:
            word.text.unicodeScalars.append("$")
        }
    }

    private func readBackquote(into word: inout ShellWord) {
        let start = index
        index += 1
        while let scalar = current, scalar != "`" {
            index += scalar == "\\" ? 2 : 1
        }
        index = min(index + 1, scalars.count)
        word.isLiteral = false
        appendSource(from: start, to: &word)
    }

    private func appendSource(from start: Int, to word: inout ShellWord) {
        word.text.unicodeScalars.append(contentsOf: scalars[start..<min(index, scalars.count)])
    }
}
