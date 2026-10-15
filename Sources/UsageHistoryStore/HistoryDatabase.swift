import Foundation
import GRDB
import UsageHistory

/// The local usage history database: one writer, concurrent readers, write-ahead logging.
public final class HistoryDatabase: Sendable {
    public let pool: DatabasePool
    /// Created once with the database. Pass it to `ProjectKey.make` so keys stay stable across launches.
    public let projectKeySalt: [UInt8]

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        pool = try DatabasePool(path: url.path)
        try Self.migrator.migrate(pool)
        let salt = try pool.read { db in try Data.fetchOne(db, sql: "SELECT value FROM projectKeySalt") }
        guard let salt else { throw DatabaseError(message: "The usage history database has no project key salt.") }
        projectKeySalt = Array(salt)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: QuotaReading.databaseTableName) { table in
                table.column("provider", .text).notNull()
                table.column("accountID", .blob).notNull()
                table.column("windowID", .text).notNull()
                table.column("usedPercent", .double).notNull()
                table.column("resetsAt", .datetime)
                table.column("windowDurationMinutes", .integer)
                table.column("observedAt", .datetime).notNull()
                table.column("source", .text).notNull()
                table.primaryKey(["accountID", "windowID", "source", "observedAt"])
            }
            try db.create(table: ModelResponse.databaseTableName) { table in
                table.column("provider", .text).notNull()
                table.column("responseID", .text).notNull()
                table.column("sessionID", .text).notNull()
                table.column("turnID", .text).notNull()
                table.column("model", .text).notNull()
                table.column("projectKey", .text)
                table.column("requestedAt", .datetime)
                table.column("completedAt", .datetime).notNull()
                table.column("outputTokens", .integer)
                table.column("thinkingTokens", .integer)
                table.column("toolCallCount", .integer).notNull()
                table.column("hasParallelToolCalls", .boolean).notNull()
                table.primaryKey(["provider", "responseID"])
            }
            try db.create(table: ShellCommandRecord.databaseTableName) { table in
                table.column("provider", .text).notNull()
                table.column("commandID", .text).notNull()
                table.column("responseID", .text).notNull()
                table.column("sessionID", .text).notNull()
                table.column("model", .text).notNull()
                table.column("projectKey", .text)
                table.column("executedAt", .datetime).notNull()
                table.column("succeeded", .boolean)
                table.column("characterCount", .integer).notNull()
                table.column("lineCount", .integer).notNull()
                table.column("searchProgram", .text).notNull()
                table.column("pipesIntoHeadOrTail", .boolean).notNull()
                table.column("runsGitStatus", .boolean).notNull()
                table.column("runsGitCommit", .boolean).notNull()
                table.column("inlineInterpreter", .text).notNull()
                table.column("runsSavedScript", .boolean).notNull()
                table.column("inlineScriptPurpose", .text)
                table.column("inlineScriptLineCount", .integer)
                table.column("programSequence", .text).notNull()
                table.column("classifierVersion", .integer).notNull()
                table.primaryKey(["provider", "commandID"])
            }
            try db.create(table: "projectKeySalt") { table in
                table.column("value", .blob).notNull()
            }
            let salt = Data((0..<16).map { _ in UInt8.random(in: .min ... .max) })
            try db.execute(sql: "INSERT INTO projectKeySalt (value) VALUES (?)", arguments: [salt])
            try db.create(table: SourceFilePosition.databaseTableName) { table in
                table.column("path", .text).notNull().primaryKey()
                table.column("byteOffset", .integer).notNull()
                table.column("fileSize", .integer).notNull()
                table.column("modifiedAt", .datetime).notNull()
            }
        }
        return migrator
    }
}

// A quota reading never changes after it is observed, so a repeated insert is ignored.
extension QuotaReading: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "quotaReading"
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .ignore, update: .abort)
}

// A later read of the same log can complete a response or command, such as its final usage line or its exit
// status, so a repeated insert replaces the earlier row. See `LogParseOutput.resumeByteOffset`.
extension ModelResponse: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "modelResponse"
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)
}

extension ShellCommandRecord: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "shellCommand"
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)
}

// A newer read position for the same path replaces the old one.
extension SourceFilePosition: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "sourceFilePosition"
    public static let persistenceConflictPolicy = PersistenceConflictPolicy(insert: .replace, update: .replace)
}
