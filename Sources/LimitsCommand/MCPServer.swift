import Foundation
import UsageCore

struct DigestSource {
    let url: URL

    func read() throws -> LimitsDigest { try LimitsDigest.read(from: url).revalidated(at: Date()) }

    static func missingMessage(_ error: Error, url: URL) -> String {
        if (error as NSError).domain == NSCocoaErrorDomain, (error as NSError).code == NSFileReadNoSuchFileError {
            return "Little Limits has not written its limits file yet (\(url.path)). Open Little Limits; it writes the file after each refresh."
        }
        return "Could not read the Little Limits limits file (\(url.path)): \(error.localizedDescription)"
    }
}

struct MCPServer {
    static let legacyVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]
    static let modernVersions = ["2026-07-28"]
    static let protocolVersionKey = "io.modelcontextprotocol/protocolVersion"

    let source: DigestSource
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
    private let digestEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    struct Failure: Error {
        let code: Int
        let message: String
        var data: JSONValue?
    }

    func run() {
        while let line = readLine(strippingNewline: true) {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let message = try? JSONDecoder().decode(JSONValue.self, from: Data(line.utf8)),
                  case .object = message else {
                send(["jsonrpc": "2.0", "id": .null, "error": ["code": -32700, "message": "Parse error"]])
                continue
            }
            guard let id = message["id"], id != .null else { continue }
            guard let method = message["method"]?.string else {
                if message["result"] == nil, message["error"] == nil {
                    send(["jsonrpc": "2.0", "id": id, "error": ["code": -32600, "message": "Invalid request"]])
                }
                continue
            }
            let params = message["params"] ?? [:]
            do {
                var result = try respond(method: method, params: params)
                if isModern(params), case .object(var object) = result {
                    object["resultType"] = "complete"
                    result = .object(object)
                }
                send(["jsonrpc": "2.0", "id": id, "result": result])
            } catch let failure as Failure {
                var error: [String: JSONValue] = ["code": .integer(failure.code), "message": .string(failure.message)]
                if let data = failure.data { error["data"] = data }
                send(["jsonrpc": "2.0", "id": id, "error": .object(error)])
            } catch {
                send(["jsonrpc": "2.0", "id": id, "error": ["code": -32603, "message": .string(error.localizedDescription)]])
            }
        }
    }

    private func send(_ message: JSONValue) {
        guard var data = try? encoder.encode(message) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
    }

    private func isModern(_ params: JSONValue) -> Bool {
        params["_meta"]?[Self.protocolVersionKey]?.string.map(Self.modernVersions.contains) == true
    }

    private func respond(method: String, params: JSONValue) throws -> JSONValue {
        if let requested = params["_meta"]?[Self.protocolVersionKey]?.string, !Self.modernVersions.contains(requested) {
            throw Failure(code: -32022, message: "Unsupported protocol version",
                          data: ["supported": .array((Self.modernVersions + Self.legacyVersions).map(JSONValue.string)),
                                 "requested": .string(requested)])
        }
        switch method {
        case "initialize":
            let requested = params["protocolVersion"]?.string ?? Self.legacyVersions[0]
            return ["protocolVersion": .string(Self.legacyVersions.contains(requested) ? requested : Self.legacyVersions[0]),
                    "capabilities": capabilities, "serverInfo": serverInfo, "instructions": .string(instructions)]
        case "server/discover":
            return ["supportedVersions": .array((Self.modernVersions + Self.legacyVersions).map(JSONValue.string)),
                    "capabilities": capabilities, "_meta": ["io.modelcontextprotocol/serverInfo": serverInfo],
                    "instructions": .string(instructions)]
        case "ping":
            return [:]
        case "tools/list":
            return ["tools": .array(Tool.allCases.map(\.definition))]
        case "tools/call":
            guard let name = params["name"]?.string, let tool = Tool(rawValue: name) else {
                throw Failure(code: -32602, message: "Unknown tool: \(params["name"]?.string ?? "none")")
            }
            return call(tool, arguments: params["arguments"] ?? [:])
        case "resources/list":
            return ["resources": [
                ["uri": "limits://overview", "name": "overview", "title": "Little Limits overview",
                 "description": "What is left on each account, when it resets, and which account to use now, as a table.",
                 "mimeType": "text/plain"],
                ["uri": "limits://overview.json", "name": "overview.json", "title": "Little Limits overview (JSON)",
                 "description": "The limits file Little Limits writes after each refresh.", "mimeType": "application/json"]
            ]]
        case "resources/templates/list":
            return ["resourceTemplates": []]
        case "resources/read":
            let uri = params["uri"]?.string ?? ""
            guard uri == "limits://overview" || uri == "limits://overview.json" else {
                throw Failure(code: -32002, message: "Resource not found", data: ["uri": .string(uri)])
            }
            let text: String
            do {
                let digest = try source.read()
                text = uri == "limits://overview" ? LimitsDigestText.overview(digest, now: Date())
                    : String(decoding: try digest.encoded(), as: UTF8.self)
            } catch {
                text = DigestSource.missingMessage(error, url: source.url)
            }
            return ["contents": [["uri": .string(uri), "mimeType": uri.hasSuffix(".json") ? "application/json" : "text/plain",
                                  "text": .string(text)]]]
        case "prompts/list":
            return ["prompts": [["name": "where-are-my-limits", "title": "Where are my limits",
                                 "description": "Ask where each Claude and Codex account stands and which one to use now."]]]
        case "prompts/get":
            guard params["name"]?.string == "where-are-my-limits" else {
                throw Failure(code: -32602, message: "Unknown prompt: \(params["name"]?.string ?? "none")")
            }
            return ["description": "Where each Claude and Codex account stands",
                    "messages": [["role": "user", "content": ["type": "text", "text": """
                        Where are my Claude and Codex accounts at? Call the little-limits limits_overview tool, then show me the table \
                        and the Use now lines. Say plainly which accounts are stale or need sign-in, and how old the reading is. \
                        Quote percentages as what is left, never as what is used.
                        """]]]]
        default:
            throw Failure(code: -32601, message: "Method not found: \(method)")
        }
    }

    private var capabilities: JSONValue {
        ["tools": ["listChanged": false], "resources": ["listChanged": false, "subscribe": false], "prompts": ["listChanged": false]]
    }

    private var serverInfo: JSONValue {
        ["name": "little-limits", "title": "Little Limits", "version": .string(Self.version)]
    }

    private var instructions: String {
        """
        Little Limits reports what is left on each Claude and Codex subscription account on this Mac, when each window resets, \
        earned resets with each expiry, Claude API credits, Codex credits, and which account to use now. Every number is what is left, never what is used. \
        Answers come from the file the Little Limits app writes after each refresh; check as_of, age_minutes and stale before \
        treating a value as current. A null value is unknown, never zero. The tools are read-only and never refresh, buy, or reset anything.
        """
    }

    static var version: String {
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
        let plist = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Info.plist")
        let info = NSDictionary(contentsOf: plist)
        return info?["CFBundleShortVersionString"] as? String ?? "development"
    }

    enum Tool: String, CaseIterable {
        case limitsOverview = "limits_overview"
        case pickAccount = "pick_account"
        case upcomingResets = "upcoming_resets"
        case earnedResets = "earned_resets"
        case apiCredits = "api_credits"

        var definition: JSONValue {
            let provider: JSONValue = ["type": "string", "enum": ["claude", "codex"]]
            let (title, description, schema): (String, String, JSONValue) = switch self {
            case .limitsOverview:
                ("Limits overview",
                 "Where are my accounts at: weekly and 5-hour quota left on every Claude and Codex account, when each resets, earned resets, Claude API credits, Codex credits, and which account to use now.",
                 ["type": "object", "properties": ["provider": provider]])
            case .pickAccount:
                ("Pick an account",
                 "Which account to use now for a provider, with the reason and the runner-up. need=weekly (default) favors quota that would otherwise reset unused; need=session favors the most 5-hour quota left.",
                 ["type": "object", "properties": ["provider": provider, "need": ["type": "string", "enum": ["weekly", "session"]]],
                  "required": ["provider"]])
            case .upcomingResets:
                ("Upcoming resets",
                 "Quota window resets in time order, with what is left in each window now. Credit expiry is not included.",
                 ["type": "object", "properties": ["within_days": ["type": "number", "minimum": 0, "default": 7]]])
            case .earnedResets:
                ("Earned resets",
                 "Banked quota resets: the Codex count and the expiry of each one. Little Limits does not read Claude limit resets yet.",
                 ["type": "object", "properties": [:]])
            case .apiCredits:
                ("API credits",
                 "Claude API credits read from the Claude Platform (experimental): purchased, monthly grant and promotional amounts kept apart, each with its expiry. Codex credits as Codex reports them, with when they were read.",
                 ["type": "object", "properties": [:]])
            }
            return ["name": .string(rawValue), "title": .string(title), "description": .string(description), "inputSchema": schema,
                    "annotations": ["title": .string(title), "readOnlyHint": true, "destructiveHint": false,
                                    "idempotentHint": true, "openWorldHint": false]]
        }
    }

    private func call(_ tool: Tool, arguments: JSONValue) -> JSONValue {
        let digest: LimitsDigest
        do { digest = try source.read() } catch {
            return ["content": [["type": "text", "text": .string(DigestSource.missingMessage(error, url: source.url))]], "isError": true]
        }
        let now = Date()
        let calendar = LimitsDigestText.calendar(for: digest)
        let heading = LimitsDigestText.heading(digest, now: now, calendar: calendar)
        do {
            let (text, structured): (String, [String: JSONValue])
            switch tool {
            case .limitsOverview:
                let provider = try self.provider(arguments["provider"], required: false)
                let accounts = digest.accounts.filter { provider == nil || $0.provider == provider }
                let picks = digest.useNow.filter { provider == nil || $0.provider == provider }
                text = LimitsDigestText.overview(digest, now: now, provider: provider)
                structured = ["accounts": try encode(accounts), "use_now": try encode(picks)]
            case .pickAccount:
                guard let provider = try self.provider(arguments["provider"], required: true) else { throw Failure(code: -32602, message: "provider is required") }
                let need = try arguments["need"].map { value -> UseNowNeed in
                    guard let need = value.string.flatMap(UseNowNeed.init(rawValue:)) else {
                        throw Failure(code: -32602, message: "need must be weekly or session")
                    }
                    return need
                } ?? .weekly
                guard let pick = digest.useNow.first(where: { $0.provider == provider && $0.need == need }) else {
                    text = "\(heading)\nNo \(provider.title) accounts are set up in Little Limits."
                    structured = ["pick": .null]
                    break
                }
                var lines = [heading, LimitsDigestText.useNowLine(pick)]
                if let runnerUp = pick.runnerUp { lines.append("Runner-up: \(runnerUp).") }
                text = lines.joined(separator: "\n")
                structured = ["pick": try encode(pick)]
            case .upcomingResets:
                let days = arguments["within_days"]?.number ?? 7
                guard days.isFinite, days >= 0 else { throw Failure(code: -32602, message: "within_days must be a number of days, 0 or more") }
                let limit = now.addingTimeInterval(days * 86_400)
                let events = digest.accounts.flatMap { account in
                    account.windows.compactMap { window -> (account: LimitsDigest.Account, window: LimitsDigest.Window, date: Date)? in
                        guard let date = window.resetsAt, date > now, date <= limit else { return nil }
                        return (account, window, date)
                    }
                }.sorted { $0.date < $1.date }
                var lines = [heading, ""]
                lines += events.isEmpty ? ["No quota resets in the next \(Self.dayText(days))."] : events.map { event in
                    let left = LimitsDigestText.windowValue(event.window)
                    let note = LimitsDigestText.stateNote(event.account, now: now).map { " (\($0))" } ?? ""
                    return "\(LimitsDigestText.moment(event.date, now: now, calendar: calendar)): "
                        + "\(LimitsDigestText.accountName(event.account)) \(event.window.kind), \(left) left\(note)"
                }
                text = lines.joined(separator: "\n")
                structured = ["resets": .array(try events.map { event in
                    ["account": .string(event.account.label), "provider": .string(event.account.provider.rawValue),
                     "state": .string(event.account.state.rawValue), "window": try encode(event.window)]
                })]
            case .earnedResets:
                text = [heading, LimitsDigestText.earnedResetsLine(digest.accounts, now: now, calendar: calendar)
                    ?? "No accounts are set up in Little Limits."].joined(separator: "\n")
                structured = ["accounts": .array(try digest.accounts.map { account in
                    ["account": .string(account.label), "provider": .string(account.provider.rawValue),
                     "state": .string(account.state.rawValue), "earned_resets": try encode(account.earnedResets)]
                })]
            case .apiCredits:
                let lines = LimitsDigestText.apiCreditLines(digest.accounts, now: now, calendar: calendar)
                    + LimitsDigestText.codexCreditLines(digest.accounts, now: now, calendar: calendar)
                text = ([heading] + (lines.isEmpty ? ["No Claude accounts or Codex credits are in Little Limits."] : lines)).joined(separator: "\n")
                structured = ["accounts": .array(try digest.accounts.compactMap { account -> JSONValue? in
                    let entry: JSONValue
                    switch account.provider {
                    case .claude:
                        entry = ["account": .string(account.label), "provider": .string(account.provider.rawValue),
                                 "api_credits": try encode(account.apiCredits), "api_usable": try encode(account.apiUsable)]
                    case .codex:
                        guard let credits = account.credits else { return nil }
                        entry = ["account": .string(account.label), "provider": .string(account.provider.rawValue),
                                 "state": .string(account.state.rawValue), "credits": try encode(credits)]
                    }
                    return entry
                })]
            }
            var content = structured
            content["as_of"] = .string(ISO8601DateFormatter().string(from: digest.asOf))
            content["age_minutes"] = .integer(Int(digest.age(at: now) / 60))
            content["stale"] = .bool(digest.isOutdated(at: now))
            return ["content": [["type": "text", "text": .string(text)]], "structuredContent": .object(content), "isError": false]
        } catch let failure as Failure {
            return ["content": [["type": "text", "text": .string(failure.message)]], "isError": true]
        } catch {
            return ["content": [["type": "text", "text": .string(error.localizedDescription)]], "isError": true]
        }
    }

    private func provider(_ value: JSONValue?, required: Bool) throws -> Provider? {
        guard let value, value != .null else {
            if required { throw Failure(code: -32602, message: "provider is required: claude or codex") }
            return nil
        }
        guard let provider = value.string.flatMap({ Provider(rawValue: $0.lowercased()) }) else {
            throw Failure(code: -32602, message: "provider must be claude or codex")
        }
        return provider
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> JSONValue {
        try JSONValue(encoding: value, encoder: digestEncoder)
    }

    private static func dayText(_ days: Double) -> String {
        if days == 1 { return "day" }
        return days == days.rounded() ? "\(Int(days)) days" : String(format: "%.1f days", days)
    }
}
