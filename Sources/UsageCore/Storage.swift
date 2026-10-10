import Foundation
import Darwin

public enum UsageError: Error, LocalizedError, Sendable {
    case invalidConfiguration(String)
    case invalidImport(String)
    case providerFailure(String)
    case authenticationRequired(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message), .invalidImport(let message),
             .providerFailure(let message), .authenticationRequired(let message): message
        }
    }
}

public enum UsagePaths {
    public static var applicationSupport: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AI Usage Stats", isDirectory: true)
    }

    public static func captureURL(profileID: UUID, directory: URL = applicationSupport) -> URL {
        directory.appendingPathComponent("Captures", isDirectory: true)
            .appendingPathComponent(profileID.uuidString + ".json")
    }

    static func writePrivate(_ data: Data, to url: URL, permissions: mode_t = 0o600) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, permissions)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { unlink(temporary.path) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            guard rename(temporary.path, url.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
        } catch {
            try? handle.close()
            throw error
        }
    }
}

struct CaptureInstallation: Codable, Sendable {
    let configurationPath: String
    let settingsPath: String
    let installedCommand: String
    let installedStatusLine: Data
    let originalStatusLine: Data?
}

struct StoredConfiguration: Codable, Sendable {
    var profiles: [AccountProfile] = []
    var snapshots: [AccountSnapshot] = []
    var manualCredits: [String: [CreditBalance]] = [:]
    var pendingManualCredits: [String: [CreditBalance]] = [:]
    var captureInstallations: [String: CaptureInstallation] = [:]
    var consoleConnections: [String: String] = [:]
    var consoleObservations: [String: ConsoleCreditObservation] = [:]

    init() {}

    private enum CodingKeys: String, CodingKey {
        case profiles, snapshots, manualCredits, pendingManualCredits, captureInstallations, consoleConnections, consoleObservations
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try values.decodeIfPresent([AccountProfile].self, forKey: .profiles) ?? []
        snapshots = try values.decodeIfPresent([AccountSnapshot].self, forKey: .snapshots) ?? []
        manualCredits = try values.decodeIfPresent([String: [CreditBalance]].self, forKey: .manualCredits) ?? [:]
        pendingManualCredits = try values.decodeIfPresent([String: [CreditBalance]].self, forKey: .pendingManualCredits) ?? [:]
        captureInstallations = try values.decodeIfPresent([String: CaptureInstallation].self, forKey: .captureInstallations) ?? [:]
        consoleConnections = try values.decodeIfPresent([String: String].self, forKey: .consoleConnections) ?? [:]
        consoleObservations = try values.decodeIfPresent([String: ConsoleCreditObservation].self, forKey: .consoleObservations) ?? [:]
    }
}

struct ConsoleCreditObservation: Codable, Sendable {
    let organizationID: String
    let observedAt: Date
    let credits: [CreditBalance]
}

struct ConfigurationStorage: Sendable {
    let directory: URL

    private var fileURL: URL { directory.appendingPathComponent("accounts.json") }

    func load() throws -> StoredConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return StoredConfiguration() }
        return try JSONDecoder().decode(StoredConfiguration.self, from: Data(contentsOf: fileURL))
    }

    func save(_ configuration: StoredConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try UsagePaths.writePrivate(encoder.encode(configuration), to: fileURL)
    }
}
