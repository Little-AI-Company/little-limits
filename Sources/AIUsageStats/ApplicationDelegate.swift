import AppKit
import UsageCore

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let model = ApplicationModel(isDemo: CommandLine.arguments.contains("--demo")
        || CommandLine.arguments.contains("--demo-home")
        || CommandLine.arguments.contains("--demo-reading-states"))
    private let statusMenu = NSMenu(title: "AI Usage Stats")
    private var isMenuTracking = false
    private var statusItem: NSStatusItem?
    private var displayedStatusSummary: StatusItemSummary?
    private var accounts: AccountsWindowController?
    private var isAccountsWindowOpen = false
    private var refreshTimer: Timer?
    private var sleeping = false
    private var platformControllers: [UUID: ClaudePlatformViewController] = [:]
    private var claudeSignIn: ClaudeSignInWindowController?
    private var accountsLoaded = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        statusMenu.delegate = self
        statusMenu.autoenablesItems = false
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "AI"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.setAccessibilityLabel("AI Usage Stats")
            button.setAccessibilityHelp("Open account usage and remaining quota")
        }
        statusItem = item
        item.menu = statusMenu
        model.onChange = { [weak self] in self?.render() }
        model.onError = { [weak self] message in self?.showError(message) }
        model.onLoginCommand = { [weak self] command, id in self?.openLogin(command: command, accountID: id) }
        model.onConsoleRefresh = { [weak self] in self?.refreshConsoleCredits() }
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.addObserver(self, selector: #selector(willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        notifications.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        Task { [weak self] in
            guard let self else { return }
            await model.load()
            accountsLoaded = true
            render()
            model.refreshIfNeeded()
            startRefreshTimer()
            if CommandLine.arguments.contains("--show-home") || CommandLine.arguments.contains("--show-accounts") {
                showAccounts(nil)
            }
            if CommandLine.arguments.contains("--show-menu") || CommandLine.arguments.contains("--show-panel") {
                // Let AppKit finish placing the status item before opening the real menu.
                try? await Task.sleep(for: .milliseconds(200))
                showStatusMenu()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        model.cancelRefresh()
        claudeSignIn?.stop()
        platformControllers.values.forEach { $0.pause() }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        presentAccountsWindow(nil, presentation: .preserve)
        return false
    }

    private func render() {
        let activeAccountIDs = Set(model.profiles.map(\.id))
        for id in platformControllers.keys.filter({ !activeAccountIDs.contains($0) }) {
            platformControllers.removeValue(forKey: id)?.retire()
        }
        if accounts?.window?.isVisible == true { accounts?.render() }
        // The number per provider comes only from current readings, so an old or signed-out zero never
        // stands for the provider. The tooltip names the account and window behind the number.
        let now = Date()
        var readings: [StatusItemSummary.Reading] = []
        var descriptions: [String] = []
        for provider in [Provider.claude, .codex] {
            let profiles = model.profiles.filter { $0.provider == provider }
            guard !profiles.isEmpty else { continue }
            let name = InterfaceFormatting.provider(provider)
            let lowest = AccountQuotaSummary.lowestCurrent(accountIDs: profiles.map(\.id), snapshots: model.snapshots, now: now)
            let remaining = lowest.map { Int(min(100, max(0, $0.remainingPercent)).rounded()) }
            readings.append(StatusItemSummary.Reading(provider: provider, remainingPercent: remaining))
            let notCurrent = profiles.compactMap { profile -> String? in
                let summary = AccountQuotaSummary(snapshot: model.snapshots[profile.id], accountID: profile.id, now: now)
                guard let reason = Self.notCurrentReason(summary) else { return nil }
                return "\(InterfaceFormatting.accountIdentity(profile)): \(reason)"
            }
            if let lowest, let remaining, let profile = profiles.first(where: { $0.id == lowest.accountID }) {
                let others = notCurrent.isEmpty ? "" : " (\(notCurrent.count) other account\(notCurrent.count == 1 ? "" : "s") not current)"
                descriptions.append("\(name): \(remaining)% left on \(InterfaceFormatting.accountIdentity(profile)), "
                    + InterfaceFormatting.usageTitle(lowest.windowTitle) + others)
            } else {
                descriptions.append("\(name): no current reading. " + notCurrent.joined(separator: "; "))
            }
        }
        let stale = model.profiles.contains {
            guard let snapshot = model.snapshots[$0.id] else { return false }
            return snapshot.state == .stale || snapshot.state == .authenticationRequired
                || snapshot.fetchedAt.map { now.timeIntervalSince($0) >= 300 } == true
                || snapshot.currentWindows.contains { $0.resetsAt.map { $0 <= now } == true }
        }
        let summary = StatusItemSummary(readings: readings, isStale: stale)
        if displayedStatusSummary != summary, let button = statusItem?.button {
            button.title = readings.isEmpty ? "AI" : ""
            button.image = readings.isEmpty ? nil : StatusItemImage.render(summary)
            button.imagePosition = readings.isEmpty ? .noImage : .imageOnly
            button.imageScaling = .scaleProportionallyDown
            displayedStatusSummary = summary
        }
        let help = "AI Usage Stats\n" + descriptions.joined(separator: "\n") + (stale ? "\nSome usage is stale or needs sign-in. Open for details." : "")
        if statusItem?.button?.toolTip != help {
            statusItem?.button?.toolTip = help
            statusItem?.button?.setAccessibilityValue(descriptions.joined(separator: ". ") + (stale ? ". Some usage is stale or needs sign-in." : ""))
        }
    }

    /// Why an account's reading does not count toward the status item number, or nil when it is current.
    private static func notCurrentReason(_ summary: AccountQuotaSummary) -> String? {
        switch summary {
        case .available: nil
        case .authenticationRequired: "Sign-in required"
        case .stale: "Stale"
        case .inactive: "No active usage window"
        case .unavailable, .unknown: "Unavailable"
        }
    }

    private func showStatusMenu() {
        guard let button = statusItem?.button else { return }
        statusMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === statusMenu, !isMenuTracking else { return }
        rebuildStatusMenu()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        isMenuTracking = true
        if !sleeping { model.refreshIfNeeded() }
        if CommandLine.arguments.contains("--panel-diagnostics") || CommandLine.arguments.contains("--menu-diagnostics") {
            let window = statusItem?.button?.window
            let providerIconCount = statusMenu.items.filter { $0.isSectionHeader && $0.image != nil }.count
            let message = "AI Usage Stats surface: native-menu, providerIcons=\(providerIconCount)/\(model.profiles.count), statusImageWidth=\(Int(statusItem?.button?.image?.size.width ?? 0)), statusButtonFrame=\(NSStringFromRect(statusItem?.button?.frame ?? .zero)), statusItemVisible=\(statusItem?.isVisible == true), statusButtonWindowVisible=\(window?.isVisible == true), anchorFrame=\(NSStringFromRect(window?.frame ?? .zero))\n"
            FileHandle.standardError.write(Data(message.utf8))
        }
    }

    func menuDidClose(_ menu: NSMenu) {
        if menu === statusMenu { isMenuTracking = false }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        guard !sleeping else { return }
        refreshTimer = Timer.scheduledTimer(timeInterval: 300, target: self,
                                           selector: #selector(refreshElapsed(_:)), userInfo: nil, repeats: true)
        refreshTimer?.tolerance = 15
    }
    @objc private func refreshElapsed(_ sender: Timer) { if !sleeping { model.refresh() } }
    @objc private func willSleep(_ notification: Notification) {
        sleeping = true
        refreshTimer?.invalidate()
        model.cancelRefresh()
        platformControllers.values.forEach { $0.pause() }
        statusMenu.cancelTracking()
    }
    @objc private func didWake(_ notification: Notification) {
        sleeping = false
        startRefreshTimer()
        model.refreshIfNeeded()
        refreshConsoleCredits()
    }

    @objc private func showAccounts(_ sender: Any?) {
        presentAccountsWindow(sender, presentation: .home)
    }

    private enum AccountsWindowPresentation { case preserve, home, settings }

    private func presentAccountsWindow(_ sender: Any?, presentation: AccountsWindowPresentation) {
        statusMenu.cancelTracking()
        if accounts == nil {
            accounts = AccountsWindowController(model: model)
            accounts?.onConsoleConnection = { [weak self] id in self?.showClaudePlatform(id) }
            accounts?.onConsoleDisconnection = { [weak self] id in self?.platformController(id)?.disconnectConnection() }
            accounts?.onClaudeConnection = { [weak self] id, label in self?.showClaudeSignIn(id: id, label: label) }
            accounts?.isAccountLoadComplete = { [weak self] in self?.accountsLoaded == true }
            accounts?.onRetryAccountLoad = { [weak self] in self?.reloadAccounts(nil) }
            if let window = accounts?.window {
                let notifications = NotificationCenter.default
                notifications.addObserver(self, selector: #selector(accountsWindowWillClose(_:)),
                                          name: NSWindow.willCloseNotification, object: window)
                notifications.addObserver(self, selector: #selector(accountsWindowDidEndSheet(_:)),
                                          name: NSWindow.didEndSheetNotification, object: window)
            }
        }
        isAccountsWindowOpen = true
        updateActivationPolicy()
        switch presentation {
        case .preserve:
            accounts?.render()
        case .home:
            accounts?.showHome()
        case .settings:
            accounts?.render()
            accounts?.showSettings()
        }
        if accounts?.window?.isMiniaturized == true { accounts?.window?.deminiaturize(sender) }
        accounts?.showWindow(sender)
        accounts?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func accountsWindowWillClose(_ notification: Notification) {
        isAccountsWindowOpen = false
        updateActivationPolicy()
    }
    @objc private func accountsWindowDidEndSheet(_ notification: Notification) {
        updateActivationPolicy()
    }
    private func updateActivationPolicy() {
        let hasOpenWindow = isAccountsWindowOpen || accounts?.window?.attachedSheet != nil
        let policy: NSApplication.ActivationPolicy = hasOpenWindow ? .regular : .accessory
        if NSApp.activationPolicy() != policy { NSApp.setActivationPolicy(policy) }
    }
    @objc private func showSettings(_ sender: Any?) {
        presentAccountsWindow(sender, presentation: .settings)
    }
    @objc func refreshAllAccounts(_ sender: Any?) { model.refresh() }

    @objc private func openAccountFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        presentAccountsWindow(sender, presentation: .preserve)
        accounts?.showAccount(id: id)
    }
    @objc private func reconnectAccountFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        presentAccountsWindow(sender, presentation: .preserve)
        accounts?.reconnectAccount(id: id)
    }

    @objc private func addClaudeAccount(_ sender: Any?) { addAccount(.claude) }
    @objc private func addCodexAccount(_ sender: Any?) { addAccount(.codex) }
    private func addAccount(_ provider: Provider) {
        guard accountsLoaded, !model.hasAccountLoadFailure, !model.isDemo,
              !model.isRefreshing, !model.isChangingAccounts else { return }
        revealAccountsWindow(nil)
        accounts?.connect(provider)
    }

    @objc private func reloadAccounts(_ sender: Any?) {
        guard accountsLoaded else { return }
        accountsLoaded = false
        render()
        Task { [weak self] in
            guard let self else { return }
            await model.load()
            accountsLoaded = true
            render()
            model.refreshIfNeeded()
        }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(refreshAllAccounts(_:)):
            return accountsLoaded && !model.profiles.isEmpty && !model.isDemo && !model.isRefreshing && !model.isChangingAccounts
        case #selector(addClaudeAccount(_:)), #selector(addCodexAccount(_:)):
            return accountsLoaded && !model.hasAccountLoadFailure && !model.isDemo
                && !model.isRefreshing && !model.isChangingAccounts
        case #selector(reloadAccounts(_:)):
            return accountsLoaded
        default:
            return true
        }
    }

    private func rebuildStatusMenu() {
        statusMenu.removeAllItems()
        statusItem?.button?.setAccessibilityHelp(model.profiles.isEmpty ? "Add an account or open settings" : "Open account usage and remaining quota")
        guard accountsLoaded else {
            statusMenu.addItem(UsageMenu.progress("Loading Accounts…"))
            statusMenu.addItem(.separator())
            appendApplicationCommands(includeRefresh: false)
            return
        }
        if model.hasAccountLoadFailure {
            // Opens the window, whose Home page explains the failure and offers Retry.
            statusMenu.addItem(UsageMenu.stateLine("Accounts could not be loaded", detail: model.message,
                                                   target: self, action: #selector(showAccounts(_:))))
            statusMenu.addItem(command(title: "Retry Loading Accounts", action: #selector(reloadAccounts(_:))))
            statusMenu.addItem(.separator())
            appendApplicationCommands(includeRefresh: false)
            return
        }
        if model.isDemo {
            statusMenu.addItem(.sectionHeader(title: "Demo · Fictional accounts and balances"))
            statusMenu.addItem(.separator())
        }
        let now = Date()
        for item in UsageMenu.accountItems(profiles: model.profiles, snapshots: model.snapshots,
                                           consoleMessages: model.consoleMessages, now: now, target: self,
                                           openAction: #selector(openAccountFromMenu(_:)),
                                           reconnectAction: #selector(reconnectAccountFromMenu(_:))) {
            statusMenu.addItem(item)
        }
        if let message = model.message {
            statusMenu.addItem(UsageMenu.stateLine(message, detail: message, target: self, action: #selector(showAccounts(_:))))
        }
        if model.isChangingAccounts { statusMenu.addItem(UsageMenu.progress("Saving account…")) }
        appendApplicationCommands(includeRefresh: !model.profiles.isEmpty, includeSetup: model.profiles.isEmpty)
    }

    private func appendApplicationCommands(includeRefresh: Bool, includeSetup: Bool = false) {
        let commands = makeApplicationMenu(includeRefresh: includeRefresh, includeSetup: includeSetup, includeSettings: true)
        for item in commands.items {
            commands.removeItem(item)
            statusMenu.addItem(item)
        }
    }

    private func command(title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.isEnabled = validateMenuItem(item)
        return item
    }

    private func platformController(_ id: UUID) -> ClaudePlatformViewController? {
        if let controller = platformControllers[id] { return controller }
        guard let profile = model.profiles.first(where: { $0.id == id && $0.provider == .claude }) else { return nil }
        let controller = ClaudePlatformViewController(profile: profile, model: model)
        platformControllers[id] = controller
        return controller
    }
    private func revealAccountsWindow(_ sender: Any?) {
        presentAccountsWindow(sender, presentation: .preserve)
    }

    private func showClaudePlatform(_ id: UUID) {
        guard let controller = platformController(id) else { return }
        revealAccountsWindow(nil)
        accounts?.showPlatform(controller, accountID: id)
    }
    private func showClaudeSignIn(id: UUID?, label: String) {
        revealAccountsWindow(nil)
        guard let parent = accounts?.window else { return }
        if let controller = claudeSignIn, controller.window?.sheetParent != nil {
            parent.makeKeyAndOrderFront(nil)
            return
        }
        guard parent.attachedSheet == nil else { return }
        if let id { platformControllers.removeValue(forKey: id)?.retire() }
        let controller = ClaudeSignInWindowController(model: model, existingProfileID: id, label: label)
        claudeSignIn = controller
        controller.presentSheet(in: parent)
    }
    private func refreshConsoleCredits() {
        guard !sleeping, !model.isDemo else { return }
        for profile in model.profiles where profile.provider == .claude && model.consoleConnections[profile.id] != nil {
            platformController(profile.id)?.refreshInBackground()
        }
    }

    private func openLogin(command: String, accountID: UUID) {
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("AIUsageStatsLogin", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let script = directory.appendingPathComponent("codex_login_\(accountID.uuidString).command")
            try ("#!/bin/zsh\n\(command)\n").write(to: script, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
            NSWorkspace.shared.open(script)
        } catch { showError("Could not open Codex sign-in: \(error.localizedDescription)") }
    }
    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "AI Usage Stats"
        alert.informativeText = message
        revealAccountsWindow(nil)
        if let window = accounts?.window { alert.beginSheetModal(for: window) }
    }

    private func installMenu() {
        let menu = NSMenu()
        let app = NSMenuItem()
        app.submenu = makeApplicationMenu()
        menu.addItem(app)
        let file = NSMenuItem()
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(nilTargetItem("Add Account…", #selector(WindowCommandHandling.addAccount(_:)), "n"))
        fileMenu.addItem(.separator())
        fileMenu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        file.submenu = fileMenu
        menu.addItem(file)
        let edit = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Cut", #selector(NSText.cut(_:)), "x"),
                                     ("Copy", #selector(NSText.copy(_:)), "c"),
                                     ("Paste", #selector(NSText.paste(_:)), "v"),
                                     ("Select All", #selector(NSText.selectAll(_:)), "a")] {
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }
        edit.submenu = editMenu
        menu.addItem(edit)
        let view = NSMenuItem()
        let viewMenu = NSMenu(title: "View")
        let sidebar = NSMenuItem(title: "Show Sidebar", action: #selector(NSSplitViewController.toggleSidebar(_:)), keyEquivalent: "s")
        sidebar.keyEquivalentModifierMask = [.command, .control]
        viewMenu.addItem(sidebar)
        viewMenu.addItem(.separator())
        viewMenu.addItem(nilTargetItem("Month", #selector(WindowCommandHandling.showMonthPeriod(_:)), "1"))
        viewMenu.addItem(nilTargetItem("2 Weeks", #selector(WindowCommandHandling.showTwoWeekPeriod(_:)), "2"))
        viewMenu.addItem(.separator())
        viewMenu.addItem(nilTargetItem("Previous", #selector(WindowCommandHandling.showPreviousPeriod(_:)), "["))
        viewMenu.addItem(nilTargetItem("Next", #selector(WindowCommandHandling.showNextPeriod(_:)), "]"))
        viewMenu.addItem(nilTargetItem("Today", #selector(WindowCommandHandling.showCurrentPeriod(_:)), "t"))
        view.submenu = viewMenu
        menu.addItem(view)
        let window = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        window.submenu = windowMenu
        menu.addItem(window)
        NSApp.windowsMenu = windowMenu
        NSApp.mainMenu = menu
    }
    /// A command dispatched through the responder chain; disabled when no responder implements it.
    private func nilTargetItem(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        NSMenuItem(title: title, action: action, keyEquivalent: key)
    }

    private func makeApplicationMenu(includeRefresh: Bool = true, includeSetup: Bool = false, includeSettings: Bool = true) -> NSMenu {
        let menu = NSMenu(title: "AI Usage Stats")
        if includeSetup {
            menu.addItem(command(title: "Add Claude Account…", action: #selector(addClaudeAccount(_:))))
            menu.addItem(command(title: "Add Codex Account…", action: #selector(addCodexAccount(_:))))
            menu.addItem(.separator())
        }
        if includeRefresh { menu.addItem(command(title: model.isRefreshing ? "Refreshing…" : "Refresh All", action: #selector(refreshAllAccounts(_:)), key: "r")) }
        menu.addItem(command(title: "Open AI Usage Stats", action: #selector(showAccounts(_:))))
        if includeSettings { menu.addItem(command(title: "Settings…", action: #selector(showSettings(_:)), key: ",")) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AI Usage Stats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }
}
