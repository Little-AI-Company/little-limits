import Foundation
import UsageCore

// Claude calls this helper with its status-line input. Only quota fields are saved.
let arguments = CommandLine.arguments
func value(after name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

let input = FileHandle.standardInput.readDataToEndOfFile()
if let identifier = value(after: "--profile"), let profileID = UUID(uuidString: identifier) {
    let directory = value(after: "--storage-directory").map { URL(fileURLWithPath: $0, isDirectory: true) }
        ?? UsagePaths.applicationSupport
    do {
        try ClaudeQuotaCapture.decodeStatusLine(input, profileID: profileID).save(directory: directory)
    } catch {
        // Capture failures must not break an existing status-line command.
    }
}

if let command = value(after: "--original-command") {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", command]
    let pipe = Pipe()
    process.standardInput = pipe
    process.standardOutput = FileHandle.standardOutput
    process.standardError = FileHandle.standardError
    do {
        try process.run()
        try pipe.fileHandleForWriting.write(contentsOf: input)
        try pipe.fileHandleForWriting.close()
        process.waitUntilExit()
        exit(process.terminationStatus)
    } catch {
        exit(1)
    }
}
