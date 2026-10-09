import Foundation

public actor UsageService {
    private let storage: ConfigurationStorage
    private let captureHelperURL: URL
    private let codexExecutableURL: URL?
    private var configuration = StoredConfiguration()
    private var loaded = false
    private var refreshes: [UUID: Task<AccountSnapshot, Never>] = [:]
    private let freshnessInterval: TimeInterval = 300

    public init(directory: URL = UsagePaths.applicationSupport, captureHelperURL: URL? = nil,
                codexExecutableURL: URL? = nil) {
        storage = ConfigurationStorage(directory: directory)
        self.captureHelperURL = captureHelperURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/UsageCapture")
        self.codexExecutableURL = codexExecutableURL
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        configuration = try storage.load()
        loaded = true
    }

    public func load() throws -> [AccountProfile] {
        try ensureLoaded()
        return configuration.profiles
    }

    public func snapshot(for accountID: UUID) -> AccountSnapshot? {
        guard let profile = configuration.profiles.first(where: { $0.id == accountID }) else { return nil }
        let saved = configuration.snapshots.first(where: { $0.profileID == accountID })
            ?? AccountSnapshot(profileID: accountID, state: .unavailable,
                               detail: profile.provider == .claude
                               ? "Usage appears after the next Claude response in this configuration directory."
                               : "Sign in to this Codex profile, then refresh.")
        let stale = saved.state == .available && (saved.fetchedAt.map { Date().timeIntervalSince($0) > freshnessInterval } == true
                                                 || saved.windows.contains { $0.resetsAt.map { $0 <= Date() } == true })
        return decorate(saved, state: stale ? .stale : saved.state,
                        detail: stale ? "Saved usage is old or a reported reset has passed. Refresh to check again." : saved.detail)
    }

    public func importClaudeCLI(label: String, configurationURL: URL? = nil) throws -> AccountProfile {
        try ensureLoaded()
        let sourceURL = (configurationURL
                         ?? ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"].map { URL(fileURLWithPath: $0) }
                         ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude"))
            .standardizedFileURL.resolvingSymlinksInPath()
        if let existing = configuration.profiles.first(where: { $0.provider == .claude && $0.sourcePath == sourceURL.path }) {
            return existing
        }
        let profile = AccountProfile(provider: .claude, label: try validLabel(label), source: .claudeCLI,
                                     sourcePath: sourceURL.path)
        let stableHelper = storage.directory.appendingPathComponent("UsageCapture")
        guard FileManager.default.isExecutableFile(atPath: captureHelperURL.path) else {
            throw UsageError.invalidConfiguration("Usage capture helper is missing. Open the packaged AI Usage Stats app.")
        }
        try UsagePaths.writePrivate(Data(contentsOf: captureHelperURL), to: stableHelper, permissions: 0o700)
        let installation = try ClaudeCaptureInstallation.install(profileID: profile.id, configurationURL: sourceURL,
                                                                 helperURL: stableHelper, storageDirectory: storage.directory)
        var updated = configuration
        updated.profiles.append(profile)
        updated.captureInstallations[profile.id.uuidString] = installation
        do {
            try storage.save(updated)
            configuration = updated
        } catch {
            try? ClaudeCaptureInstallation.remove(installation)
            throw error
        }
        return profile
    }

    public func createCodexProfile(label: String) throws -> AccountProfile {
        try ensureLoaded()
        let identifier = UUID()
        let home = storage.directory.appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(identifier.uuidString, isDirectory: true).appendingPathComponent("Codex", isDirectory: true)
        let profile = AccountProfile(id: identifier, provider: .codex, label: try validLabel(label),
                                     source: .codexCLI, sourcePath: home.path)
        _ = try codexExecutable()
        try UsagePaths.writePrivate(Data("cli_auth_credentials_store = \"keyring\"\n".utf8),
                                    to: home.appendingPathComponent("config.toml"))
        var updated = configuration
        updated.profiles.append(profile)
        do {
            try storage.save(updated)
            configuration = updated
        } catch {
            try? FileManager.default.removeItem(at: home.deletingLastPathComponent())
            throw error
        }
        return profile
    }

    public func codexLoginCommand(accountID: UUID) throws -> String {
        try ensureLoaded()
        guard let profile = configuration.profiles.first(where: { $0.id == accountID }),
              profile.provider == .codex, let sourcePath = profile.sourcePath else {
            throw UsageError.invalidConfiguration("Select a Codex profile first.")
        }
        return "cd \(ClaudeCaptureInstallation.shellQuote(sourcePath)) && env -u CODEX_ACCESS_TOKEN -u CODEX_API_KEY -u OPENAI_API_KEY CODEX_HOME=\(ClaudeCaptureInstallation.shellQuote(sourcePath)) \(ClaudeCaptureInstallation.shellQuote(try codexExecutable().path)) login"
    }

    public func renameAccount(id: UUID, label: String) throws {
        try ensureLoaded()
        guard let index = configuration.profiles.firstIndex(where: { $0.id == id }) else { return }
        var updated = configuration
        updated.profiles[index].label = try validLabel(label)
        try storage.save(updated)
        configuration = updated
    }

    public func removeAccount(id: UUID) throws {
        try ensureLoaded()
        if let installation = configuration.captureInstallations[id.uuidString] {
            try ClaudeCaptureInstallation.remove(installation)
        }
        var updated = configuration
        updated.profiles.removeAll { $0.id == id }
        updated.snapshots.removeAll { $0.profileID == id }
        updated.manualCredits.removeValue(forKey: id.uuidString)
        updated.captureInstallations.removeValue(forKey: id.uuidString)
        updated.consoleConnections.removeValue(forKey: id.uuidString)
        updated.consoleObservations.removeValue(forKey: id.uuidString)
        try storage.save(updated)
        configuration = updated
        try? FileManager.default.removeItem(at: UsagePaths.captureURL(profileID: id, directory: storage.directory))
        // Codex homes and their CLI-owned Keychain entries are retained. Removing a row must not revoke a login.
    }

    public func setManualCredit(accountID: UUID, credit: CreditBalance) throws {
        try ensureLoaded()
        guard configuration.profiles.contains(where: { $0.id == accountID }),
              ["api_balance", "monthly_grant"].contains(credit.id), credit.unit == .usd else {
            throw UsageError.invalidConfiguration("Manual amounts belong to an account's API balance or monthly grant.")
        }
        guard let profile = configuration.profiles.first(where: { $0.id == accountID }),
              profile.provider == .claude || credit.id == "api_balance" else {
            throw UsageError.invalidConfiguration("The Codex connection does not expose a monthly API grant.")
        }
        if let amount = credit.amount, amount < 0 {
            throw UsageError.invalidConfiguration("A credit balance cannot be negative.")
        }
        let manual = CreditBalance(id: credit.id, title: credit.title, amount: credit.amount, unit: credit.unit,
                                   expiresAt: credit.expiresAt, source: .manual, asOf: credit.asOf ?? Date(),
                                   detail: "User-entered balance. Verify it in the provider's billing page.")
        var updated = configuration
        var credits = updated.manualCredits[accountID.uuidString] ?? []
        credits.removeAll { $0.id == credit.id }
        if credit.amount != nil { credits.append(manual) }
        updated.manualCredits[accountID.uuidString] = credits
        try storage.save(updated)
        configuration = updated
    }

    public func manualCredits(for accountID: UUID) -> [CreditBalance] {
        configuration.manualCredits[accountID.uuidString] ?? []
    }

    public func consoleConnection(for accountID: UUID) -> String? {
        configuration.consoleConnections[accountID.uuidString]
    }

    public func setClaudeConsoleConnection(accountID: UUID, organizationID: String?) throws {
        try ensureLoaded()
        guard configuration.profiles.contains(where: { $0.id == accountID && $0.provider == .claude }) else {
            throw UsageError.invalidConfiguration("Select a Claude profile to connect Console billing.")
        }
        if let organizationID, UUID(uuidString: organizationID) == nil {
            throw UsageError.invalidConfiguration("The Claude Console organization identifier must be a UUID.")
        }
        let organizationID = organizationID.flatMap { UUID(uuidString: $0)?.uuidString.lowercased() }
        var updated = configuration
        if updated.consoleConnections[accountID.uuidString] != organizationID {
            updated.consoleObservations.removeValue(forKey: accountID.uuidString)
        }
        updated.consoleConnections[accountID.uuidString] = organizationID
        try storage.save(updated)
        configuration = updated
    }

    public func updateClaudeConsoleCredits(accountID: UUID, organizationID: String, responseData: Data) throws {
        try ensureLoaded()
        guard let connectedOrganization = configuration.consoleConnections[accountID.uuidString],
              UUID(uuidString: organizationID)?.uuidString.lowercased() == connectedOrganization,
              configuration.profiles.contains(where: { $0.id == accountID && $0.provider == .claude }) else {
            throw UsageError.invalidConfiguration("The Console response no longer matches this profile's connected organization.")
        }
        let balance = try ClaudeConsoleBalance.decode(responseData, organizationID: connectedOrganization)
        var updated = configuration
        updated.consoleObservations[accountID.uuidString] = ConsoleCreditObservation(organizationID: balance.organizationID,
                                                                                   observedAt: balance.observedAt, credits: balance.credits)
        try storage.save(updated)
        configuration = updated
    }

    public func refreshAccount(id: UUID) async -> AccountSnapshot {
        if let active = refreshes[id] { return await active.value }
        do { try ensureLoaded() } catch {
            return AccountSnapshot(profileID: id, state: .unavailable, detail: error.localizedDescription)
        }
        guard let profile = configuration.profiles.first(where: { $0.id == id }) else {
            return AccountSnapshot(profileID: id, state: .unavailable, detail: "Account profile was removed.")
        }
        let task = Task { await self.fetch(profile) }
        refreshes[id] = task
        let result = await task.value
        refreshes.removeValue(forKey: id)
        return result
    }

    public func refreshAll() async -> [AccountSnapshot] {
        do { try ensureLoaded() } catch { return [] }
        let identifiers = configuration.profiles.map(\.id)
        var results: [AccountSnapshot] = []
        for identifier in identifiers { results.append(await refreshAccount(id: identifier)) }
        return results
    }

    private func fetch(_ profile: AccountProfile) async -> AccountSnapshot {
        var observed: AccountSnapshot
        do {
            if profile.provider == .claude {
                let url = UsagePaths.captureURL(profileID: profile.id, directory: storage.directory)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw UsageError.providerFailure("Waiting for a Claude response in this configuration directory. Refresh reads captured usage; it does not send a Claude request.")
                }
                let capture = try JSONDecoder().decode(ClaudeQuotaCapture.self, from: Data(contentsOf: url))
                guard capture.profileID == profile.id else {
                    throw UsageError.providerFailure("The captured usage belongs to another profile.")
                }
                let stale = Date().timeIntervalSince(capture.observedAt) > freshnessInterval
                    || capture.windows.contains { $0.resetsAt.map { $0 <= Date() } == true }
                observed = AccountSnapshot(profileID: profile.id, fetchedAt: capture.observedAt,
                                           windows: capture.windows, state: capture.windows.isEmpty ? .unavailable : stale ? .stale : .available,
                                           detail: capture.windows.isEmpty
                                           ? "Claude has not supplied quota data. Status-line quotas require an eligible subscription and a Claude response."
                                           : "Current login in this Claude configuration directory. Timestamp records the last quota change, not a live refresh.")
            } else {
                guard let path = profile.sourcePath else { throw UsageError.invalidConfiguration("Codex profile directory is missing.") }
                let client = CodexClient(executable: try codexExecutable(), home: URL(fileURLWithPath: path))
                let result = try await Task.detached(priority: .utility) {
                    try client.fetch(profileID: profile.id, expectedIdentity: profile.providerAccountID)
                }.value
                observed = result.snapshot
                if profile.providerAccountID == nil, let identity = result.accountIdentity,
                   let index = configuration.profiles.firstIndex(where: { $0.id == profile.id }) {
                    configuration.profiles[index] = AccountProfile(id: profile.id, provider: profile.provider,
                                                                  label: configuration.profiles[index].label, source: profile.source,
                                                                  providerAccountID: identity, sourcePath: profile.sourcePath)
                }
            }
        } catch {
            let authentication: Bool
            if case UsageError.authenticationRequired = error { authentication = true } else { authentication = false }
            let previous = configuration.snapshots.first { $0.profileID == profile.id }
            observed = AccountSnapshot(profileID: profile.id, fetchedAt: previous?.fetchedAt,
                                       windows: previous?.windows ?? [], credits: previous?.credits ?? [],
                                       state: authentication ? .authenticationRequired : previous?.fetchedAt == nil ? .unavailable : .stale,
                                       detail: error.localizedDescription)
        }
        if configuration.profiles.contains(where: { $0.id == profile.id }) {
            configuration.snapshots.removeAll { $0.profileID == profile.id }
            configuration.snapshots.append(observed)
            do { try storage.save(configuration) } catch {
                observed = AccountSnapshot(profileID: observed.profileID, fetchedAt: observed.fetchedAt,
                                           windows: observed.windows, credits: observed.credits, state: observed.state,
                                           detail: "Usage read, but could not save it: \(error.localizedDescription)")
            }
        }
        return decorate(observed, state: observed.state, detail: observed.detail)
    }

    private func decorate(_ snapshot: AccountSnapshot, state: SnapshotState, detail: String?) -> AccountSnapshot {
        var credits = snapshot.credits.filter { $0.source == .provider }
        let console = configuration.consoleObservations[snapshot.profileID.uuidString]
        if let console, console.organizationID == configuration.consoleConnections[snapshot.profileID.uuidString] {
            credits.append(contentsOf: console.credits)
        }
        let provider = configuration.profiles.first { $0.id == snapshot.profileID }?.provider ?? .claude
        for credit in Self.unavailableCredits(for: provider) where !credits.contains(where: { $0.id == credit.id }) {
            if credit.id == "api_balance", credits.contains(where: { $0.id.hasPrefix("api_balance_") }) { continue }
            if credit.id == "monthly_grant", credits.contains(where: { $0.id.hasPrefix("console_grant_") }) { continue }
            credits.append(credit)
        }
        for credit in configuration.manualCredits[snapshot.profileID.uuidString] ?? [] {
            if credit.id == "api_balance", credits.contains(where: { $0.id.hasPrefix("api_balance_") }) { continue }
            credits.removeAll { $0.id == credit.id }
            credits.append(credit)
        }
        return AccountSnapshot(profileID: snapshot.profileID, fetchedAt: snapshot.fetchedAt, windows: snapshot.windows,
                               credits: credits, state: state, detail: detail)
    }

    public static var unavailableAPICredits: [CreditBalance] {
        unavailableCredits(for: .claude)
    }

    public static func unavailableCredits(for provider: Provider) -> [CreditBalance] {
        var credits = [CreditBalance(id: "api_balance", title: provider == .claude ? "Purchased API credits" : "OpenAI API credits", amount: nil,
                       detail: "The connected CLI does not expose API billing balances."),
        ]
        if provider == .claude {
            credits.append(CreditBalance(id: "monthly_grant", title: "Monthly included API grant", amount: nil,
                                        detail: "The connected CLI does not expose remaining grants or their expiry."))
        } else {
            credits.append(CreditBalance(id: "provider_credits", title: "Codex credits", amount: nil, unit: .credits,
                                        detail: "Codex has not supplied a credit balance."))
        }
        return credits
    }

    private func codexExecutable() throws -> URL { try codexExecutableURL ?? CodexExecutable.resolve() }

    private func validLabel(_ label: String) throws -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw UsageError.invalidConfiguration("Enter an account name.") }
        return trimmed
    }
}
