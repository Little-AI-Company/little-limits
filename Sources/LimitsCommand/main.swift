import Foundation
import UsageCore

func usage() -> String {
    """
    Usage: little-limits [status [--json] | mcp] [--digest <path>]

      status          Print what is left on each Claude and Codex account, when it resets,
                      and which account to use now. This is the default.
      status --json   Print the limits file Little Limits writes after each refresh.
      mcp             Run a read-only MCP server on standard input and output for
                      Claude Code, Codex CLI and Claude Desktop.
      --digest <path> Read this limits file instead of the one Little Limits writes.

    Nothing here refreshes an account or contacts a provider. Answers come from the file
    Little Limits wrote last, labelled with its age.

    """
}

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

var arguments = Array(CommandLine.arguments.dropFirst())
var digestURL = LimitsDigest.fileURL
if let index = arguments.firstIndex(of: "--digest") {
    guard arguments.indices.contains(index + 1) else { fail(usage(), code: 64) }
    digestURL = URL(fileURLWithPath: arguments[index + 1])
    arguments.removeSubrange(index...(index + 1))
}

switch arguments {
case [], ["status"]:
    do {
        let now = Date()
        print(LimitsDigestText.overview(try LimitsDigest.read(from: digestURL).revalidated(at: now), now: now))
    } catch {
        fail(DigestSource.missingMessage(error, url: digestURL), code: 2)
    }
case ["status", "--json"]:
    do {
        FileHandle.standardOutput.write(try LimitsDigest.read(from: digestURL).encoded())
        print()
    } catch {
        fail(DigestSource.missingMessage(error, url: digestURL), code: 2)
    }
case ["mcp"]:
    MCPServer(source: DigestSource(url: digestURL)).run()
case ["--help"], ["-h"], ["help"]:
    print(usage(), terminator: "")
default:
    fail(usage(), code: 64)
}
