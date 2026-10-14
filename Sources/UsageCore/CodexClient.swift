import Foundation
import Darwin

private struct CodexNotification<Parameters: Encodable>: Encodable {
    let method: String
    let params: Parameters
}

private struct CodexRequest<Parameters: Encodable>: Encodable {
    let id: Int
    let method: String
    let params: Parameters
}

private struct CodexProtocolFailure: Decodable { let code: Int; let message: String }
private struct CodexResponseEnvelope<Result: Decodable>: Decodable {
    let id: Int?
    let result: Result?
    let error: CodexProtocolFailure?
}
private struct CodexResponseIdentifier: Decodable { let id: Int?; let method: String? }

public struct CodexUsageResponse: Decodable, Sendable {
    public struct Window: Decodable, Sendable {
        public let usedPercent: Double?
        public let windowDurationMins: Int?
        public let resetsAt: Double?
    }
    public struct Credits: Decodable, Sendable {
        public let hasCredits: Bool?
        public let unlimited: Bool?
        public let balance: String?
    }
    public struct RateLimits: Decodable, Sendable {
        public let limitId: String?
        public let limitName: String?
        public let primary: Window?
        public let secondary: Window?
        public let credits: Credits?
        public let planType: String?
    }
    public struct ResetCredit: Decodable, Sendable {
        public let id: String
        public let status: String?
        public let grantedAt: Double?
        public let expiresAt: Double?
        public let title: String?
        public let doesNotExpire: Bool

        private enum CodingKeys: String, CodingKey { case id, status, grantedAt, expiresAt, title }

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            id = try values.decode(String.self, forKey: .id)
            status = try values.decodeIfPresent(String.self, forKey: .status)
            grantedAt = try values.decodeIfPresent(Double.self, forKey: .grantedAt)
            expiresAt = try values.decodeIfPresent(Double.self, forKey: .expiresAt)
            title = try values.decodeIfPresent(String.self, forKey: .title)
            if values.contains(.expiresAt) { doesNotExpire = try values.decodeNil(forKey: .expiresAt) }
            else { doesNotExpire = false }
        }
    }
    public struct ResetCredits: Decodable, Sendable {
        public let availableCount: Int
        public let credits: [ResetCredit]?
    }
    public let rateLimits: RateLimits?
    public let rateLimitsByLimitId: [String: RateLimits]?
    public let rateLimitResetCredits: ResetCredits?
    public let accountId: String?

    public func snapshot(profileID: UUID, observedAt: Date = Date(), planType: String? = nil) -> AccountSnapshot {
        var windows: [UsageWindow] = []
        var credits: [CreditBalance] = []
        let groups: [(String, RateLimits)]
        if let rateLimitsByLimitId, !rateLimitsByLimitId.isEmpty {
            groups = rateLimitsByLimitId.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
        } else if let rateLimits { groups = [(rateLimits.limitId ?? "codex", rateLimits)] }
        else { groups = [] }
        for (identifier, rateLimit) in groups {
            for (position, window) in [("primary", rateLimit.primary), ("secondary", rateLimit.secondary)] {
                guard let window else { continue }
                let duration = window.windowDurationMins.map { minutes in
                    if minutes % 1_440 == 0 { return "\(minutes / 1_440) days" }
                    if minutes % 60 == 0 { return "\(minutes / 60) hours" }
                    return "\(minutes) minutes"
                } ?? (position == "primary" ? "Primary window" : "Secondary window")
                let prefix = groups.count > 1 ? (rateLimit.limitName ?? identifier) + ": " : ""
                windows.append(UsageWindow(id: identifier + "_" + position, title: prefix + duration,
                                           utilizationPercent: window.usedPercent,
                                           resetsAt: window.resetsAt.map(Date.init(timeIntervalSince1970:)),
                                           windowDurationMinutes: window.windowDurationMins))
            }
        }
        // The subscription credit object appears on each meter; keep one balance.
        if let balance = groups.compactMap({ $0.1.credits }).first {
            let amount = balance.balance.flatMap { Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }
            let detail = balance.unlimited == true ? "Provider reports unlimited credits." : nil
            credits.append(CreditBalance(id: "provider_credits", title: "Codex credits", amount: amount,
                                         unit: .credits, asOf: observedAt, detail: detail, isUnlimited: balance.unlimited == true))
        }
        if let resetCredits = rateLimitResetCredits {
            credits.append(CreditBalance(id: "quota_reset_credits", title: "Earned resets",
                                         amount: Decimal(resetCredits.availableCount), unit: .resets,
                                         asOf: observedAt))
            for credit in resetCredits.credits ?? [] {
                credits.append(CreditBalance(id: "quota_reset_" + credit.id, title: credit.title ?? "Earned reset",
                                             amount: nil, unit: .resets,
                                             expiresAt: credit.expiresAt.map(Date.init(timeIntervalSince1970:)),
                                             asOf: observedAt, status: credit.status, doesNotExpire: credit.doesNotExpire))
            }
        }
        let empty = windows.isEmpty && credits.isEmpty
        let expiredWindow = windows.contains { $0.resetsAt.map { $0 <= observedAt } == true }
        return AccountSnapshot(profileID: profileID, fetchedAt: observedAt, windows: windows,
                               credits: credits, state: empty ? .unavailable : expiredWindow ? .stale : .available,
                               detail: empty ? "The Codex CLI returned no usage data." : expiredWindow ? "A reported quota reset has passed. Refresh to obtain current usage." : nil,
                               planName: Self.planName(explicit: planType, groups: groups))
    }

    private static func planName(explicit: String?, groups: [(String, RateLimits)]) -> String? {
        let names = Set(groups.compactMap { displayPlanName($0.1.planType) })
        if names.count == 1 { return names.first }
        if names.count > 1 { return nil }
        return displayPlanName(explicit)
    }

    /// Maps a provider plan code to its name. Unrecognized codes stay as reported. Capacity multipliers are not inferred.
    private static func displayPlanName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "plus": return "Plus"
        case "pro": return "Pro"
        case "free": return "Free"
        case "team": return "Team"
        case "business": return "Business"
        case "enterprise": return "Enterprise"
        case "edu": return "Edu"
        case "go": return "Go"
        case "", "unknown": return nil
        default: return raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}

