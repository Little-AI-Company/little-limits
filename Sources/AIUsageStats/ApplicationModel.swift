import Foundation
import OSLog
import UsageCore
import UsageHistory
import UsageHistoryStore

/// The answer to the Add Codex Account question shown when this Mac's Codex CLI is already signed in.
enum CodexLoginChoice {
    case useCurrentLogin
    case signInSeparately
    case cancel
}

@MainActor
final class ApplicationModel {
    let isDemo: Bool
    private let service = UsageService()
    private(set) var profiles: [AccountProfile] = []
    private(set) var snapshots: [UUID: AccountSnapshot] = [:]
    private(set) var isRefreshing = false
    private(set) var isChangingAccounts = false
    private(set) var isAllowingKeychainAccess = false
    private(set) var message: String?
    private(set) var completedAccountChanges = 0
    private(set) var consoleConnections: [UUID: String] = [:]
    private(set) var consoleMessages: [UUID: String] = [:]
    private(set) var manualCredits: [UUID: [CreditBalance]] = [:]
    private(set) var pendingManualCredits: [UUID: [CreditBalance]] = [:]
    /// Codex accounts whose Terminal sign-in is open. The account page and sidebar show the wait instead of an error.
    private(set) var awaitingCodexSignIns: Set<UUID> = []
    /// The local usage history, or nil when it could not be opened or the app runs the demonstration.
    /// `historyDatabaseError` then explains why; monitoring continues without history.
    let historyDatabase: HistoryDatabase?
    let historyDatabaseError: String?
    private let logIngestor: LogIngestor?
    private var logIngestion: Task<Void, Never>?
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    /// Opens the Terminal login command. Returns false when Terminal could not be opened.
    var onLoginCommand: ((String, UUID) -> Bool)?
    var onCodexLoginChoice: (@MainActor (CodexCurrentLogin) async -> CodexLoginChoice)?
    var onShowAccount: ((UUID) -> Void)?
    var onConsoleRefresh: (() -> Void)?
    private var refreshTask: Task<Void, Never>?
    private var codexSignInWaits: [UUID: Task<Void, Never>] = [:]
    private var refreshRequested = false
    private var claudeAuthorizationID: UUID?
    private var hasPresentedDemoLoadError = false
    var isSigningInClaude: Bool { claudeAuthorizationID != nil }
    var hasAccountLoadFailure: Bool { profiles.isEmpty && message != nil }

    init(isDemo: Bool) {
        self.isDemo = isDemo
        (historyDatabase, historyDatabaseError) = isDemo ? (nil, nil) : Self.openHistoryDatabase()
        logIngestor = historyDatabase.map { LogIngestor(database: $0) }
        let defaults = UserDefaults.standard
        chosenMenuBarAccountIDs = isDemo ? nil
            : defaults.stringArray(forKey: Self.menuBarAccountsKey).map { Set($0.compactMap(UUID.init(uuidString:))) }
        let legacy = isDemo ? [] : defaults.stringArray(forKey: Self.legacyMenuBarHiddenKey) ?? []
        legacyMenuBarHiddenAccountIDs = Set(legacy.compactMap(UUID.init(uuidString:)))
    }

    nonisolated private static let logger = Logger(subsystem: "com.parkerrex.ai-usage-stats", category: "History")

    private static func openHistoryDatabase() -> (HistoryDatabase?, String?) {
        let url = UsagePaths.applicationSupport.appendingPathComponent("history.sqlite")
        do {
            return (try HistoryDatabase(url: url), nil)
        } catch {
            logger.error("Could not open the usage history database: \(error.localizedDescription, privacy: .public)")
            return (nil, "Could not open the usage history: \(error.localizedDescription)")
        }
    }

