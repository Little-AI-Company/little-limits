import Foundation
import libzstd
import Testing
import UsageHistory

/// Synthetic lines of varied length, enough to cross read and decompression buffer boundaries many times.
private let syntheticLines: [String] = (0..<6_000).map { index in
    #"{"index":\#(index),"text":"\#(String(repeating: "x", count: (index * 37) % 400))"}"#
}

private func expectedLines(_ lines: [String]) -> [LogFileLine] {
    var offset: Int64 = 0
    return lines.map { line in
        defer { offset += Int64(line.utf8.count + 1) }
        return LogFileLine(data: Data(line.utf8), byteOffset: offset)
    }
}

private func readAll(_ path: String, from startOffset: Int64 = 0, maximumLineLength: Int? = nil) throws -> [LogFileLine] {
    let reader = try maximumLineLength.map { try LogLineReader(path: path, startOffset: startOffset, maximumLineLength: $0) }
        ?? LogLineReader(path: path, startOffset: startOffset)
    var lines: [LogFileLine] = []
    while let line = try reader.nextLine() { lines.append(line) }
    return lines
}

private func compress(_ data: Data) -> Data {
    let bound = ZSTD_compressBound(data.count)
    var compressed = [UInt8](repeating: 0, count: bound)
    let size = data.withUnsafeBytes { source in
        compressed.withUnsafeMutableBytes { destination in
            ZSTD_compress(destination.baseAddress, bound, source.baseAddress, source.count, 3)
        }
    }
    precondition(ZSTD_isError(size) == 0)
    return Data(compressed[..<size])
}

/// Writes `content` as `log.jsonl` and `log.jsonl.zst` in a new temporary directory.
private func writeLogFiles(_ content: String) throws -> (plain: String, compressed: String) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let plain = directory.appendingPathComponent("log.jsonl")
    let compressed = directory.appendingPathComponent("log.jsonl.zst")
    try Data(content.utf8).write(to: plain)
    try compress(Data(content.utf8)).write(to: compressed)
    return (plain.path, compressed.path)
}

@Test func plainAndCompressedFilesGiveTheSameLinesAndOffsets() throws {
    let files = try writeLogFiles(syntheticLines.joined(separator: "\n") + "\n")
    let expected = expectedLines(syntheticLines)

    #expect(try readAll(files.plain) == expected)
    #expect(try readAll(files.compressed) == expected)

    let start = expected[4_321].byteOffset
    #expect(try readAll(files.plain, from: start) == Array(expected[4_321...]))
    #expect(try readAll(files.compressed, from: start) == Array(expected[4_321...]))
}

@Test func partialLastLineIsWithheld() throws {
    let lines = Array(syntheticLines.prefix(300))
    let files = try writeLogFiles(lines.joined(separator: "\n") + "\n" + #"{"index":300,"te"#)
    let expected = expectedLines(lines)

    #expect(try readAll(files.plain) == expected)
    #expect(try readAll(files.compressed) == expected)
}

@Test func lineLongerThanTheLimitIsSkippedAndOffsetsStayAbsolute() throws {
    let lines = ["first", String(repeating: "y", count: 300_000), "third"]
    let files = try writeLogFiles(lines.joined(separator: "\n") + "\n")
    let expected = expectedLines(lines)

    #expect(try readAll(files.plain, maximumLineLength: 1_000) == [expected[0], expected[2]])
    #expect(try readAll(files.compressed, maximumLineLength: 1_000) == [expected[0], expected[2]])
}

/// The frame's last call fills the output buffer exactly; the reader must not treat the finished frame as truncated.
@Test func frameEndingOnAFullOutputBufferIsComplete() throws {
    let lineLength = 1_023
    let lines = (0..<(ZSTD_DStreamOutSize() / (lineLength + 1))).map { _ in String(repeating: "z", count: lineLength) }
    let files = try writeLogFiles(lines.joined(separator: "\n") + "\n")

    #expect(try readAll(files.compressed) == expectedLines(lines))
}

@Test func truncatedCompressedFileThrows() throws {
    let files = try writeLogFiles(syntheticLines.joined(separator: "\n") + "\n")
    let truncated = try Data(contentsOf: URL(fileURLWithPath: files.compressed)).dropLast(16)
    try truncated.write(to: URL(fileURLWithPath: files.compressed))

    #expect(throws: LogLineReaderError.truncatedCompressedFile) { try readAll(files.compressed) }
}
