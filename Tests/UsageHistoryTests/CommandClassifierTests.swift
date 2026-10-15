import Testing
import UsageHistory

struct ClassifierCase: Sendable, CustomTestStringConvertible {
    let name: String
    let command: String
    let expected: CommandClassification

    var testDescription: String { name }

    init(_ name: String, _ command: String, search: SearchProgram = .none, pipesIntoHeadOrTail: Bool = false,
         gitStatus: Bool = false, gitCommit: Bool = false, interpreter: InlineInterpreter = .none,
         savedScript: Bool = false, purpose: InlineScriptPurpose? = nil, lines: Int? = nil, sequence: String) {
        self.name = name
        self.command = command
        expected = CommandClassification(
            searchProgram: search, pipesIntoHeadOrTail: pipesIntoHeadOrTail, runsGitStatus: gitStatus,
            runsGitCommit: gitCommit, inlineInterpreter: interpreter, runsSavedScript: savedScript,
            inlineScriptPurpose: purpose, inlineScriptLineCount: lines, programSequence: sequence)
    }
}

let classifierCases: [ClassifierCase] = [
    // Quoted text and here-document bodies are never programs.
    ClassifierCase("quoted pipeline is an argument", #"echo "grep | head""#, sequence: "echo"),
    ClassifierCase("single-quoted pipeline is an argument", "echo 'rg x | tail' && ls", sequence: "echo && ls"),
    ClassifierCase("grep inside a here-document body", "cat <<EOF > notes.txt\ngrep -r x . | head\nEOF",
                   sequence: "cat <<heredoc"),
    ClassifierCase("grep inside a commit message substitution",
                   "git commit -m \"$(cat <<'EOF'\nUse grep | head less\n\nEOF\n)\"",
                   gitCommit: true, sequence: "git commit"),
    ClassifierCase("escaped pipe is an argument", #"echo a \| grep b"#, sequence: "echo"),

    // Search programs and pipes.
    ClassifierCase("ripgrep piped into head", "rg -n x | head -20", search: .ripgrep, pipesIntoHeadOrTail: true,
                   sequence: "rg | head"),
    ClassifierCase("grep piped into tail", "grep -rn 'TODO' Sources | tail -5", search: .grep,
                   pipesIntoHeadOrTail: true, sequence: "grep | tail"),
    ClassifierCase("egrep and fgrep are grep", "egrep x f; fgrep y f", search: .grep, sequence: "egrep; fgrep"),
    ClassifierCase("grep through a path", "/usr/bin/grep -c x f", search: .grep, sequence: "grep"),
    ClassifierCase("git grep is not a search program", "git grep -n needle", sequence: "git grep"),
    ClassifierCase("head without a pipe", "head -5 f && tail f", sequence: "head && tail"),
    ClassifierCase("pipe continued on the next line", "ls |\n  head", pipesIntoHeadOrTail: true,
                   sequence: "ls | head"),
    ClassifierCase("pipe after a loop", "for f in *.swift; do\n  grep -c x \"$f\"\ndone | head",
                   search: .grep, pipesIntoHeadOrTail: true, sequence: "grep | head"),

    // Only a file search counts. A search that reads a pipe, here-string, or here-document is a filter.
    ClassifierCase("grep filtering git output", "git log | grep x", sequence: "git log | grep"),
    ClassifierCase("grep filtering cat output", "cat f | grep x", sequence: "cat | grep"),
    ClassifierCase("grep reading a here-string", #"grep x <<< "$v""#, sequence: "grep <<<string"),
    ClassifierCase("recursive grep searches files", "grep -r x .", search: .grep, sequence: "grep"),
    ClassifierCase("ripgrep piped into head searches files", "rg x src | head", search: .ripgrep,
                   pipesIntoHeadOrTail: true, sequence: "rg | head"),
    ClassifierCase("ripgrep then grep filter", "rg x | grep y", search: .ripgrep, sequence: "rg | grep"),
    ClassifierCase("piped grep with a path searches the path", "git diff | grep x file.swift", search: .grep,
                   sequence: "git diff | grep"),
    ClassifierCase("ripgrep with a path ignores a here-string", #"rg x Sources <<< "$t""#, search: .ripgrep,
                   sequence: "rg <<<string"),
    ClassifierCase("option value is not a path", "ps | grep -A 2 x", sequence: "ps | grep"),
    ClassifierCase("pattern option and stdin operand", "git log | grep -e x -", sequence: "git log | grep"),
    ClassifierCase("attached pattern option with a path", "git log | rg -eneedle Sources", search: .ripgrep,
                   sequence: "git log | rg"),
    ClassifierCase("attached option value is not a path", "ps | grep -A2 x", sequence: "ps | grep"),
    ClassifierCase("explicit standard input operand", "grep -e needle -; rg needle -", sequence: "grep; rg"),
    ClassifierCase("piped recursive grep searches the directory", "git log | grep -rn needle", search: .grep,
                   sequence: "git log | grep"),

    // Git.
    ClassifierCase("git status with a directory option", "git -C repo status --short", gitStatus: true,
                   sequence: "git status"),
    ClassifierCase("git status then commit", "git status && git commit -am 'msg'", gitStatus: true,
                   gitCommit: true, sequence: "git status && git commit"),
    ClassifierCase("git config option before commit", "git -c user.name=x --no-pager commit -m y",
                   gitCommit: true, sequence: "git commit"),
    ClassifierCase("cd before git", "cd ~/src/app && git status", gitStatus: true, sequence: "cd && git status"),
    ClassifierCase("unlisted git subcommand", "git stash pop", sequence: "git"),

    // Wrappers.
    ClassifierCase("assignment, sudo, env, and time are stripped",
                   "FOO=1 sudo -u admin env -i BAR=2 time -p rg x", search: .ripgrep, sequence: "rg"),
    ClassifierCase("allow-listed build tools", "swift build -c release; npm run lint || cargo test --all",
                   sequence: "swift build; npm run || cargo test"),
    ClassifierCase("sudo long option value is not the program", "sudo --user git rg needle", search: .ripgrep,
                   sequence: "rg"),
    ClassifierCase("cargo option value is not the subcommand", "cargo +nightly --config test build",
                   sequence: "cargo build"),
    ClassifierCase("command runs its operand", "command rg needle | head", search: .ripgrep,
                   pipesIntoHeadOrTail: true, sequence: "rg | head"),
    ClassifierCase("command -v only looks a name up", "command -v rg", sequence: "command"),
    ClassifierCase("conditional keyword", "if grep -q x f; then echo y; fi", search: .grep,
                   sequence: "grep; echo"),

    // Inline Python purposes.
    ClassifierCase("python heredoc that edits a file in place",
                   "python3 - <<'EOF'\np = 'Sources/App.swift'\ns = open(p).read()\nopen(p, 'w').write(s.replace('a', 'b'))\nEOF",
                   interpreter: .python, purpose: .editsFileInPlace, lines: 3, sequence: "python3 <<heredoc"),
    ClassifierCase("python heredoc that edits a path in place",
                   "python3 <<EOF\nfrom pathlib import Path\npath = Path(\"a.txt\")\ntext = path.read_text()\npath.write_text(text.upper())\nEOF",
                   interpreter: .python, purpose: .editsFileInPlace, lines: 4, sequence: "python3 <<heredoc"),
    ClassifierCase("python heredoc that writes a file",
                   "python3 - <<'EOF'\nimport json\ndata = {'a': 1}\nwith open('out.json', 'w') as f:\n    json.dump(data, f)\nEOF",
                   interpreter: .python, purpose: .writesFile, lines: 4, sequence: "python3 <<heredoc"),
    ClassifierCase("python heredoc that reads JSON",
                   "python3 - <<'EOF'\nimport json\nwith open('package.json') as f:\n    print(json.load(f)['name'])\nEOF",
                   interpreter: .python, purpose: .readsJSON, lines: 3, sequence: "python3 <<heredoc"),
    ClassifierCase("python heredoc with another purpose",
                   "python3 - <<'EOF'\n# open('x', 'w') in a comment\nprint(\"json.load(\")\nprint(sum(range(10)))\nEOF",
                   interpreter: .python, purpose: .other, lines: 3, sequence: "python3 <<heredoc"),
    ClassifierCase("python stripping heredoc", "\tpython3 <<-EOF\n\tprint(1)\n\tEOF\necho done",
                   interpreter: .python, purpose: .other, lines: 1, sequence: "python3 <<heredoc; echo"),
    ClassifierCase("heredoc piped into python", "cat <<'EOF' | python3\nimport json\nprint(json.loads('{}'))\nEOF",
                   interpreter: .python, purpose: .readsJSON, lines: 2, sequence: "cat <<heredoc | python3"),
    ClassifierCase("python -c", #"python3 -c "import sys; print(sys.version)""#, interpreter: .python,
                   purpose: .other, lines: 1, sequence: "python3"),
    ClassifierCase("python long option value is not a script",
                   "python3 --check-hash-based-pycs always -c 'print(1)'", interpreter: .python, purpose: .other,
                   lines: 1, sequence: "python3"),
    ClassifierCase("multi-line python -c", "python3 -c '\nimport json\nprint(json.load(open(\"a.json\")))\n'",
                   interpreter: .python, purpose: .readsJSON, lines: 2, sequence: "python3"),
    ClassifierCase("versioned python through a path", ".venv/bin/python3.12 -c 'print(1)'", interpreter: .python,
                   purpose: .other, lines: 1, sequence: "python3.12"),

    // JavaScript and saved scripts.
    ClassifierCase("node option value is not a script",
                   "node --input-type module --inspect-port 9229 -e 'console.log(1)'",
                   interpreter: .javascript, lines: 1, sequence: "node"),
    ClassifierCase("last input redirection wins", "python3 <<EOF < tool.py\nprint(1)\nEOF", savedScript: true,
                   sequence: "python3 <<heredoc"),
    ClassifierCase("node -e", "node -e 'console.log(1)\nconsole.log(2)'", interpreter: .javascript, lines: 2,
                   sequence: "node"),
    ClassifierCase("node heredoc", "node - <<'EOF'\nconsole.log(require('fs').readdirSync('.'))\nEOF",
                   interpreter: .javascript, lines: 1, sequence: "node <<heredoc"),
    ClassifierCase("python saved script", "python3 scripts/report.py --out x.json", savedScript: true,
                   sequence: "python3"),
    ClassifierCase("node saved script", "node build.js", savedScript: true, sequence: "node"),
    ClassifierCase("python script reading a heredoc as data", "python3 tool.py <<EOF\nprint(1)\nEOF",
                   savedScript: true, sequence: "python3 <<heredoc"),
    ClassifierCase("python module is neither", "python3 -m pytest -q", sequence: "python3"),
    ClassifierCase("script written then run", "cat > /tmp/x.py <<'EOF'\nprint(1)\nEOF\npython3 /tmp/x.py",
                   savedScript: true, sequence: "cat <<heredoc; python3"),

    // Privacy: arguments, paths, and strings never reach the program sequence.
    ClassifierCase("secret-looking token is dropped",
                   "GITHUB_TOKEN=ghp_abc123SECRET curl -H 'Authorization: Bearer sk-ant-api03-SECRET' https://api.example.com | head",
                   pipesIntoHeadOrTail: true, sequence: "curl | head"),
    ClassifierCase("local script path is a placeholder", "./scripts/deploy-acme-prod.sh --token=hunter2",
                   sequence: "<other>"),
    ClassifierCase("expanded program is a placeholder", "$EDITOR ~/private/notes.txt", sequence: "<other>"),
    ClassifierCase("unlisted program is a placeholder", "hunter2 --login && ls", sequence: "<other> && ls"),
    ClassifierCase("case patterns are not programs",
                   "case \"$token\" in\nhunter2|ghp_live_SECRET) echo matched;;\n(*) rg x | head;;\nesac",
                   search: .ripgrep, pipesIntoHeadOrTail: true, sequence: "echo; rg | head"),
    ClassifierCase("one-line case with several arms", "case $1 in start) make;; hunter2|stop) kill 1;; esac; ls",
                   sequence: "make; kill; ls"),
    ClassifierCase("case inside a command substitution",
                   "mode=$(case $x in hunter2|b) echo y;; esac) && ls", sequence: "ls"),
    ClassifierCase("empty command", "  \n", sequence: ""),
]

@Test(arguments: classifierCases)
func classifiesCommand(_ testCase: ClassifierCase) {
    #expect(CommandClassifier.classify(testCase.command) == testCase.expected)
}

@Test func programSequenceNeverContainsArgumentText() {
    let secrets = ["ghp_abc123SECRET", "sk-ant-api03-SECRET", "ghp_live_SECRET", "deploy-acme-prod", "hunter2",
                   "private", "notes", "api.example.com", "Sources/App.swift", "a.txt", "msg"]
    for testCase in classifierCases {
        let sequence = CommandClassifier.classify(testCase.command).programSequence
        for secret in secrets {
            #expect(!sequence.contains(secret), "\(testCase.name): \(sequence)")
        }
    }
}

@Test func classifierVersionIsTwo() {
    #expect(CommandClassifier.version == 2)
}