enum CodexExecutable {
    static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                        home: URL = FileManager.default.homeDirectoryForCurrentUser,
                        applicationDirectories: [URL]? = nil) throws -> URL {
        let applications = applicationDirectories ?? [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        let bundled = applications.flatMap { directory in
            ["ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
             "Codex.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
             "CodexCLI.app/Contents/MacOS/codex", "Codex.app/Contents/Resources/codex"]
                .map { directory.appendingPathComponent($0) }
        }
        if let executable = bundled.first(where: isNativeExecutable) { return executable }
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + [home.appendingPathComponent(".local/bin").path,
               home.appendingPathComponent(".bun/bin").path, "/opt/homebrew/bin", "/usr/local/bin"]
        for directory in directories {
            let entry = URL(fileURLWithPath: directory).appendingPathComponent("codex").resolvingSymlinksInPath()
            if isNativeExecutable(entry) { return entry }
            // Official npm installs expose a Node entry point. Use their shipped native executable instead.
            guard entry.lastPathComponent == "codex.js", entry.deletingLastPathComponent().lastPathComponent == "bin" else { continue }
            let package = entry.deletingLastPathComponent().deletingLastPathComponent()
            guard package.lastPathComponent == "codex", package.deletingLastPathComponent().lastPathComponent == "@openai" else { continue }
            #if arch(arm64)
            let platform = "codex-darwin-arm64"
            let target = "aarch64-apple-darwin"
            #else
            let platform = "codex-darwin-x64"
            let target = "x86_64-apple-darwin"
            #endif
            let vendors = [package.deletingLastPathComponent().appendingPathComponent(platform).appendingPathComponent("vendor"),
                           package.appendingPathComponent("vendor")]
            for vendor in vendors {
                let root = vendor.appendingPathComponent(target)
                for suffix in ["CodexCLI.app/Contents/MacOS/codex", "bin/codex", "codex/codex"] {
                    let candidate = root.appendingPathComponent(suffix)
                    if isNativeExecutable(candidate) { return candidate }
                }
            }
        }
        throw UsageError.invalidConfiguration("A native Codex CLI is unavailable. Reinstall the Codex CLI or install the Codex desktop app.")
    }

    private static func isNativeExecutable(_ url: URL) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: url.path),
              let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        guard let data = try? file.read(upToCount: 4), data.count == 4 else { return false }
        let magic = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return [0xfeedface, 0xcefaedfe, 0xfeedfacf, 0xcffaedfe,
                0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca].contains(magic)
    }
}

struct CodexClient: Sendable {
    let executable: URL
    let home: URL
    var timeout: TimeInterval = 25

