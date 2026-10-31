import Foundation
import GRDB
import UsageHistory

public struct CodexAccountLink: Sendable, Hashable {
    public let accountID: UUID
    public let providerAccountID: String

    public init(accountID: UUID, providerAccountID: String) {
        self.accountID = accountID
        self.providerAccountID = providerAccountID
    }
}

public struct LogIngestionSummary: Sendable, Equatable {
    public var filesRead = 0
    public var filesUnchanged = 0
    public var filesFailed = 0
    public var responses = 0
    public var commands = 0
    public var quotaReadingsMatched = 0
    public var quotaReadingsUnmatched = 0
    public var quotaReadingsAdded = 0
    public var lastFailure: String?

    public init() {}
}

public actor LogIngestor {
    private let database: HistoryDatabase
    private let claudeProjects: URL
    private let codexDirectories: [URL]

    public init(database: HistoryDatabase, homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.database = database
        claudeProjects = homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        codexDirectories = ["sessions", "archived_sessions"].map {
            homeDirectory.appendingPathComponent(".codex", isDirectory: true).appendingPathComponent($0, isDirectory: true)
        }
    }

    public func ingest(codexAccounts: [CodexAccountLink]) -> LogIngestionSummary {
        var summary = LogIngestionSummary()
        let accountsByProviderID = Dictionary(grouping: codexAccounts, by: \.providerAccountID)
            .compactMapValues { $0.count == 1 ? $0[0].accountID : nil }
        let positions: [String: SourceFilePosition]
        let newLinks: [CodexAccountLink]
        let completedClassifierVersion: Int?
        let hasCommands: Bool
        do {
            newLinks = try readCodexLinksToApply(codexAccounts.filter { accountsByProviderID[$0.providerAccountID] != nil })
            (positions, completedClassifierVersion, hasCommands) = try database.pool.read { db in
                (Dictionary(uniqueKeysWithValues: try SourceFilePosition.fetchAll(db).map { ($0.path, $0) }),
                 try Int.fetchOne(db, sql: "SELECT version FROM completedClassifierVersion"),
                 try Bool.fetchOne(db, sql: "SELECT EXISTS (SELECT 1 FROM shellCommand)") ?? false)
            }
        } catch {
            summary.filesFailed += 1
            summary.lastFailure = error.localizedDescription
            return summary
        }

        let salt = database.projectKeySalt
        let (claudeFiles, unreadableClaude) = Self.logFiles(in: [claudeProjects], suffixes: [".jsonl"], salt: salt)
        let (unsortedCodexFiles, unreadableCodex) = Self.logFiles(in: codexDirectories,
                                                                   suffixes: [".jsonl", ".jsonl.zst"], salt: salt)
        let codexFiles = unsortedCodexFiles.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
        summary.filesFailed += unreadableClaude + unreadableCodex
        let appliedVersion = completedClassifierVersion ?? (hasCommands ? 0 : CommandClassifier.version)
        let reclassifies = appliedVersion < CommandClassifier.version
        for file in claudeFiles {
            ingest(file, as: ClaudeLogParser.self, position: reclassifies ? nil : positions[file.positionKey],
                   accounts: [:], summary: &summary)
        }
        var everyCodexLogRead = unreadableCodex == 0
        for file in codexFiles {
            let rereads = reclassifies || !newLinks.isEmpty
            let succeeded = ingest(file, as: CodexLogParser.self, position: rereads ? nil : positions[file.positionKey],
                                   accounts: accountsByProviderID, summary: &summary)
            if !succeeded { everyCodexLogRead = false }
        }
        let discovered = Set((claudeFiles + codexFiles).map(\.positionKey))
        let missing = positions.keys.filter { !discovered.contains($0) }
        if summary.filesFailed == 0, completedClassifierVersion != CommandClassifier.version {
            do {
                try database.pool.write { db in
                    _ = try SourceFilePosition.deleteAll(db, keys: missing)
                    try db.execute(sql: "DELETE FROM completedClassifierVersion")
                    try db.execute(sql: "INSERT INTO completedClassifierVersion (version) VALUES (?)",
                                   arguments: [CommandClassifier.version])
                }
            } catch {
                summary.lastFailure = error.localizedDescription
            }
        }
        if !newLinks.isEmpty, everyCodexLogRead {
            do {
                try database.pool.write { db in
                    _ = try SourceFilePosition.deleteAll(db, keys: missing)
                    for link in newLinks {
                        try db.execute(sql: "INSERT OR IGNORE INTO codexBackfillAccount VALUES (?, ?)",
                                       arguments: [link.accountID, link.providerAccountID])
                    }
                }
            } catch {
                summary.lastFailure = error.localizedDescription
            }
        }
        return summary
    }

    private func readCodexLinksToApply(_ links: [CodexAccountLink]) throws -> [CodexAccountLink] {
        let applied = try database.pool.read { db in
            try Row.fetchAll(db, sql: "SELECT accountID, providerAccountID FROM codexBackfillAccount").map {
                CodexAccountLink(accountID: $0["accountID"], providerAccountID: $0["providerAccountID"])
            }
        }
        return links.filter { !applied.contains($0) }
    }

    @discardableResult
    private func ingest<Parser: HistoryLogParser>(_ file: LogFile, as parser: Parser.Type,
                                                  position: SourceFilePosition?, accounts: [String: UUID],
                                                  summary: inout LogIngestionSummary) -> Bool {
        let start: Int64
        if let position {
            if file.isUnchanged(since: position) {
                summary.filesUnchanged += 1
                return true
            }
            start = file.isDifferentFile(from: position) ? 0 : position.byteOffset
        } else {
            start = 0
        }
        do {
            var parser = Parser(filePath: file.url.path, projectKeySalt: database.projectKeySalt)
            if Parser.needsFirstLine, start > 0, let first = try LogLineReader(path: file.url.path).nextLine() {
                parser.consume(line: first.data, at: first.byteOffset)
            }
            let reader = try LogLineReader(path: file.url.path, startOffset: start)
            while let line = try autoreleasepool(invoking: { try reader.nextLine() }) {
                autoreleasepool { parser.consume(line: line.data, at: line.byteOffset) }
            }
            let output = parser.finish()
            let commands = output.commands.map {
                ShellCommandRecord(event: $0, classification: CommandClassifier.classify($0.command),
                                   classifierVersion: CommandClassifier.version)
            }
            var readings: [QuotaReading] = []
            for reading in output.quotaReadings {
                guard let accountID = accounts[reading.providerAccountID] else {
                    summary.quotaReadingsUnmatched += 1
                    continue
                }
                summary.quotaReadingsMatched += 1
                readings.append(QuotaReading(provider: .codex, accountID: accountID, windowID: reading.windowID,
                                             usedPercent: reading.usedPercent, resetsAt: reading.resetsAt,
                                             windowDurationMinutes: reading.windowDurationMinutes,
                                             observedAt: reading.observedAt, source: .codexLogBackfill))
            }
            let newPosition = SourceFilePosition(path: file.positionKey, byteOffset: max(output.resumeByteOffset, start),
                                                 fileSize: file.size, modifiedAt: file.modifiedAt)
            let added = try database.pool.write { db in
                for response in output.responses { try response.insert(db) }
                for command in commands { try command.insert(db) }
                let added = try Self.insertChangedReadings(readings, db)
                try newPosition.insert(db)
                return added
            }
            summary.filesRead += 1
            summary.responses += output.responses.count
            summary.commands += commands.count
            summary.quotaReadingsAdded += added
            return true
        } catch {
            summary.filesFailed += 1
            summary.lastFailure = error.localizedDescription
            return false
        }
    }

    private static func insertChangedReadings(_ readings: [QuotaReading], _ db: Database) throws -> Int {
        var added = 0
        for reading in readings {
            let window = QuotaReading.filter(Column("accountID") == reading.accountID
                                             && Column("windowID") == reading.windowID
                                             && Column("source") == QuotaReadingSource.codexLogBackfill.rawValue)
            let earlier = try window.filter(Column("observedAt") < reading.observedAt)
                .order(Column("observedAt").desc).fetchOne(db)
            if let earlier, hasSameQuota(earlier, reading) { continue }
            try reading.insert(db)
            added += db.changesCount
            let later = try window.filter(Column("observedAt") > reading.observedAt)
                .order(Column("observedAt")).fetchOne(db)
            if let later, hasSameQuota(later, reading) {
                try later.delete(db)
                added -= 1
            }
        }
        return added
    }

    private static func hasSameQuota(_ first: QuotaReading, _ second: QuotaReading) -> Bool {
        guard first.usedPercent == second.usedPercent else { return false }
        switch (first.resetsAt, second.resetsAt) {
        case (nil, nil): return true
        case let (firstReset?, secondReset?): return abs(firstReset.timeIntervalSince(secondReset)) < 60
        default: return false
        }
    }

    private static func logFiles(in directories: [URL], suffixes: [String],
                                 salt: [UInt8]) -> (files: [LogFile], unreadable: Int) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        var files: [LogFile] = []
        var unreadable = 0
        for directory in directories where FileManager.default.fileExists(atPath: directory.path) {
            guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys,
                                                                  errorHandler: { _, _ in unreadable += 1; return true })
            else { unreadable += 1; continue }
            for case let url as URL in enumerator where suffixes.contains(where: url.lastPathComponent.hasSuffix) {
                guard let values = try? url.resourceValues(forKeys: Set(keys)) else { unreadable += 1; continue }
                guard values.isRegularFile == true, let size = values.fileSize,
                      let modifiedAt = values.contentModificationDate else { continue }
                files.append(LogFile(url: url, positionKey: ProjectKey.make(workingDirectory: url.path, salt: salt),
                                     size: Int64(size), modifiedAt: modifiedAt))
            }
        }
        return (files, unreadable)
    }
}

private struct LogFile {
    let url: URL
    let positionKey: String
    let size: Int64
    let modifiedAt: Date

    func isUnchanged(since position: SourceFilePosition) -> Bool {
        size == position.fileSize
            && abs(modificationChange(since: position)) < SourceFilePosition.modificationTimePrecision
    }

    func isDifferentFile(from position: SourceFilePosition) -> Bool {
        size < position.fileSize || modificationChange(since: position) < -SourceFilePosition.modificationTimePrecision
    }

    private func modificationChange(since position: SourceFilePosition) -> TimeInterval {
        modifiedAt.timeIntervalSince(position.modifiedAt)
    }
}

extension SourceFilePosition {
    static let modificationTimePrecision: TimeInterval = 0.001
}

protocol HistoryLogParser {
    static var needsFirstLine: Bool { get }
    init(filePath: String, projectKeySalt: [UInt8])
    mutating func consume(line: Data, at byteOffset: Int64)
    func finish() -> LogParseOutput
}

extension ClaudeLogParser: HistoryLogParser {
    static var needsFirstLine: Bool { false }
}

extension CodexLogParser: HistoryLogParser {
    static var needsFirstLine: Bool { true }
}
