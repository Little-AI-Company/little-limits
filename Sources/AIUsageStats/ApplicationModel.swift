import Foundation
import UsageCore

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
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    var onLoginCommand: ((String, UUID) -> Void)?
    var onConsoleRefresh: (() -> Void)?
    private var refreshTask: Task<Void, Never>?
    private var refreshRequested = false
    private var claudeAuthorizationID: UUID?
    private var hasPresentedDemoLoadError = false
    var isSigningInClaude: Bool { claudeAuthorizationID != nil }
    var hasAccountLoadFailure: Bool { profiles.isEmpty && message != nil }

    init(isDemo: Bool) { self.isDemo = isDemo }

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
            self.onChange?()
            if self.refreshRequested {
                self.refreshRequested = false
                self.refresh()
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
                do {
                    let profile = try await service.createCodexProfile(label: label)
                    let command = try await service.codexLoginCommand(accountID: profile.id)
                    await self?.load()
                    self?.onLoginCommand?(command, profile.id)
                } catch { self?.onError?(error.localizedDescription) }
                self?.isChangingAccounts = false
                self?.onChange?()
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
                self?.onLoginCommand?(command, id)
            } catch { self?.onError?(error.localizedDescription) }
            self?.isChangingAccounts = false
            self?.onChange?()
        }
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
