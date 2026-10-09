import AppKit
import UsageCore

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private let model = ApplicationModel(isDemo: CommandLine.arguments.contains("--demo"))
    private let popover = NSPopover()
    private var statusItem: NSStatusItem?
    private var panel: UsagePanelController?
    private var accounts: AccountsWindowController?
    private var settings: SettingsWindowController?
    private var validationWindow: NSWindow?
    private var refreshTimer: Timer?
    private var countdownTimer: Timer?
    private var sleeping = false
    private var consoleWindows: [UUID: ClaudeConsoleWindowController] = [:]

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let panel = UsagePanelController(model: model)
        panel.onClose = { [weak self] in self?.closePanel() }
        panel.onAccounts = { [weak self] in self?.showAccounts(nil) }
        panel.onSettings = { [weak self] in self?.showSettings(nil) }
        panel.onImport = { [weak self] provider in
            self?.showAccounts(nil)
            self?.accounts?.connect(provider)
        }
        self.panel = panel
        popover.contentViewController = panel
        popover.contentSize = panel.preferredContentSize
        popover.behavior = .transient
        popover.delegate = self
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.title = "AI"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
            button.target = self
            button.action = #selector(togglePanel(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("AI Usage Stats")
            button.setAccessibilityHelp("Open account usage and remaining quota")
        }
        statusItem = item
        model.onChange = { [weak self] in self?.render() }
        model.onError = { [weak self] message in self?.showError(message) }
        model.onLoginCommand = { [weak self] command, id in self?.openLogin(command: command, accountID: id) }
        model.onConsoleRefresh = { [weak self] in self?.refreshConsoleCredits() }
        let notifications = NSWorkspace.shared.notificationCenter
        notifications.addObserver(self, selector: #selector(willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        notifications.addObserver(self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        if CommandLine.arguments.contains("--show-window") {
            popover.contentViewController = nil
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: panel.preferredContentSize),
                                  styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "AI Usage Stats"
            window.contentViewController = panel
            window.setContentSize(panel.preferredContentSize)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            validationWindow = window
            showValidationWindow()
        }
        Task { [weak self] in
            guard let self else { return }
            await model.load()
            model.refreshIfNeeded()
            startRefreshTimer()
            if CommandLine.arguments.contains("--show-panel"), validationWindow == nil {
                // Let AppKit finish placing the status item before anchoring a validation popover.
                try? await Task.sleep(for: .milliseconds(200))
                togglePanel(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        refreshTimer?.invalidate()
        countdownTimer?.invalidate()
        model.cancelRefresh()
        consoleWindows.values.forEach { $0.pause() }
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    private var isPanelVisible: Bool {
        if let window = validationWindow { return window.isVisible && !window.isMiniaturized }
        return popover.isShown
    }

    private func render(updateAccounts: Bool = true, updatePanel: Bool = true) {
        let activeAccountIDs = Set(model.profiles.map(\.id))
        for id in consoleWindows.keys.filter({ !activeAccountIDs.contains($0) }) {
            consoleWindows.removeValue(forKey: id)?.retire()
        }
        if updatePanel, isPanelVisible { panel?.render(); synchronizePanelSize() }
        if updateAccounts, accounts?.window?.isVisible == true { accounts?.render() }
        var summaries: [String] = []
        var descriptions: [String] = []
        for provider in [Provider.claude, .codex] {
            let profiles = model.profiles.filter { $0.provider == provider }
            guard !profiles.isEmpty else { continue }
            let values = profiles.flatMap { model.snapshots[$0.id]?.windows ?? [] }.compactMap(\.utilizationPercent).filter(\.isFinite)
            let remaining = values.max().map { Int((100 - min(100, max(0, $0))).rounded()) }
            summaries.append("\(InterfaceFormatting.provider(provider)) \(remaining.map { "\($0)%" } ?? "?")")
            descriptions.append("\(InterfaceFormatting.provider(provider)): \(remaining.map { "\($0)% lowest remaining quota" } ?? "usage unavailable") across \(profiles.count) account\(profiles.count == 1 ? "" : "s")")
        }
        let stale = model.profiles.contains {
            guard let snapshot = model.snapshots[$0.id] else { return false }
            return snapshot.state == .stale || snapshot.state == .authenticationRequired
                || snapshot.fetchedAt.map { Date().timeIntervalSince($0) >= 300 } == true
                || snapshot.windows.contains { $0.resetsAt.map { $0 <= Date() } == true }
        }
        let title = summaries.isEmpty ? "AI" : summaries.joined(separator: " · ") + (stale ? " !" : "")
        if statusItem?.button?.title != title { statusItem?.button?.title = title }
        let help = "AI Usage Stats\n" + descriptions.joined(separator: "\n") + (stale ? "\nSome usage is stale or needs sign-in. Open for details." : "")
        statusItem?.button?.toolTip = help
        statusItem?.button?.setAccessibilityValue(descriptions.joined(separator: ". "))
    }

    @objc private func togglePanel(_ sender: Any?) {
        if let button = statusItem?.button, NSApp.currentEvent?.type == .rightMouseUp {
            closePanel()
            makeApplicationMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
            return
        }
        if let window = validationWindow {
            if window.isVisible && !window.isMiniaturized { window.performClose(sender) }
            else { showValidationWindow() }
            return
        }
        guard let button = statusItem?.button else { return }
        if popover.isShown { closePanel() }
        else {
            panel?.render()
            synchronizePanelSize()
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            panel?.focus()
            recordPanelDiagnostics()
        }
    }

    private func recordPanelDiagnostics() {
        guard CommandLine.arguments.contains("--panel-diagnostics") else { return }
        let window = statusItem?.button?.window
        let message = "AI Usage Stats panel: shown=\(popover.isShown), statusItemVisible=\(statusItem?.isVisible == true), statusButtonWindowVisible=\(window?.isVisible == true), anchorFrame=\(NSStringFromRect(window?.frame ?? .zero))\n"
        FileHandle.standardError.write(Data(message.utf8))
    }

    private func closePanel() {
        if let window = validationWindow { window.performClose(nil) }
        else { popover.performClose(nil) }
    }

    func popoverWillShow(_ notification: Notification) { panelOpened() }
    func popoverDidClose(_ notification: Notification) { stopCountdownTimer() }
    func windowWillClose(_ notification: Notification) { stopCountdownTimer() }
    func windowDidMiniaturize(_ notification: Notification) { stopCountdownTimer() }
    func windowDidDeminiaturize(_ notification: Notification) { panelOpened() }

    private func showValidationWindow() {
        validationWindow?.deminiaturize(nil)
        validationWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panelOpened()
        panel?.focus()
    }

    private func panelOpened() {
        panel?.render()
        synchronizePanelSize()
        if !sleeping { model.refreshIfNeeded(); scheduleCountdown() }
    }

    private func scheduleCountdown() {
        stopCountdownTimer()
        let delay = 60 - Date().timeIntervalSince1970.truncatingRemainder(dividingBy: 60)
        countdownTimer = Timer.scheduledTimer(timeInterval: delay, target: self,
                                             selector: #selector(countdownElapsed(_:)), userInfo: nil, repeats: false)
        countdownTimer?.tolerance = 1
    }
    @objc private func countdownElapsed(_ sender: Timer) {
        guard isPanelVisible && !sleeping else { return }
        panel?.updateCountdowns()
        render(updateAccounts: false, updatePanel: false)
        scheduleCountdown()
    }
    private func stopCountdownTimer() { countdownTimer?.invalidate(); countdownTimer = nil }

    private func synchronizePanelSize() {
        guard let size = panel?.desiredSize else { return }
        if popover.contentSize != size { popover.contentSize = size }
        if let window = validationWindow, window.contentView?.frame.size != size {
            window.setContentSize(size)
        }
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
        stopCountdownTimer()
        model.cancelRefresh()
        consoleWindows.values.forEach { $0.pause() }
        popover.performClose(nil)
    }
    @objc private func didWake(_ notification: Notification) {
        sleeping = false
        startRefreshTimer()
        model.refreshIfNeeded()
        refreshConsoleCredits()
        if isPanelVisible { panelOpened() }
    }

    @objc private func showAccounts(_ sender: Any?) {
        popover.performClose(nil)
        if accounts == nil {
            accounts = AccountsWindowController(model: model)
            accounts?.onConsoleConnection = { [weak self] id in self?.showConsoleCredits(id) }
        }
        accounts?.render()
        accounts?.showWindow(sender)
        accounts?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func showSettings(_ sender: Any?) {
        popover.performClose(nil)
        if settings == nil { settings = SettingsWindowController() }
        settings?.showWindow(sender)
        settings?.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func refreshAccounts(_ sender: Any?) { model.refresh() }

    private func consoleController(_ id: UUID) -> ClaudeConsoleWindowController? {
        if let controller = consoleWindows[id] { return controller }
        guard let profile = model.profiles.first(where: { $0.id == id && $0.provider == .claude }) else { return nil }
        let controller = ClaudeConsoleWindowController(profile: profile, model: model)
        consoleWindows[id] = controller
        return controller
    }
    private func showConsoleCredits(_ id: UUID) {
        guard let controller = consoleController(id) else { return }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    private func refreshConsoleCredits() {
        guard !sleeping, !model.isDemo else { return }
        for profile in model.profiles where profile.provider == .claude && model.consoleConnections[profile.id] != nil {
            consoleController(profile.id)?.refreshInBackground()
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
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func installMenu() {
        let menu = NSMenu()
        let app = NSMenuItem()
        app.submenu = makeApplicationMenu()
        menu.addItem(app)
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
        NSApp.mainMenu = menu
    }
    private func makeApplicationMenu() -> NSMenu {
        let menu = NSMenu(title: "AI Usage Stats")
        for (title, action, key) in [("Refresh", #selector(refreshAccounts(_:)), "r"),
                                     ("Accounts…", #selector(showAccounts(_:)), ""),
                                     ("Settings…", #selector(showSettings(_:)), ",")] {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit AI Usage Stats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }
}
