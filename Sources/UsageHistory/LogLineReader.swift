import Foundation
import libzstd

/// One complete line of a log file, without its line feed.
public struct LogLine: Sendable, Equatable {
    public let data: Data
    /// Absolute offset of the line's first byte in the uncompressed content.
    public let byteOffset: Int64

    public init(data: Data, byteOffset: Int64) {
        self.data = data
        self.byteOffset = byteOffset
    }
}

public enum LogLineReaderError: Error, Equatable {
    case decompressorUnavailable
    case decompressionFailed(String)
    /// The file ends inside a Zstandard frame.
    case truncatedCompressedFile
}

/// Reads the complete lines of a plain `.jsonl` file or a Zstandard `.jsonl.zst` file, chosen by the `.zst` suffix,
/// starting at a line's offset in the uncompressed content. Call `nextLine()` until it returns nil.
///
/// The file is read in fixed-size chunks and a compressed file is decompressed as a stream, so memory holds one chunk
/// plus the current line. A line longer than `maximumLineLength` is skipped. A trailing line without a line feed may
/// still be growing and is never returned; the next read starts at its offset.
public final class LogLineReader {
    public static let defaultMaximumLineLength = 64 << 20
    private static let plainChunkSize = 64 << 10

    private let handle: FileHandle
    private let decompressor: ZstandardDecompressor?
    private let maximumLineLength: Int
    /// Uncompressed bytes not yet returned. `cursor` is the next line's first byte; no line feed precedes `scanned`.
    private var pending: [UInt8] = []
    private var cursor = 0
    private var scanned = 0
    private var cursorOffset: Int64
    /// Decompressed bytes before the start offset, which a compressed file cannot seek past.
    private var bytesToSkip: Int64
    private var isSkippingLongLine = false

    /// `startOffset` must be the first byte of a line, such as a parser's resume offset.
    public init(path: String, startOffset: Int64 = 0, maximumLineLength: Int = LogLineReader.defaultMaximumLineLength)
        throws {
        handle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        self.maximumLineLength = maximumLineLength
        cursorOffset = startOffset
        if path.hasSuffix(".zst") {
            do { decompressor = try ZstandardDecompressor() } catch {
                try? handle.close()
                throw error
            }
            bytesToSkip = startOffset
        } else {
            decompressor = nil
            bytesToSkip = 0
            do { try handle.seek(toOffset: UInt64(startOffset)) } catch {
                try? handle.close()
                throw error
            }
        }
    }

    deinit { try? handle.close() }

    public func nextLine() throws -> LogLine? {
        while true {
            if let newline = pending[scanned...].firstIndex(of: 0x0A) {
                let isTooLong = isSkippingLongLine || newline - cursor > maximumLineLength
                let line = isTooLong ? nil : LogLine(data: Data(pending[cursor..<newline]), byteOffset: cursorOffset)
                cursorOffset += Int64(newline + 1 - cursor)
                cursor = newline + 1
                scanned = cursor
                isSkippingLongLine = false
                if let line { return line }
                continue
            }
            scanned = pending.count
            if pending.count - cursor > maximumLineLength {
                cursorOffset += Int64(pending.count - cursor)
                pending.removeAll(keepingCapacity: true)
                cursor = 0
                scanned = 0
                isSkippingLongLine = true
            }
            guard try readMore() else { return nil }
        }
    }

    /// Appends at least one byte to `pending`, or returns false at the end of the file.
    private func readMore() throws -> Bool {
        if cursor > 0 {
            pending.removeFirst(cursor)
            scanned -= cursor
            cursor = 0
        }
        let countBefore = pending.count
        while pending.count == countBefore {
            if let decompressor {
                guard try decompressor.decompressBlock(from: handle, into: { append($0) }) else { return false }
            } else {
                guard let chunk = try handle.read(upToCount: Self.plainChunkSize), !chunk.isEmpty else { return false }
                chunk.withUnsafeBytes { append($0) }
            }
        }
        return true
    }

    private func append(_ bytes: UnsafeRawBufferPointer) {
        var bytes = bytes
        if bytesToSkip > 0 {
            let skipped = Int(min(bytesToSkip, Int64(bytes.count)))
            bytesToSkip -= Int64(skipped)
            bytes = UnsafeRawBufferPointer(rebasing: bytes[skipped...])
        }
        pending.append(contentsOf: bytes)
    }
}

/// A Zstandard streaming decoder that produces at most one output block per call, so a highly compressed line cannot
/// expand beyond the line length limit in memory.
private final class ZstandardDecompressor {
    private let inputChunkSize = ZSTD_DStreamInSize()
    private let context: OpaquePointer
    private var input = Data()
    private var inputPosition = 0
    private var output: [UInt8]
    /// The last call filled the output buffer, so the decoder may hold more output without new input.
    private var mayHoldOutput = false
    /// False while a frame has started but not finished.
    private var isAtFrameBoundary = true

    init() throws {
        guard let context = ZSTD_createDCtx() else { throw LogLineReaderError.decompressorUnavailable }
        self.context = context
        output = [UInt8](repeating: 0, count: ZSTD_DStreamOutSize())
    }

    deinit { ZSTD_freeDCtx(context) }

    /// Passes up to one block of output to `sink`, which may be empty. Returns false at the end of the file.
    func decompressBlock(from handle: FileHandle, into sink: (UnsafeRawBufferPointer) -> Void) throws -> Bool {
        if inputPosition == input.count && !mayHoldOutput {
            guard let chunk = try handle.read(upToCount: inputChunkSize), !chunk.isEmpty else {
                if !isAtFrameBoundary { throw LogLineReaderError.truncatedCompressedFile }
                return false
            }
            input = chunk
            inputPosition = 0
        }
        try input.withUnsafeBytes { source in
            var inBuffer = ZSTD_inBuffer(src: source.baseAddress, size: source.count, pos: inputPosition)
            try output.withUnsafeMutableBytes { destination in
                var outBuffer = ZSTD_outBuffer(dst: destination.baseAddress, size: destination.count, pos: 0)
                let result = ZSTD_decompressStream(context, &outBuffer, &inBuffer)
                if ZSTD_isError(result) != 0 {
                    throw LogLineReaderError.decompressionFailed(String(cString: ZSTD_getErrorName(result)))
                }
                inputPosition = inBuffer.pos
                mayHoldOutput = outBuffer.pos == outBuffer.size
                isAtFrameBoundary = result == 0
                sink(UnsafeRawBufferPointer(rebasing: destination[..<outBuffer.pos]))
            }
        }
        return true
    }
}
