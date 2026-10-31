import Foundation
import Testing

private final class TestProducts {}

@Test func captureHelperRunsTheOriginalCommandWhenItCannotSave() throws {
    let helper = Bundle(for: TestProducts.self).bundleURL.deletingLastPathComponent()
        .appendingPathComponent("UsageCapture")
    try #require(FileManager.default.isExecutableFile(atPath: helper.path))
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("UsageCaptureHelperTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let fileInPlaceOfStorage = directory.appendingPathComponent("storage")
    try Data().write(to: fileInPlaceOfStorage)
    let input = Data(#"{"rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1738425600}}}"#.utf8)

    let process = Process()
    process.executableURL = helper
    process.arguments = ["--profile", UUID().uuidString, "--storage-directory", fileInPlaceOfStorage.path,
                         "--original-command", "cat; exit 7"]
    let standardInput = Pipe()
    let standardOutput = Pipe()
    process.standardInput = standardInput
    process.standardOutput = standardOutput
    try process.run()
    try standardInput.fileHandleForWriting.write(contentsOf: input)
    try standardInput.fileHandleForWriting.close()
    let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    #expect(process.terminationStatus == 7)
    #expect(output == input)
}