    /// Saves the latest readings to quota history and starts a log read when none is running. Both run on a
    /// background task; the menu and windows never wait for them.
    private func recordHistory() {
        guard let historyDatabase, let logIngestor else { return }
        let readings = profiles.flatMap { profile in
            snapshots[profile.id].map { Self.quotaReadings(profile: profile, snapshot: $0) } ?? []
        }
        Task.detached(priority: .utility) {
            do { try historyDatabase.recordQuotaReadings(readings) } catch {
                Self.logger.error("Could not save quota history: \(error.localizedDescription, privacy: .public)")
            }
        }
        guard logIngestion == nil else { return }
        let codexAccounts = profiles.compactMap { profile -> CodexAccountLink? in
            guard profile.source == .codexCLI || profile.source == .codexDefaultLogin,
                  let providerAccountID = profile.providerAccountID else { return nil }
            return CodexAccountLink(accountID: profile.id, providerAccountID: providerAccountID)
        }
        logIngestion = Task.detached(priority: .utility) { [weak self] in
            let started = ContinuousClock.now
            let summary = await logIngestor.ingest(codexAccounts: codexAccounts)
            let duration = ContinuousClock.now - started
            if summary.filesRead > 0 { Self.logger.notice("""
                Read \(summary.filesRead) log files (\(summary.filesUnchanged) unchanged, \(summary.filesFailed) failed) \
                in \(duration, privacy: .public): \(summary.responses) responses, \(summary.commands) commands, \
                \(summary.quotaReadingsAdded) quota readings added
                """) }
            if let failure = summary.lastFailure {
                Self.logger.error("Could not read a log file: \(failure, privacy: .private)")
            }
            await self?.finishLogIngestion()
        }
    }

    private func finishLogIngestion() { logIngestion = nil }

    /// One reading per window of an available snapshot. Demonstration and manual accounts have no live source.
    private static func quotaReadings(profile: AccountProfile, snapshot: AccountSnapshot) -> [QuotaReading] {
        let source: QuotaReadingSource
        switch profile.source {
        case .claudeOAuth: source = .claudeOAuth
        case .claudeCLI: source = .claudeStatusLine
        case .codexCLI, .codexDefaultLogin: source = .codexAppServer
        case .manual, .demo: return []
        }
        guard snapshot.state == .available, let fetchedAt = snapshot.fetchedAt else { return [] }
        let provider: HistoryProvider = profile.provider == .claude ? .claude : .codex
        return snapshot.currentWindows.compactMap { window in
            window.utilizationPercent.map {
                QuotaReading(provider: provider, accountID: profile.id, windowID: window.id, usedPercent: $0,
                             resetsAt: window.resetsAt, windowDurationMinutes: window.windowDurationMinutes,
                             observedAt: fetchedAt, source: source)
            }
        }
    }

    // MARK: Menu bar accounts

    private static let menuBarAccountsKey = "MenuBarAccountIDs"
    /// The first version stored hidden accounts instead; read once so an existing choice carries over.
    private static let legacyMenuBarHiddenKey = "MenuBarHiddenAccountIDs"
    private var chosenMenuBarAccountIDs: Set<UUID>?
    private var legacyMenuBarHiddenAccountIDs: Set<UUID>

    /// Accounts that each get their own menu bar number, or nil for the default: the lowest remaining quota
    /// per provider across every account. A display preference only; account data is unchanged.
    var menuBarAccountIDs: Set<UUID>? { chosenMenuBarAccountIDs }

    func showsInMenuBar(_ id: UUID) -> Bool { menuBarAccountIDs?.contains(id) == true }

    func setShowsInMenuBar(_ shows: Bool, for id: UUID) {
        var chosen = menuBarAccountIDs ?? []
        if shows { chosen.insert(id) } else { chosen.remove(id) }
        saveMenuBarChoice(chosen)
    }

    /// Saves the earlier hidden-account choice as the chosen-account list once, against the loaded accounts, so
    /// accounts added later are not chosen automatically.
    private func convertLegacyMenuBarChoice() {
        guard chosenMenuBarAccountIDs == nil, !legacyMenuBarHiddenAccountIDs.isEmpty else { return }
        chosenMenuBarAccountIDs = Set(profiles.map(\.id)).subtracting(legacyMenuBarHiddenAccountIDs)
        legacyMenuBarHiddenAccountIDs = []
        if !isDemo, let chosen = chosenMenuBarAccountIDs {
            UserDefaults.standard.set(chosen.map(\.uuidString).sorted(), forKey: Self.menuBarAccountsKey)
            UserDefaults.standard.removeObject(forKey: Self.legacyMenuBarHiddenKey)
        }
    }

    /// Returns the menu bar to the lowest remaining quota per provider.
    func showLowestPerProviderInMenuBar() { saveMenuBarChoice(nil) }