    struct Result: Sendable { let snapshot: AccountSnapshot; let accountIdentity: String?; let accountEmail: String? }

    func fetch(profileID: UUID, expectedIdentity: String?) throws -> Result {
        let connection = try CodexConnection(executable: executable, home: home, timeout: timeout)
        defer { connection.close() }
        struct ClientInfo: Encodable { let name = "ai_usage_stats"; let title = "AI Usage Stats"; let version = "0.1.0" }
        struct Initialize: Encodable { let clientInfo = ClientInfo() }
        struct Empty: Codable {}
        struct AccountParameters: Encodable { let refreshToken = false }
        struct Account: Decodable { let type: String; let email: String?; let planType: String? }
        struct AccountResponse: Decodable { let account: Account?; let requiresOpenaiAuth: Bool? }
        let _: Empty = try connection.request(method: "initialize", parameters: Initialize())
        try connection.notify(method: "initialized", parameters: Empty())
        let account: AccountResponse = try connection.request(method: "account/read", parameters: AccountParameters())
        guard account.account?.type == "chatgpt" else {
            throw UsageError.authenticationRequired("Sign in to this Codex profile in Terminal, then refresh.")
        }
        let response: CodexUsageResponse = try connection.request(method: "account/rateLimits/read", parameters: Empty())
        guard let identity = response.accountId, !identity.isEmpty else {
            throw UsageError.providerFailure("The Codex CLI did not provide an account identifier. Update the CLI and refresh.")
        }
        if let expectedIdentity, expectedIdentity != identity {
            throw UsageError.authenticationRequired("This Codex profile now belongs to a different login. Create a separate profile for that account.")
        }
        return Result(snapshot: response.snapshot(profileID: profileID, planType: account.account?.planType),
                      accountIdentity: identity, accountEmail: account.account?.email)
    }
}

private final class CodexConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var deadline: DispatchSourceTimer?
    private var buffer = Data()
    private var nextID = 1

    init(executable: URL, home: URL, timeout: TimeInterval) throws {
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        var environment = ProcessInfo.processInfo.environment
        environment["CODEX_HOME"] = home.path
        for name in ["CODEX_ACCESS_TOKEN", "CODEX_API_KEY", "OPENAI_API_KEY"] { environment.removeValue(forKey: name) }
        process.environment = environment
        process.currentDirectoryURL = home
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        let identifier = process.processIdentifier
        timer.setEventHandler { kill(identifier, SIGKILL) }
        timer.schedule(deadline: .now() + timeout)
        timer.resume()
        deadline = timer
    }

    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning {
            process.terminate()
            kill(process.processIdentifier, SIGKILL)
        }
        process.waitUntilExit()
        deadline?.cancel()
        deadline = nil
        try? output.fileHandleForReading.close()
    }

    private func send<Request: Encodable>(_ request: Request) throws {
        var data = try JSONEncoder().encode(request)
        data.append(0x0A)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func notify<Parameters: Encodable>(method: String, parameters: Parameters) throws {
        try send(CodexNotification(method: method, params: parameters))
    }

    func request<Response: Decodable, Parameters: Encodable>(method: String, parameters: Parameters) throws -> Response {
        let identifier = nextID
        nextID += 1
        try send(CodexRequest(id: identifier, method: method, params: parameters))
        while true {
            let line = try readLine()
            // Decode only the response matching our request. Notifications have another shape.
            guard let header = try? JSONDecoder().decode(CodexResponseIdentifier.self, from: line) else { continue }
            guard header.id == identifier, header.method == nil else { continue }
            let envelope = try JSONDecoder().decode(CodexResponseEnvelope<Response>.self, from: line)
            if let error = envelope.error {
                throw UsageError.providerFailure("Codex could not read usage (\(error.code)). Sign in again if this login expired.")
            }
            guard let result = envelope.result else { throw UsageError.providerFailure("Codex returned an empty response.") }
            return result
        }
    }

    private func readLine() throws -> Data {
        while true {
            if let newline = buffer.firstIndex(of: 0x0A) {
                let line = buffer.prefix(upTo: newline)
                buffer.removeSubrange(...newline)
                return Data(line)
            }
            let data = output.fileHandleForReading.availableData
            guard !data.isEmpty else {
                throw UsageError.providerFailure("The Codex CLI stopped or exceeded the 25-second refresh limit.")
            }
            buffer.append(data)
            guard buffer.count < 2_000_000 else { throw UsageError.providerFailure("Codex returned an oversized response.") }
        }
    }
}
