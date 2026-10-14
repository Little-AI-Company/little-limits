import Foundation

public actor UsageService {
    private let storage: ConfigurationStorage
    private let captureHelperURL: URL
    private let codexExecutableURL: URL?
    private let codexDefaultHomeURL: URL?
    private var configuration = StoredConfiguration()
    private var loaded = false
    private var refreshes: [UUID: Task<AccountSnapshot, Never>] = [:]
    private var refreshIdentifiers: [UUID: UUID] = [:]
    private let claudeClient: ClaudeOAuthClient
    private let claudeCredentials: any ClaudeCredentialStore
    private var generations: [UUID: Int] = [:]
    private struct PendingClaudeAuthorization {
        let authorization: ClaudeAuthorization
        let profileID: UUID
        let label: String?
        let generation: Int
    }
    private var claudeAuthorizations: [UUID: PendingClaudeAuthorization] = [:]
    private var completingClaudeAuthorizations: Set<UUID> = []
    private var claudeCaptureCleanupMessages: [UUID: String] = [:]
    private let freshnessInterval: TimeInterval = 300

    /// `codexDefaultHomeURL` replaces the Codex CLI's own home (`$CODEX_HOME`, else `~/.codex`) for tests.
    public init(directory: URL = UsagePaths.applicationSupport, captureHelperURL: URL? = nil,
                codexExecutableURL: URL? = nil, codexDefaultHomeURL: URL? = nil) {
        storage = ConfigurationStorage(directory: directory)
        self.captureHelperURL = captureHelperURL
            ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/UsageCapture")
        self.codexExecutableURL = codexExecutableURL
        self.codexDefaultHomeURL = codexDefaultHomeURL
        claudeClient = ClaudeOAuthClient()
        claudeCredentials = ClaudeKeychainStore()
    }

    init(directory: URL, captureHelperURL: URL? = nil, claudeClient: ClaudeOAuthClient,
         claudeCredentials: any ClaudeCredentialStore) {
        storage = ConfigurationStorage(directory: directory)
        self.captureHelperURL = captureHelperURL ?? directory.appendingPathComponent("UsageCapture")
        codexExecutableURL = nil
        codexDefaultHomeURL = nil
        self.claudeClient = claudeClient
        self.claudeCredentials = claudeCredentials
    }

    public func prepareClaudeSignIn(existingProfileID: UUID? = nil, label: String? = nil) throws -> ClaudeAuthorizationRequest {
        try ensureLoaded()
        try retryClaudeCredentialCleanup(allowInteraction: true)
        if let existingProfileID {
            guard configuration.profiles.contains(where: { $0.id == existingProfileID && $0.provider == .claude }) else {
                throw UsageError.invalidConfiguration("Select a Claude account to reconnect.")
            }
        }
        let profileID = existingProfileID ?? UUID()
        let authorization = try ClaudeAuthorization()
        let validName = try label.map(validLabel)
        generations[profileID, default: 0] += 1
        claudeAuthorizations[authorization.request.id] = PendingClaudeAuthorization(
            authorization: authorization, profileID: profileID, label: validName, generation: generations[profileID, default: 0])
        return authorization.request
    }

    public func allowClaudeKeychainAccess(id: UUID) throws {
        try ensureLoaded()
        guard let profile = configuration.profiles.first(where: { $0.id == id && $0.provider == .claude && $0.source == .claudeOAuth }),
              let credentials = try claudeCredentials.read(accountID: id, allowInteraction: true),
              credentials.identity == profile.providerAccountID else {
            throw UsageError.authenticationRequired("Claude credentials are missing or belong to another account. Reconnect this account.")
        }
    }

    public func cancelClaudeSignIn(id: UUID) {
        guard let pending = claudeAuthorizations.removeValue(forKey: id) else { return }
        if generations[pending.profileID, default: 0] == pending.generation {
            generations[pending.profileID, default: 0] += 1
        }
    }

    public func completeClaudeSignIn(requestID: UUID, callbackURL: URL) async throws -> AccountProfile {
        guard let pending = claudeAuthorizations[requestID] else {
            throw UsageError.authenticationRequired("Claude sign-in is no longer active. Try again.")
        }
        guard completingClaudeAuthorizations.insert(requestID).inserted else {
            throw UsageError.authenticationRequired("Claude sign-in is already being completed.")
        }
        defer {
            claudeAuthorizations.removeValue(forKey: requestID)
            completingClaudeAuthorizations.remove(requestID)
        }
        let code = try pending.authorization.code(from: callbackURL)
        let token = try await claudeClient.exchange(pending.authorization, code: code)
        // Validate the requested scopes before using the returned token for any account request.
        _ = try token.credentials(identity: "")
        try validateClaudeAuthorization(pending, requestID: requestID)
        let providerProfile = try await claudeClient.profile(accessToken: token.access_token)
        try validateClaudeAuthorization(pending, requestID: requestID)
        let existing = configuration.profiles.first { $0.id == pending.profileID }
        let identity = try providerProfile.resolvedIdentity(expected: existing?.providerAccountID,
                                                           tokenAccount: token.account?.uuid, tokenOrganization: token.organization?.uuid)
        let identityParts = identity.split(separator: "/")
        if configuration.profiles.contains(where: { profile in
            guard profile.id != pending.profileID, profile.provider == .claude,
                  let existingIdentity = profile.providerAccountID else { return false }
            let existingParts = existingIdentity.split(separator: "/")
            return existingParts.first == identityParts.first
                && (existingParts.count == 1 || identityParts.count == 1 || existingIdentity == identity)
        }) {
            throw UsageError.invalidConfiguration("This Claude account is already listed. Select it, then choose Reconnect.")
        }
        let reportedEmail = providerProfile.account.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        let verifiedEmail = existing?.providerAccountID == nil ? nil : existing?.providerEmail
        let profile = AccountProfile(id: pending.profileID, provider: .claude,
                                     label: existing?.label ?? pending.label ?? providerProfile.account.email ?? "Claude Account",
                                     source: .claudeOAuth, providerAccountID: identity,
                                     providerEmail: reportedEmail?.isEmpty == false ? reportedEmail : verifiedEmail)
        let credentials = try token.credentials(identity: identity)
        let previousCredentials = try claudeCredentials.read(accountID: profile.id, allowInteraction: true)
        // Keep the generated identifier durable before writing an otherwise unlisted grant.
        if previousCredentials == nil { try storage.markClaudeCredentialForCleanup(accountID: profile.id) }
        try claudeCredentials.save(credentials, accountID: profile.id, allowInteraction: true)
        var updated = configuration
        if let index = updated.profiles.firstIndex(where: { $0.id == profile.id }) { updated.profiles[index] = profile }
        else { updated.profiles.append(profile) }
        // A legacy capture cannot establish the identity of this new authorization.
        if existing?.providerAccountID == nil {
            updated.snapshots.removeAll { $0.profileID == profile.id }
        }
        if let existing, existing.providerAccountID == nil {
            updated.consoleConnections.removeValue(forKey: profile.id.uuidString)
            updated.consoleObservations.removeValue(forKey: profile.id.uuidString)
            var pending = updated.pendingManualCredits[profile.id.uuidString] ?? []
            for credit in updated.manualCredits.removeValue(forKey: profile.id.uuidString) ?? [] {
                pending.removeAll { $0.id == credit.id }
                pending.append(credit)
            }
            if !pending.isEmpty { updated.pendingManualCredits[profile.id.uuidString] = pending }
        }
        do { try storage.save(updated) }
        catch {
            do {
                if let previousCredentials { try claudeCredentials.save(previousCredentials, accountID: profile.id, allowInteraction: true) }
                else {
                    try claudeCredentials.remove(accountID: profile.id, allowInteraction: true)
                    try storage.removeClaudeCredentialCleanupMarker(accountID: profile.id)
                }
            } catch {
                throw UsageError.authenticationRequired(previousCredentials == nil
                    ? "The account could not be saved and its sign-in could not be removed. Cleanup will retry when accounts load or you choose Add Claude Account."
                    : "The account could not be saved and its previous sign-in could not be restored. Reconnect this account.")
            }
            throw UsageError.providerFailure("Claude sign-in completed, but the account could not be saved. Try again.")
        }
        configuration = updated
        retireClaudeCapture(accountID: profile.id)
        refreshes[profile.id]?.cancel()
        refreshes.removeValue(forKey: profile.id)
        refreshIdentifiers.removeValue(forKey: profile.id)
        _ = await refreshAccount(id: profile.id)
        return profile
    }

    private func validateClaudeAuthorization(_ pending: PendingClaudeAuthorization, requestID: UUID) throws {
        guard claudeAuthorizations[requestID] != nil,
              generations[pending.profileID, default: 0] == pending.generation, !Task.isCancelled else {
            throw UsageError.authenticationRequired("Claude sign-in was cancelled or the account changed. Try again.")
        }
    }

    private func ensureLoaded() throws {
        guard !loaded else { return }
        configuration = try storage.load()
        loaded = true
    }

    public func load() throws -> [AccountProfile] {
        try ensureLoaded()
        do { try retryClaudeCredentialCleanup(allowInteraction: false) }
        catch {
            // Keep recovery markers for interactive retry without hiding otherwise valid accounts.
        }
        for profile in configuration.profiles where profile.source == .claudeOAuth {
            retireClaudeCapture(accountID: profile.id)
        }
        return configuration.profiles
    }

    private func retryClaudeCredentialCleanup(allowInteraction: Bool) throws {
        for id in try storage.pendingClaudeCredentialAccountIDs() {
            guard !claudeAuthorizations.values.contains(where: { $0.profileID == id }) else { continue }
            do {
                if !configuration.profiles.contains(where: {
                    $0.id == id && $0.provider == .claude && $0.source == .claudeOAuth && $0.providerAccountID != nil
                }) {
                    try claudeCredentials.remove(accountID: id, allowInteraction: allowInteraction)
                }
                try storage.removeClaudeCredentialCleanupMarker(accountID: id)
            } catch {
                throw UsageError.authenticationRequired("An incomplete Claude sign-in still needs cleanup. Make Keychain and account storage available, then retry Add Claude Account.")
            }
        }
    }

    private func retireClaudeCapture(accountID: UUID) {
        guard let installation = configuration.captureInstallations[accountID.uuidString] else {
            claudeCaptureCleanupMessages[accountID] = nil
            return
        }
        do {
            guard try ClaudeCaptureInstallation.retire(installation) else {
                claudeCaptureCleanupMessages[accountID] = "The old Claude Code connection's settings changed, so its command was preserved. Remove that old command in Claude Code settings; your browser connection is saved."
                return
            }
            var updated = configuration
            updated.captureInstallations.removeValue(forKey: accountID.uuidString)
            try storage.save(updated)
            configuration = updated
            claudeCaptureCleanupMessages[accountID] = nil
        } catch {
            claudeCaptureCleanupMessages[accountID] = "Could not finish removing the old Claude Code connection. Your browser connection is saved. Reopen AI Usage Stats to retry."
        }
    }

    public func snapshot(for accountID: UUID) -> AccountSnapshot? {
        guard let profile = configuration.profiles.first(where: { $0.id == accountID }) else { return nil }
        let saved = configuration.snapshots.first(where: { $0.profileID == accountID })
            ?? AccountSnapshot(profileID: accountID, state: .unavailable,
                               detail: profile.provider == .claude
                               ? (profile.source == .claudeOAuth
                                  ? "Refresh to read this Claude account's current quota."
                                  : "Reconnect this account in your browser to read usage immediately.")
                               : "Sign in to this Codex profile, then refresh.")
        let stale = saved.state == .available && (saved.fetchedAt.map { Date().timeIntervalSince($0) > freshnessInterval } == true
                                                 || saved.currentWindows.contains { $0.resetsAt.map { $0 <= Date() } == true })
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

    /// The Codex CLI's default login on this Mac, when it is signed in with ChatGPT and no account reads it yet.
    /// Uses only `account/read`, which neither reads usage nor renews tokens. Returns nil when the home is absent,
    /// so detection never creates it.
    public func currentCodexLogin() async -> CodexCurrentLogin? {
        guard (try? ensureLoaded()) != nil else { return nil }
        let home = codexDefaultHome
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: home.path, isDirectory: &isDirectory), isDirectory.boolValue,
              !configuration.profiles.contains(where: { $0.provider == .codex && $0.sourcePath == home.path }),
              let executable = try? codexExecutable() else { return nil }
        let client = CodexClient(executable: executable, home: home, timeout: 10)
        guard let login = try? await Task.detached(priority: .userInitiated, operation: { try client.readLogin() }).value,
              login.isSignedIn else { return nil }
        let email = login.email?.trimmingCharacters(in: .whitespacesAndNewlines)
        return CodexCurrentLogin(email: email?.isEmpty == false ? email : nil, home: home)
    }

    /// Adds an account that reads the Codex CLI's default login in place. Nothing is written to that home; its
    /// credentials stay where the CLI stored them. Refuses a login whose Codex account is already listed.
    public func createCodexProfileUsingCurrentLogin(label: String) async throws -> AccountProfile {
        try ensureLoaded()
        let name = try validLabel(label)
        let home = codexDefaultHome
        guard FileManager.default.fileExists(atPath: home.path) else {
            throw UsageError.authenticationRequired("The Codex CLI on this Mac is not signed in. Choose Sign In with a Different Account… instead.")
        }
        let client = CodexClient(executable: try codexExecutable(), home: home)
        let identifier = UUID()
        let result = try await Task.detached(priority: .userInitiated) {
            try client.fetch(profileID: identifier, expectedIdentity: nil)
        }.value
        // Check after the read: another change may have listed this login meanwhile.
        guard let identity = result.accountIdentity else {
            throw UsageError.providerFailure("The Codex CLI did not provide an account identifier. Update the CLI and try again.")
        }
        if configuration.profiles.contains(where: { $0.provider == .codex && ($0.sourcePath == home.path || $0.providerAccountID == identity) }) {
            throw UsageError.invalidConfiguration("This Codex account is already listed. Select it in the sidebar.")
        }
        let email = result.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let profile = AccountProfile(id: identifier, provider: .codex, label: name, source: .codexDefaultLogin,
                                     providerAccountID: identity, providerEmail: email?.isEmpty == false ? email : nil,
                                     sourcePath: home.path)
        var updated = configuration
        updated.profiles.append(profile)
        updated.snapshots.append(result.snapshot)
        try storage.save(updated)
        configuration = updated
        return profile
    }

    /// Waits for a Terminal `codex login` into this account's own home, then refreshes the account once.
    /// Polls `account/read` every `interval`. Stops on sign-in, cancellation, removal of the account, or `timeout`.
    public func awaitCodexSignIn(id: UUID, interval: Duration = .seconds(3),
                                 timeout: Duration = .seconds(600)) async -> CodexSignInOutcome {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while true {
            guard !Task.isCancelled else { return .cancelled }
            guard (try? ensureLoaded()) != nil,
                  let profile = configuration.profiles.first(where: { $0.id == id && $0.provider == .codex }),
                  let path = profile.sourcePath else { return .accountRemoved }
            if let executable = try? codexExecutable() {
                let client = CodexClient(executable: executable, home: URL(fileURLWithPath: path), timeout: 10)
                let login = try? await Task.detached(priority: .utility, operation: { try client.readLogin() }).value
                if login?.isSignedIn == true {
                    guard !Task.isCancelled else { return .cancelled }
                    guard configuration.profiles.contains(where: { $0.id == id }) else { return .accountRemoved }
                    return .signedIn(await refreshAccount(id: id))
                }
            }
            guard clock.now < deadline else { return .timedOut }
            do { try await Task.sleep(for: min(interval, deadline - clock.now)) } catch { return .cancelled }
        }
    }

    public func codexLoginCommand(accountID: UUID) throws -> String {
        try ensureLoaded()
        guard let profile = configuration.profiles.first(where: { $0.id == accountID }),
              profile.provider == .codex, let sourcePath = profile.sourcePath else {
            throw UsageError.invalidConfiguration("Select a Codex profile first.")
        }
        // Signing in here would replace the CLI's own login, which monitoring must never change.
        guard profile.source != .codexDefaultLogin else {
            throw UsageError.invalidConfiguration("This account reads the Codex CLI login on this Mac. To sign in again, run codex login in Terminal, then choose Refresh All.")
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

    /// Moves the account so it sits at `index` in the saved order, counted after the account is taken out of the list.
    public func moveAccount(id: UUID, toIndex index: Int) throws {
        try ensureLoaded()
        guard let source = configuration.profiles.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(index, 0), configuration.profiles.count - 1)
        guard destination != source else { return }
        var updated = configuration
        let profile = updated.profiles.remove(at: source)
        updated.profiles.insert(profile, at: destination)
        try storage.save(updated)
        configuration = updated
    }

    public func removeAccount(id: UUID) throws {
        try ensureLoaded()
        generations[id, default: 0] += 1
        refreshes[id]?.cancel()
        let ownsClaudeCredentials = configuration.profiles.first(where: { $0.id == id })?.source == .claudeOAuth
        let savedCredentials = ownsClaudeCredentials ? try claudeCredentials.read(accountID: id, allowInteraction: true) : nil
        if let installation = configuration.captureInstallations[id.uuidString] {
            guard try ClaudeCaptureInstallation.retire(installation) else {
                throw UsageError.invalidConfiguration("The account was not removed because its old Claude Code status line still runs the capture helper. Restore or replace that command in Claude Code settings, then try again.")
            }
        }
        if ownsClaudeCredentials {
            try claudeCredentials.remove(accountID: id, allowInteraction: true)
        }
        var updated = configuration
        updated.profiles.removeAll { $0.id == id }
        updated.snapshots.removeAll { $0.profileID == id }
        updated.manualCredits.removeValue(forKey: id.uuidString)
        updated.pendingManualCredits.removeValue(forKey: id.uuidString)
        updated.captureInstallations.removeValue(forKey: id.uuidString)
        updated.consoleConnections.removeValue(forKey: id.uuidString)
        updated.consoleObservations.removeValue(forKey: id.uuidString)
        do { try storage.save(updated) }
        catch {
            if let savedCredentials {
                do { try claudeCredentials.save(savedCredentials, accountID: id, allowInteraction: true) }
                catch {
                    throw UsageError.authenticationRequired("The account was not removed, but its sign-in could not be restored. Reconnect this account.")
                }
            }
            throw UsageError.providerFailure("The account could not be removed. Its saved profile is unchanged.")
        }
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
        updated.pendingManualCredits[accountID.uuidString]?.removeAll { $0.id == credit.id }
        if updated.pendingManualCredits[accountID.uuidString]?.isEmpty == true {
            updated.pendingManualCredits.removeValue(forKey: accountID.uuidString)
        }
        try storage.save(updated)
        configuration = updated
    }

    public func manualCredits(for accountID: UUID) -> [CreditBalance] {
        configuration.manualCredits[accountID.uuidString] ?? []
    }

    public func consoleConnection(for accountID: UUID) -> String? {
        configuration.consoleConnections[accountID.uuidString]
    }

    public func pendingManualCredits(for accountID: UUID) -> [CreditBalance] {
        configuration.pendingManualCredits[accountID.uuidString] ?? []
    }

    public func setClaudeConsoleConnection(accountID: UUID, organizationID: String?, expectedIdentity: String?) throws {
        try Task.checkCancellation()
        try ensureLoaded()
        guard let profile = configuration.profiles.first(where: { $0.id == accountID && $0.provider == .claude }),
              profile.providerAccountID == expectedIdentity else {
            throw UsageError.authenticationRequired("This API Credits connection belongs to an earlier account. Connect API Credits for the current account.")
        }
        if let organizationID, UUID(uuidString: organizationID) == nil {
            throw UsageError.invalidConfiguration("The Claude Platform organization identifier must be a UUID. Connect API Credits again.")
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

    public func updateClaudeConsoleCredits(accountID: UUID, organizationID: String, responseData: Data, expectedIdentity: String?,
                                          linkStateData: Data? = nil, invoicesData: Data? = nil, observedAt: Date = Date(), monthlyMetadataError: String? = nil) throws {
        try Task.checkCancellation()
        try ensureLoaded()
        guard let profile = configuration.profiles.first(where: { $0.id == accountID && $0.provider == .claude }),
              profile.providerAccountID == expectedIdentity else {
            throw UsageError.authenticationRequired("This Claude Platform response belongs to an earlier account. Connect API Credits for the current account.")
        }
        guard let connectedOrganization = configuration.consoleConnections[accountID.uuidString],
              UUID(uuidString: organizationID)?.uuidString.lowercased() == connectedOrganization,
              configuration.profiles.contains(where: { $0.id == accountID && $0.provider == .claude }) else {
            throw UsageError.invalidConfiguration("The Claude Platform response no longer matches this account's connected organization. Connect API Credits again.")
        }
        var linkState: ClaudeConsoleLinkState?
        var invoices: ClaudeConsoleInvoices?
        var metadataErrors = monthlyMetadataError.map { [$0] } ?? []
        if let linkStateData {
            do { linkState = try ClaudeConsoleLinkState.decode(linkStateData, organizationID: connectedOrganization) }
            catch { metadataErrors.append("Monthly plan details could not be read.") }
        }
        if let invoicesData {
            do { invoices = try ClaudeConsoleInvoices.decode(invoicesData, organizationID: connectedOrganization) }
            catch { metadataErrors.append("Monthly invoices could not be read.") }
        }
        let balance = try ClaudeConsoleBalance.decode(responseData, organizationID: connectedOrganization, observedAt: observedAt, linkState: linkState, invoices: invoices)
        var credits = balance.credits
        let metadataIncomplete = linkState == nil || invoices == nil
        if metadataIncomplete {
            let explanation = metadataErrors.isEmpty ? "Monthly grant details are unavailable." : metadataErrors.joined(separator: " ")
            if invoices == nil, let previous = configuration.consoleObservations[accountID.uuidString], previous.organizationID == connectedOrganization {
                for credit in previous.credits where credit.id.hasPrefix("monthly_grant_") && !credits.contains(where: { $0.id == credit.id }) {
                    // A cached monthly classification must not also appear as a fresh generic grant.
                    let genericID = "console_grant_" + credit.id.dropFirst("monthly_grant_".count)
                    credits.removeAll { $0.id == genericID }
                    credits.append(CreditBalance(id: credit.id, title: credit.title, amount: credit.amount, unit: credit.unit,
                                                 expiresAt: credit.expiresAt, source: credit.source, asOf: credit.asOf,
                                                 detail: credit.status == "Stale" ? credit.detail : [credit.detail, explanation, "Last verified monthly reading retained; refresh monthly details to confirm the current balance."].compactMap { $0 }.joined(separator: " "),
                                                 isUnlimited: credit.isUnlimited, status: "Stale", doesNotExpire: credit.doesNotExpire,
                                                 currencyCode: credit.currencyCode, originalAmount: credit.originalAmount))
                }
            }
            if !credits.contains(where: { $0.id.hasPrefix("monthly_grant_") }) {
                if let index = credits.firstIndex(where: { $0.id == "monthly_grant" }) {
                    let placeholder = credits[index]
                    credits[index] = CreditBalance(id: placeholder.id, title: placeholder.title, amount: nil, asOf: placeholder.asOf,
                                                  detail: [placeholder.detail, explanation].compactMap { $0 }.joined(separator: " "),
                                                  status: placeholder.status == "Balance unidentified" ? "Details unavailable" : placeholder.status)
                } else {
                    credits.append(CreditBalance(id: "monthly_grant", title: "Monthly included API grant", amount: nil,
                                                asOf: balance.observedAt, detail: explanation, status: "Details unavailable"))
                }
            }
        }
        if credits.contains(where: { $0.id.hasPrefix("monthly_grant_") }) { credits.removeAll { $0.id == "monthly_grant" } }
        var updated = configuration
        updated.consoleObservations[accountID.uuidString] = ConsoleCreditObservation(organizationID: balance.organizationID,
                                                                                   observedAt: balance.observedAt, credits: credits)
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
        let identifier = UUID()
        let generation = generations[id, default: 0]
        let task = Task { await self.fetch(profile, generation: generation) }
        refreshes[id] = task
        refreshIdentifiers[id] = identifier
        let result = await task.value
        if refreshIdentifiers[id] == identifier {
            refreshes.removeValue(forKey: id)
            refreshIdentifiers.removeValue(forKey: id)
        }
        return result
    }

    public func refreshAll() async -> [AccountSnapshot] {
        do { try ensureLoaded() } catch { return [] }
        let identifiers = configuration.profiles.map(\.id)
        var results: [AccountSnapshot] = []
        for identifier in identifiers { results.append(await refreshAccount(id: identifier)) }
        return results
    }

    private func fetch(_ profile: AccountProfile, generation: Int) async -> AccountSnapshot {
        var observed: AccountSnapshot
        do {
            if profile.source == .claudeOAuth {
                observed = try await fetchClaudeOAuth(profile, generation: generation)
            } else if profile.provider == .claude {
                let url = UsagePaths.captureURL(profileID: profile.id, directory: storage.directory)
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw UsageError.providerFailure("No Claude Code reading is available. Reconnect this account in your browser to read usage immediately.")
                }
                let capture = try JSONDecoder().decode(ClaudeQuotaCapture.self, from: Data(contentsOf: url))
                guard capture.profileID == profile.id else {
                    throw UsageError.providerFailure("The captured usage belongs to another profile.")
                }
                let currentWindows = capture.windows.filter { $0.isActive != false }
                let stale = Date().timeIntervalSince(capture.observedAt) > freshnessInterval
                    || currentWindows.contains { $0.resetsAt.map { $0 <= Date() } == true }
                observed = AccountSnapshot(profileID: profile.id, fetchedAt: capture.observedAt,
                                           windows: capture.windows, state: currentWindows.isEmpty ? .unavailable : stale ? .stale : .available,
                                           detail: currentWindows.isEmpty
                                           ? "Claude has not supplied quota data. Status-line quotas require an eligible subscription and a Claude response."
                                           : "Current login in this Claude configuration directory. Timestamp records the last quota change, not a live refresh.")
            } else {
                guard let path = profile.sourcePath else { throw UsageError.invalidConfiguration("Codex profile directory is missing.") }
                let client = CodexClient(executable: try codexExecutable(), home: URL(fileURLWithPath: path))
                let result = try await Task.detached(priority: .utility) {
                    try client.fetch(profileID: profile.id, expectedIdentity: profile.providerAccountID)
                }.value
                // Refuse to bind a second account to a listed Codex identity. Already bound profiles keep working.
                if profile.providerAccountID == nil, let identity = result.accountIdentity, configuration.profiles.contains(where: {
                    $0.id != profile.id && $0.provider == .codex && $0.providerAccountID == identity
                }) {
                    throw UsageError.authenticationRequired("This Codex account is already listed. Remove this account, or choose Reconnect… and sign in with a different account.")
                }
                observed = result.snapshot
                if let identity = result.accountIdentity,
                   let index = configuration.profiles.firstIndex(where: { $0.id == profile.id }) {
                    let reportedEmail = result.accountEmail?.trimmingCharacters(in: .whitespacesAndNewlines)
                    let knownEmail = profile.providerAccountID == identity ? profile.providerEmail : nil
                    let email = reportedEmail?.isEmpty == false ? reportedEmail : knownEmail
                    configuration.profiles[index] = AccountProfile(id: profile.id, provider: profile.provider,
                                                                  label: configuration.profiles[index].label, source: profile.source,
                                                                  providerAccountID: identity, providerEmail: email, sourcePath: profile.sourcePath)
                }
            }
        } catch {
            let authentication: Bool
            if case UsageError.authenticationRequired = error { authentication = true } else { authentication = false }
            let previous = configuration.snapshots.first { $0.profileID == profile.id }
            observed = AccountSnapshot(profileID: profile.id, fetchedAt: previous?.fetchedAt,
                                       windows: previous?.windows ?? [], credits: previous?.credits ?? [],
                                       state: authentication ? .authenticationRequired : previous?.fetchedAt == nil ? .unavailable : .stale,
                                       detail: error.localizedDescription, planName: previous?.planName)
        }
        guard generations[profile.id, default: 0] == generation else {
            return snapshot(for: profile.id) ?? AccountSnapshot(profileID: profile.id, state: .unavailable,
                                                              detail: "The account connection changed. Refresh to read current usage.")
        }
        if configuration.profiles.contains(where: { $0.id == profile.id }) {
            configuration.snapshots.removeAll { $0.profileID == profile.id }
            configuration.snapshots.append(observed)
            do { try storage.save(configuration) } catch {
                observed = AccountSnapshot(profileID: observed.profileID, fetchedAt: observed.fetchedAt,
                                           windows: observed.windows, credits: observed.credits, state: observed.state,
                                           detail: "Usage read, but could not save it: \(error.localizedDescription)",
                                           planName: observed.planName)
            }
        }
        return decorate(observed, state: observed.state, detail: observed.detail)
    }

    private func fetchClaudeOAuth(_ profile: AccountProfile, generation: Int) async throws -> AccountSnapshot {
        guard var credentials = try claudeCredentials.read(accountID: profile.id, allowInteraction: false),
              credentials.identity == profile.providerAccountID else {
            throw UsageError.authenticationRequired("Claude credentials are missing or belong to another account. Reconnect this account.")
        }
        guard !credentials.refreshPending else {
            throw UsageError.authenticationRequired("The previous Claude sign-in renewal did not finish safely. Reconnect this account.")
        }
        if credentials.expiresAt <= Date().addingTimeInterval(60) {
            guard let refreshToken = credentials.refreshToken, !refreshToken.isEmpty else {
                throw UsageError.authenticationRequired("Claude access expired. Reconnect this account.")
            }
            credentials.refreshPending = true
            // Persist before rotation: a crash or uncertain response must never retry this refresh token.
            try claudeCredentials.save(credentials, accountID: profile.id, allowInteraction: false)
            let pendingCredentials = credentials
            do {
                let token = try await claudeClient.refresh(refreshToken)
                credentials = try token.credentials(identity: pendingCredentials.identity, previousRefreshToken: refreshToken)
                let providerProfile = try await claudeClient.profile(accessToken: credentials.accessToken)
                _ = try providerProfile.resolvedIdentity(expected: profile.providerAccountID,
                                                       tokenAccount: token.account?.uuid, tokenOrganization: token.organization?.uuid)
                try validateClaudeCredentials(pendingCredentials, profileID: profile.id, generation: generation)
                try claudeCredentials.save(credentials, accountID: profile.id, allowInteraction: false)
            } catch {
                throw UsageError.authenticationRequired("Claude sign-in renewal could not be confirmed. Reconnect this account.")
            }
        }
        let providerProfile = try await claudeClient.profile(accessToken: credentials.accessToken)
        _ = try providerProfile.resolvedIdentity(expected: profile.providerAccountID)
        let usage = try await claudeClient.usage(accessToken: credentials.accessToken)
        try validateClaudeCredentials(credentials, profileID: profile.id, generation: generation)
        return try usage.snapshot(profileID: profile.id, planName: providerProfile.planName)
    }

    private func validateClaudeCredentials(_ credentials: ClaudeCredentials, profileID: UUID, generation: Int) throws {
        guard !Task.isCancelled, generations[profileID, default: 0] == generation,
              configuration.profiles.contains(where: { $0.id == profileID && $0.source == .claudeOAuth }),
              try claudeCredentials.read(accountID: profileID, allowInteraction: false) == credentials else {
            throw UsageError.authenticationRequired("The Claude account connection changed during this refresh. Refresh to read current usage.")
        }
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
            if credit.id == "monthly_grant", credits.contains(where: { $0.id.hasPrefix("monthly_grant_") }) { continue }
            credits.append(credit)
        }
        for credit in configuration.manualCredits[snapshot.profileID.uuidString] ?? [] {
            if credit.id == "monthly_grant", credits.contains(where: { $0.id.hasPrefix("monthly_grant_") }) { continue }
            if credit.id == "api_balance", credits.contains(where: { $0.id.hasPrefix("api_balance_") }) { continue }
            credits.removeAll { $0.id == credit.id }
            credits.append(credit)
        }
        let details = [detail, claudeCaptureCleanupMessages[snapshot.profileID]].compactMap { $0 }.joined(separator: "\n")
        return AccountSnapshot(profileID: snapshot.profileID, fetchedAt: snapshot.fetchedAt, windows: snapshot.windows,
                               credits: credits, state: state, detail: details.isEmpty ? nil : details,
                               planName: snapshot.planName)
    }

    public static var unavailableAPICredits: [CreditBalance] {
        unavailableCredits(for: .claude)
    }

    public static func unavailableCredits(for provider: Provider) -> [CreditBalance] {
        var credits = [CreditBalance(id: "api_balance", title: provider == .claude ? "Purchased API credits" : "OpenAI API credits", amount: nil,
                       detail: provider == .claude
                           ? "Connect API Credits to read purchased credit balances."
                           : "OpenAI API balances are entered manually."),
        ]
        if provider == .claude {
            credits.append(CreditBalance(id: "monthly_grant", title: "Monthly included API grant", amount: nil,
                                        detail: "Connect API Credits to read monthly grants and their expiry."))
        } else {
            credits.append(CreditBalance(id: "provider_credits", title: "Codex credits", amount: nil, unit: .credits,
                                        detail: "Codex has not supplied a credit balance."))
        }
        return credits
    }

    private func codexExecutable() throws -> URL { try codexExecutableURL ?? CodexExecutable.resolve() }

    private var codexDefaultHome: URL {
        let configured = ProcessInfo.processInfo.environment["CODEX_HOME"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        return (codexDefaultHomeURL ?? configured
                ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true))
            .standardizedFileURL.resolvingSymlinksInPath()
    }

    private func validLabel(_ label: String) throws -> String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw UsageError.invalidConfiguration("Enter an account name.") }
        return trimmed
    }
}
