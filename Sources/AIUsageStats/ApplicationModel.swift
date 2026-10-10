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
    private(set) var message: String?
    private(set) var completedAccountChanges = 0
    private(set) var consoleConnections: [UUID: String] = [:]
    private(set) var consoleMessages: [UUID: String] = [:]
    private(set) var manualCredits: [UUID: [CreditBalance]] = [:]
    var onChange: (() -> Void)?
    var onError: ((String) -> Void)?
    var onLoginCommand: ((String, UUID) -> Void)?
    var onConsoleRefresh: (() -> Void)?
    private var refreshTask: Task<Void, Never>?
    private var refreshRequested = false
    private var claudeAuthorizationID: UUID?
    var isSigningInClaude: Bool { claudeAuthorizationID != nil }

    init(isDemo: Bool) { self.isDemo = isDemo }

    func load() async {
        if isDemo {
            profiles = DemoFixtures.profiles
            snapshots = Dictionary(uniqueKeysWithValues: DemoFixtures.snapshots.map { ($0.profileID, $0) })
            onChange?()
            return
        }
        do {
            profiles = try await service.load()
            for profile in profiles {
                snapshots[profile.id] = await service.snapshot(for: profile.id)
                consoleConnections[profile.id] = await service.consoleConnection(for: profile.id)
                manualCredits[profile.id] = await service.manualCredits(for: profile.id)
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
                do { self.profiles = try await service.load() }
                catch { self.message = "Could not reload accounts: \(error.localizedDescription)" }
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

    func renameAccount(_ id: UUID, label: String) {
        changeAccounts { service in try await service.renameAccount(id: id, label: label) }
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

    func removeAccount(_ id: UUID) {
        changeAccounts { service in try await service.removeAccount(id: id) }
    }

    func setManualCredit(accountID: UUID, credit: CreditBalance) {
        changeAccounts { service in try await service.setManualCredit(accountID: accountID, credit: credit) }
    }

    func setConsoleConnection(accountID: UUID, organizationID: String?) async throws {
        try await service.setClaudeConsoleConnection(accountID: accountID, organizationID: organizationID)
        consoleConnections[accountID] = organizationID
    }

    func updateConsoleCredits(accountID: UUID, organizationID: String, responseData: Data) async throws {
        try await service.updateClaudeConsoleCredits(accountID: accountID, organizationID: organizationID, responseData: responseData)
        consoleMessages[accountID] = nil
        await load()
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
