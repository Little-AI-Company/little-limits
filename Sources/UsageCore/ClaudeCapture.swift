import Foundation

public struct ClaudeQuotaCapture: Codable, Sendable {
    public let profileID: UUID
    public let observedAt: Date
    public let windows: [UsageWindow]

    public init(profileID: UUID, observedAt: Date, windows: [UsageWindow]) {
        self.profileID = profileID
        self.observedAt = observedAt
        self.windows = windows
    }

    public static func decodeStatusLine(_ data: Data, profileID: UUID, observedAt: Date = Date()) throws -> Self {
        struct Window: Decodable {
            let used_percentage: Double?
            let resets_at: Double?
        }
        struct Limits: Decodable {
            let five_hour: Window?
            let seven_day: Window?
        }
        struct Input: Decodable { let rate_limits: Limits? }
        let input = try JSONDecoder().decode(Input.self, from: data)
        var windows: [UsageWindow] = []
        for (id, title, value) in [("five_hour", "5 hours", input.rate_limits?.five_hour),
                                   ("seven_day", "7 days", input.rate_limits?.seven_day)] {
            guard let value else { continue }
            windows.append(UsageWindow(id: id, title: title, utilizationPercent: value.used_percentage,
                                       resetsAt: value.resets_at.map(Date.init(timeIntervalSince1970:))))
        }
        return Self(profileID: profileID, observedAt: observedAt, windows: windows)
    }

    public func save(directory: URL = UsagePaths.applicationSupport) throws {
        let url = UsagePaths.captureURL(profileID: profileID, directory: directory)
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONDecoder().decode(Self.self, from: data),
           existing.profileID == profileID, existing.windows == windows {
            // Claude may repaint its status line without receiving new quota data.
            return
        }
        try UsagePaths.writePrivate(JSONEncoder().encode(self), to: url)
    }
}

enum ClaudeCaptureInstallation {
    static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func install(profileID: UUID, configurationURL: URL, helperURL: URL,
                        storageDirectory: URL) throws -> CaptureInstallation {
        guard FileManager.default.isExecutableFile(atPath: helperURL.path) else {
            throw UsageError.invalidConfiguration("Usage capture helper is missing. Open the packaged Limits Left app.")
        }
        let settingsURL = configurationURL.appendingPathComponent("settings.json").resolvingSymlinksInPath()
        var settings: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: settingsURL.path) {
            guard let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settingsURL)) as? [String: Any] else {
                throw UsageError.invalidConfiguration("Claude settings.json must contain a JSON object.")
            }
            settings = object
        }
        let original = settings["statusLine"]
        var originalCommand: String?
        if let original {
            guard let statusLine = original as? [String: Any], statusLine["type"] as? String == "command",
                  let command = statusLine["command"] as? String else {
                throw UsageError.invalidConfiguration("The existing Claude status line cannot be preserved automatically.")
            }
            guard !command.contains("UsageCapture") else {
                throw UsageError.invalidConfiguration("This Claude directory already has a usage capture command. Restore its original status line before importing again.")
            }
            originalCommand = command
        }
        var command = "\(shellQuote(helperURL.path)) --profile \(shellQuote(profileID.uuidString)) --storage-directory \(shellQuote(storageDirectory.path))"
        if let originalCommand { command += " --original-command \(shellQuote(originalCommand))" }
        var statusLine = (original as? [String: Any]) ?? [:]
        statusLine["type"] = "command"
        statusLine["command"] = command
        settings["statusLine"] = statusLine
        let originalData = try original.map { try JSONSerialization.data(withJSONObject: $0) }
        try UsagePaths.writePrivate(JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]), to: settingsURL)
        return CaptureInstallation(configurationPath: configurationURL.path, settingsPath: settingsURL.path, installedCommand: command,
                                   installedStatusLine: try JSONSerialization.data(withJSONObject: statusLine, options: [.sortedKeys]),
                                   originalStatusLine: originalData)
    }

    static func remove(_ installation: CaptureInstallation) throws {
        let url = URL(fileURLWithPath: installation.configurationPath).appendingPathComponent("settings.json").resolvingSymlinksInPath()
        guard url.path == installation.settingsPath, FileManager.default.fileExists(atPath: url.path),
              var settings = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              let statusLine = settings["statusLine"] as? [String: Any],
              try JSONSerialization.data(withJSONObject: statusLine, options: [.sortedKeys]) == installation.installedStatusLine else { return }
        if let original = installation.originalStatusLine {
            settings["statusLine"] = try JSONSerialization.jsonObject(with: original)
        } else {
            settings.removeValue(forKey: "statusLine")
        }
        try UsagePaths.writePrivate(JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]), to: url)
    }

    static func retire(_ installation: CaptureInstallation) throws -> Bool {
        try remove(installation)
        let url = URL(fileURLWithPath: installation.configurationPath).appendingPathComponent("settings.json").resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: url.path) else { return true }
        guard let settings = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw UsageError.invalidConfiguration("Claude settings could not be checked after removing the old connection.")
        }
        // A changed wrapper with our command still runs the helper. Keep its restoration record.
        return (settings["statusLine"] as? [String: Any])?["command"] as? String != installation.installedCommand
    }
}