    private func saveMenuBarChoice(_ chosen: Set<UUID>?) {
        chosenMenuBarAccountIDs = chosen
        legacyMenuBarHiddenAccountIDs = []
        if !isDemo {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: Self.legacyMenuBarHiddenKey)
            if let chosen { defaults.set(chosen.map(\.uuidString).sorted(), forKey: Self.menuBarAccountsKey) }
            else { defaults.removeObject(forKey: Self.menuBarAccountsKey) }
        }
        onChange?()
    }

    func load() async {
        if isDemo {
            message = nil
            // Load failure and empty keep their existing precedence. Reading states and Home are additional demo sets.
            if CommandLine.arguments.contains("--demo-load-error"), !hasPresentedDemoLoadError {
                hasPresentedDemoLoadError = true
                profiles = []
                snapshots = [:]
                message = "Could not load accounts: Demonstration load failure."
            } else if CommandLine.arguments.contains("--demo-empty") {
                profiles = []
                snapshots = [:]
            } else if CommandLine.arguments.contains("--demo-reading-states") {
                profiles = DemoFixtures.homeProfiles
                snapshots = Dictionary(uniqueKeysWithValues: DemoFixtures.homeReadingStateSnapshots.map { ($0.profileID, $0) })
            } else if CommandLine.arguments.contains("--demo-home") {
                profiles = DemoFixtures.homeProfiles
                snapshots = Dictionary(uniqueKeysWithValues: DemoFixtures.homeSnapshots.map { ($0.profileID, $0) })
            } else {
                profiles = DemoFixtures.profiles
                snapshots = Dictionary(uniqueKeysWithValues: DemoFixtures.snapshots.map { ($0.profileID, $0) })
            }
            onChange?()
            return
        }
        do {
            profiles = try await service.load()
            for profile in profiles {
                snapshots[profile.id] = await service.snapshot(for: profile.id)
                consoleConnections[profile.id] = await service.consoleConnection(for: profile.id)
                manualCredits[profile.id] = await service.manualCredits(for: profile.id)
                pendingManualCredits[profile.id] = await service.pendingManualCredits(for: profile.id)
            }
            message = nil
            convertLegacyMenuBarChoice()
        } catch {
            message = "Could not load accounts: \(error.localizedDescription)"
        }
        onChange?()
    }

    func refreshIfNeeded() {
        guard profiles.contains(where: { profile in
            guard let snapshot = snapshots[profile.id], let date = snapshot.fetchedAt else { return true }
            if snapshot.currentWindows.contains(where: { $0.resetsAt.map { $0 <= Date() } == true }) { return true }
            return Date().timeIntervalSince(date) >= 300
        }) else { return }
        refresh()
    }

    func refresh() {
        guard !isDemo, !isChangingAccounts, !profiles.isEmpty else { return }
        if isRefreshing { refreshRequested = true; return }
        isRefreshing = true
        onConsoleRefresh?()
        onChange?()
        refreshTask = Task { [weak self, service] in
            let results = await service.refreshAll()
            guard let self else { return }
            if !Task.isCancelled {
                self.snapshots = Dictionary(uniqueKeysWithValues: results.map { ($0.profileID, $0) })
                do {
                    self.profiles = try await service.load()
                    self.message = nil
                } catch { self.message = "Could not reload accounts: \(error.localizedDescription)" }
            }
            self.isRefreshing = false
            self.refreshTask = nil
            if !Task.isCancelled { self.recordHistory() }
            self.onChange?()
            if self.refreshRequested {
                self.refreshRequested = false
                self.refresh()
            }
        }
    }

    /// Reads one account again. It shares `isRefreshing` with Refresh All, so the two never run together and every
    /// refresh control disables while it runs. Only that account's snapshot changes.
    func refreshAccount(_ id: UUID) {
        guard !isDemo, !isChangingAccounts, !isRefreshing, profiles.contains(where: { $0.id == id }) else { return }
        isRefreshing = true
        onChange?()
        refreshTask = Task { [weak self, service] in
            let snapshot = await service.refreshAccount(id: id)
            guard let self else { return }
            if !Task.isCancelled, profiles.contains(where: { $0.id == id }) {
                snapshots[id] = snapshot
                // A read can update the saved email or plan, as Refresh All reloads after reading.
                do {
                    profiles = try await service.load()
                    message = nil
                } catch { message = "Could not reload accounts: \(error.localizedDescription)" }
                recordHistory()
            }
            isRefreshing = false
            refreshTask = nil
            onChange?()
            if refreshRequested {
                refreshRequested = false
                refresh()
            }
        }
    }

    func cancelRefresh() { refreshRequested = false; refreshTask?.cancel() }

    func importAccount(provider: Provider, label: String, configurationURL: URL? = nil) {
        if provider == .codex {
            guard !isDemo, !isChangingAccounts, !isRefreshing else { return }
            isChangingAccounts = true
            onChange?()
            Task { [weak self, service] in
                guard let self else { return }
                do {
                    if let login = await service.currentCodexLogin(), let onCodexLoginChoice {
                        switch await onCodexLoginChoice(login) {
                        case .cancel:
                            isChangingAccounts = false
                            onChange?()
                            return
                        case .useCurrentLogin:
                            let profile = try await service.createCodexProfileUsingCurrentLogin(label: label)
                            await load()
                            completedAccountChanges += 1
                            isChangingAccounts = false
                            onChange?()
                            onShowAccount?(profile.id)
                            return
                        case .signInSeparately: break
                        }
                    }
                    let profile = try await service.createCodexProfile(label: label)
                    let command = try await service.codexLoginCommand(accountID: profile.id)
                    await load()
                    openCodexLogin(command: command, accountID: profile.id)
                } catch { onError?(error.localizedDescription) }
                isChangingAccounts = false
                onChange?()
            }
            return
        }
        changeAccounts { service in
            _ = try await service.importClaudeCLI(label: label, configurationURL: configurationURL)
        }
    }

    func allowKeychainAccess(_ id: UUID) {
        guard !isDemo, !isChangingAccounts, !isRefreshing,
              profiles.contains(where: { $0.id == id && $0.source == .claudeOAuth }) else { return }
        isChangingAccounts = true
        isAllowingKeychainAccess = true
        onChange?()
        Task { [weak self, service] in
            var failure: Error?
            do { try await service.allowClaudeKeychainAccess(id: id) }
            catch { failure = error }
            guard let self else { return }
            isChangingAccounts = false
            isAllowingKeychainAccess = false
            onChange?()
            if let failure { onError?(failure.localizedDescription) }
            else { refresh() }
        }
    }

    func signInCodex(_ id: UUID) {
        guard !isDemo, !isChangingAccounts, !isRefreshing else { return }
        isChangingAccounts = true
        onChange?()
        Task { [weak self, service] in
            do {
                let command = try await service.codexLoginCommand(accountID: id)
                self?.openCodexLogin(command: command, accountID: id)
            } catch { self?.onError?(error.localizedDescription) }
            self?.isChangingAccounts = false
            self?.onChange?()
        }
    }

    func isAwaitingCodexSignIn(_ id: UUID) -> Bool { awaitingCodexSignIns.contains(id) }

    /// Opens the Terminal login, then refreshes the account and shows its page once the login finishes.
    private func openCodexLogin(command: String, accountID id: UUID) {
        guard onLoginCommand?(command, id) == true else { return }
        cancelCodexSignInWait(id)
        awaitingCodexSignIns.insert(id)
        onChange?()
        codexSignInWaits[id] = Task { [weak self, service] in
            let outcome = await service.awaitCodexSignIn(id: id)
            // A cancelled wait was replaced or stopped, and its owner already cleared the waiting state.
            guard let self, !Task.isCancelled else { return }
            codexSignInWaits[id] = nil
            awaitingCodexSignIns.remove(id)
            switch outcome {
            case .signedIn(let snapshot):
                snapshots[id] = snapshot
                if let loaded = try? await service.load() { profiles = loaded }
                onChange?()
                onShowAccount?(id)
            case .timedOut:
                // One ordinary read replaces the wait with the account's real state, such as Sign-in required.
                let snapshot = await service.refreshAccount(id: id)
                if profiles.contains(where: { $0.id == id }) { snapshots[id] = snapshot }
                onChange?()
            case .cancelled, .accountRemoved:
                onChange?()
            }
        }
    }

    private func cancelCodexSignInWait(_ id: UUID) {
        codexSignInWaits.removeValue(forKey: id)?.cancel()
        awaitingCodexSignIns.remove(id)
    }

    /// Stops every Terminal sign-in wait, for example when the app quits.
    func cancelCodexSignInWaits() {
        for id in Array(codexSignInWaits.keys) { cancelCodexSignInWait(id) }
    }

    func prepareClaudeSignIn(existingProfileID: UUID?, label: String) async throws -> ClaudeAuthorizationRequest {
        guard !isDemo, !isChangingAccounts, !isRefreshing else {
            throw UsageError.providerFailure("Wait for the current account operation to finish, then try again.")
        }
        isChangingAccounts = true
        onChange?()
        do {
            let request = try await service.prepareClaudeSignIn(existingProfileID: existingProfileID, label: label)
            claudeAuthorizationID = request.id
            onChange?()
            return request
        } catch {
            isChangingAccounts = false
            onChange?()
            throw error
        }
    }

    func completeClaudeSignIn(requestID: UUID, callbackURL: URL) async throws -> AccountProfile {
        defer {
            if claudeAuthorizationID == requestID {
                claudeAuthorizationID = nil
                isChangingAccounts = false
                onChange?()
            }
        }
        let profile = try await service.completeClaudeSignIn(requestID: requestID, callbackURL: callbackURL)
        if profiles.first(where: { $0.id == profile.id })?.providerAccountID == nil {
            consoleMessages[profile.id] = nil
        }
        await load()
        completedAccountChanges += 1
        return profile
    }

    func cancelClaudeSignIn(id: UUID) async {
        await service.cancelClaudeSignIn(id: id)
        guard claudeAuthorizationID == id else { return }
        claudeAuthorizationID = nil
        isChangingAccounts = false
        onChange?()
    }

    /// Shows the new order at once, then saves it. A failed save reloads the saved order.
    func moveAccount(id: UUID, toIndex index: Int) {
        guard !isDemo, !isChangingAccounts, !isRefreshing,
              let source = profiles.firstIndex(where: { $0.id == id }) else { return }
        let destination = min(max(index, 0), profiles.count - 1)
        guard destination != source else { return }
        profiles.insert(profiles.remove(at: source), at: destination)
        isChangingAccounts = true
        onChange?()
        Task { [weak self, service] in
            do { try await service.moveAccount(id: id, toIndex: destination) }
            catch {
                self?.onError?(error.localizedDescription)
                await self?.load()
            }
            self?.isChangingAccounts = false
            self?.onChange?()
        }
    }

    func removeAccount(_ id: UUID) {
        // A sign-in wait for this account ends on its own once the service no longer lists the account.
        changeAccounts { service in try await service.removeAccount(id: id) }
    }

    func setManualCredit(accountID: UUID, credit: CreditBalance) {
        changeAccounts { service in try await service.setManualCredit(accountID: accountID, credit: credit) }
    }

    func setConsoleConnection(accountID: UUID, organizationID: String?, expectedIdentity: String?) async throws {
        try await service.setClaudeConsoleConnection(accountID: accountID, organizationID: organizationID, expectedIdentity: expectedIdentity)
        try validateConsoleIdentity(accountID: accountID, expectedIdentity: expectedIdentity)
        consoleConnections[accountID] = organizationID
        if organizationID == nil { consoleMessages[accountID] = nil }
    }

    func updateConsoleCredits(accountID: UUID, organizationID: String, responseData: Data, expectedIdentity: String?,
                              linkStateData: Data? = nil, invoicesData: Data? = nil, observedAt: Date = Date(), monthlyMetadataError: String? = nil) async throws {
        try await service.updateClaudeConsoleCredits(accountID: accountID, organizationID: organizationID, responseData: responseData,
                                                    expectedIdentity: expectedIdentity, linkStateData: linkStateData,
                                                    invoicesData: invoicesData, observedAt: observedAt, monthlyMetadataError: monthlyMetadataError)
        try validateConsoleIdentity(accountID: accountID, expectedIdentity: expectedIdentity)
        consoleMessages[accountID] = nil
        await load()
    }

    private func validateConsoleIdentity(accountID: UUID, expectedIdentity: String?) throws {
        try Task.checkCancellation()
        guard let profile = profiles.first(where: { $0.id == accountID }), profile.providerAccountID == expectedIdentity else {
            throw UsageError.authenticationRequired("The account changed during the Claude Platform request. Connect API Credits for the current account.")
        }
    }

    func recordConsoleError(accountID: UUID, message: String) {
        consoleMessages[accountID] = message
        onChange?()
    }

    private func changeAccounts(_ operation: @escaping @Sendable (UsageService) async throws -> Void) {
        guard !isDemo, !isChangingAccounts, !isRefreshing else { return }
        isChangingAccounts = true
        onChange?()
        Task { [weak self, service] in
            do {
                try await operation(service)
                await self?.load()
                self?.completedAccountChanges += 1
            } catch {
                self?.onError?(error.localizedDescription)
            }
            guard let self else { return }
            self.isChangingAccounts = false
            self.onChange?()
            self.refreshIfNeeded()
        }
    }
}
