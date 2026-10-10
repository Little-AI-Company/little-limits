import AppKit
import UsageCore

@MainActor
private final class PanelView: NSView {
    var onClose: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onClose?() } else { super.keyDown(with: event) }
    }
    override func cancelOperation(_ sender: Any?) { onClose?() }
}

@MainActor
private final class AccountListView: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
final class UsagePanelController: NSViewController {
    var onAccounts: (() -> Void)?
    var onSettings: (() -> Void)?
    var onImport: ((Provider) -> Void)?
    var onClose: (() -> Void)?
    var onContentSizeChange: (() -> Void)?
    private(set) var desiredSize = NSSize(width: 440, height: 120)
    private let model: ApplicationModel
    private let content = AccountListView(views: [])
    private let scroll = NSScrollView()
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let accountsButton = NSButton(title: "Accounts…", target: nil, action: nil)
    private let settingsButton = NSButton(title: "Settings…", target: nil, action: nil)
    private let quitButton = NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:)))
    private let status = InterfaceControls.label("", size: 11)
    private var sections: [UUID: AccountSectionView] = [:]
    private var displayedIDs: [UUID]?
    private var emptyControls: [NSButton] = []
    private var statusHeight: NSLayoutConstraint?

    init(model: ApplicationModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = desiredSize
    }
    required init?(coder: NSCoder) { nil }

    override func viewDidAppear() {
        super.viewDidAppear()
        configureKeyboardNavigation()
    }

    override func loadView() {
        let root = PanelView(frame: NSRect(origin: .zero, size: preferredContentSize))
        root.onClose = { [weak self] in self?.onClose?() }
        view = root
        refreshButton.target = self
        refreshButton.action = #selector(refresh(_:))
        refreshButton.keyEquivalent = "r"
        refreshButton.bezelStyle = .inline
        refreshButton.isBordered = false
        refreshButton.toolTip = "Refresh all accounts. Readings refresh automatically every 5 minutes."
        refreshButton.setAccessibilityLabel("Refresh all accounts")
        accountsButton.target = self
        accountsButton.action = #selector(openAccounts(_:))
        settingsButton.target = self
        settingsButton.action = #selector(openSettings(_:))
        settingsButton.keyEquivalent = ","
        quitButton.keyEquivalent = "q"
        quitButton.bezelStyle = .inline
        quitButton.isBordered = false
        quitButton.setAccessibilityLabel("Quit AI Usage Stats")
        for button in [refreshButton, accountsButton, settingsButton, quitButton] {
            button.controlSize = .small
            button.font = .systemFont(ofSize: 12)
            button.refusesFirstResponder = false
        }
        let commands = NSStackView(views: [refreshButton, NSView(), accountsButton, settingsButton, quitButton])
        commands.orientation = .horizontal
        commands.spacing = 8
        commands.alignment = .centerY
        let separator = InterfaceControls.separator()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 2, right: 0)
        content.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = content
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = false
        scroll.setAccessibilityLabel("Account quotas and credit balances")
        let clip = scroll.contentView
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: clip.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: clip.trailingAnchor),
            content.topAnchor.constraint(equalTo: clip.topAnchor),
            content.widthAnchor.constraint(equalTo: clip.widthAnchor)
        ])
        status.lineBreakMode = .byTruncatingTail
        status.maximumNumberOfLines = 1
        status.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        for component in [commands, separator, scroll, status] {
            component.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(component)
        }
        let statusHeight = status.heightAnchor.constraint(equalToConstant: 0)
        self.statusHeight = statusHeight
        NSLayoutConstraint.activate([
            commands.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            commands.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            commands.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            commands.heightAnchor.constraint(equalToConstant: 24),
            separator.topAnchor.constraint(equalTo: commands.bottomAnchor, constant: 8),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            status.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 4),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10),
            statusHeight
        ])
        render()
    }

    func focus() {
        configureKeyboardNavigation()
        view.window?.makeFirstResponder(view)
    }

    func render() {
        guard isViewLoaded else { return }
        let offset = scroll.contentView.bounds.origin
        let ids = model.profiles.map(\.id)
        if displayedIDs != ids {
            rebuildAccountList(ids: ids)
            displayedIDs = ids
            configureKeyboardNavigation()
        }
        let now = Date()
        for profile in model.profiles {
            sections[profile.id]?.update(profile: profile, snapshot: model.snapshots[profile.id],
                                         consoleMessage: model.consoleMessages[profile.id], now: now)
        }
        if let message = model.message { status.stringValue = message }
        else if model.isDemo { status.stringValue = "Demo · Fictional accounts and balances" }
        else if model.isChangingAccounts { status.stringValue = "Saving account…" }
        else if model.isRefreshing { status.stringValue = "Refreshing accounts…" }
        else { status.stringValue = "" }
        status.isHidden = status.stringValue.isEmpty
        statusHeight?.constant = status.isHidden ? 0 : 16
        status.toolTip = status.stringValue
        refreshButton.isHidden = ids.isEmpty
        refreshButton.isEnabled = !model.isDemo && !model.isRefreshing && !model.isChangingAccounts && !ids.isEmpty
        emptyControls.forEach { $0.isEnabled = !model.isChangingAccounts && !model.isDemo && model.message == nil }
        fitContent(restoring: offset)
    }

    func updateCountdowns() {
        guard isViewLoaded else { return }
        let now = Date()
        sections.values.forEach { $0.updateTimes(now: now) }
        fitContent(restoring: scroll.contentView.bounds.origin)
    }

    private func rebuildAccountList(ids: [UUID]) {
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        sections = sections.filter { ids.contains($0.key) }
        emptyControls.removeAll()
        if ids.isEmpty {
            add(InterfaceControls.label(model.message == nil ? "No accounts connected." : "Accounts could not be loaded."))
            let claude = NSButton(title: "Add Claude Account…", target: self, action: #selector(importClaude(_:)))
            let codex = NSButton(title: "Add Codex Account…", target: self, action: #selector(importCodex(_:)))
            emptyControls = [claude, codex]
            let connections = NSStackView(views: emptyControls)
            connections.orientation = .horizontal
            connections.spacing = 8
            add(connections)
            return
        }
        for profile in model.profiles {
            let section = sections[profile.id] ?? AccountSectionView(profile: profile)
            section.onExpansionChange = { [weak self] in
                guard let self else { return }
                fitContent(restoring: scroll.contentView.bounds.origin)
                configureKeyboardNavigation()
            }
            sections[profile.id] = section
            add(section)
            if profile.id != ids.last { add(InterfaceControls.separator()) }
        }
    }

    private func add(_ component: NSView) {
        content.addArrangedSubview(component)
        component.widthAnchor.constraint(equalTo: content.widthAnchor).isActive = true
    }

    private func fitContent(restoring offset: NSPoint) {
        view.layoutSubtreeIfNeeded()
        let contentHeight = ceil(content.fittingSize.height)
        let chromeHeight: CGFloat = 69 + (status.isHidden ? 0 : 16)
        let size = NSSize(width: 440, height: min(540, max(100, contentHeight + chromeHeight)))
        if desiredSize != size {
            desiredSize = size
            preferredContentSize = size
            onContentSizeChange?()
        }
        view.layoutSubtreeIfNeeded()
        let maximum = max(0, content.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, offset.y))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func configureKeyboardNavigation() {
        guard let window = view.window else { return }
        window.autorecalculatesKeyViewLoop = false
        window.recalculateKeyViewLoop()
        var controls: [NSView] = [refreshButton, accountsButton, settingsButton, quitButton]
        controls.append(contentsOf: emptyControls)
        for profile in model.profiles {
            controls.append(contentsOf: sections[profile.id]?.keyboardControls ?? [])
        }
        view.nextKeyView = controls.first
        for (index, control) in controls.enumerated() {
            control.nextKeyView = controls[(index + 1) % controls.count]
        }
        window.initialFirstResponder = view
    }

    @objc private func refresh(_ sender: Any?) { model.refresh() }
    @objc private func openAccounts(_ sender: Any?) { onAccounts?() }
    @objc private func openSettings(_ sender: Any?) { onSettings?() }
    @objc private func importClaude(_ sender: Any?) { onImport?(.claude) }
    @objc private func importCodex(_ sender: Any?) { onImport?(.codex) }
}
