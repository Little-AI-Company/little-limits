import AppKit
import UsageCore

@MainActor
private final class PanelView: NSView {
    var onClose: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
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
    var desiredSize: NSSize { NSSize(width: 440, height: model.profiles.isEmpty ? 250 : 540) }
    private let model: ApplicationModel
    private let content = AccountListView(views: [])
    private let scroll = NSScrollView()
    private let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)
    private let actions = NSPopUpButton(frame: .zero, pullsDown: true)
    private let status = InterfaceControls.label("", size: 11)
    private var sections: [UUID: AccountSectionView] = [:]
    private var displayedIDs: [UUID]?
    private var emptyControls: [NSButton] = []

    init(model: ApplicationModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 440, height: 540)
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
        let title = InterfaceControls.label("AI Usage Stats", size: 16, weight: .semibold)
        refreshButton.target = self
        refreshButton.action = #selector(refresh(_:))
        refreshButton.keyEquivalent = "r"
        refreshButton.bezelStyle = .inline
        refreshButton.isBordered = false
        refreshButton.refusesFirstResponder = false
        refreshButton.font = .systemFont(ofSize: 13)
        refreshButton.setAccessibilityLabel("Refresh all accounts")
        refreshButton.heightAnchor.constraint(equalToConstant: 26).isActive = true
        configureActions()
        let controls = FunctionalControlGroupView(controls: [refreshButton, actions])
        controls.heightAnchor.constraint(equalToConstant: 34).isActive = true
        let heading = NSStackView(views: [title, NSView(), controls])
        heading.orientation = .horizontal
        heading.spacing = 8
        heading.alignment = .centerY
        let separator = InterfaceControls.separator()
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 2, left: 0, bottom: 10, right: 0)
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
        for component in [heading, separator, scroll, status] {
            component.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(component)
        }
        NSLayoutConstraint.activate([
            heading.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            heading.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            heading.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            heading.heightAnchor.constraint(equalToConstant: 34),
            separator.topAnchor.constraint(equalTo: heading.bottomAnchor, constant: 10),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 14),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            status.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 4),
            status.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 16),
            status.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -16),
            status.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -10)
        ])
        render()
    }

    func focus() {
        configureKeyboardNavigation()
        view.window?.makeFirstResponder(view)
    }

    func render() {
        guard isViewLoaded else { return }
        preferredContentSize = desiredSize
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
        else { status.stringValue = "Automatic refresh every 5 minutes" }
        status.toolTip = status.stringValue
        refreshButton.isEnabled = !model.isDemo && !model.isRefreshing && !model.isChangingAccounts && !model.profiles.isEmpty
        emptyControls.forEach { $0.isEnabled = !model.isChangingAccounts && !model.isDemo }
        restoreScroll(offset)
    }

    func updateCountdowns() {
        guard isViewLoaded else { return }
        let now = Date()
        sections.values.forEach { $0.updateTimes(now: now) }
    }

    private func rebuildAccountList(ids: [UUID]) {
        content.arrangedSubviews.forEach { content.removeArrangedSubview($0); $0.removeFromSuperview() }
        sections = sections.filter { ids.contains($0.key) }
        emptyControls.removeAll()
        if ids.isEmpty {
            add(InterfaceControls.label("Connect your first account", size: 15, weight: .semibold))
            add(InterfaceControls.label("Connect Claude Code quota reporting or sign in to Codex. Each account keeps a separate profile."))
            let claude = NSButton(title: "Connect Claude…", target: self, action: #selector(importClaude(_:)))
            let codex = NSButton(title: "Connect Codex…", target: self, action: #selector(importCodex(_:)))
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
                restoreScroll(scroll.contentView.bounds.origin)
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

    private func restoreScroll(_ offset: NSPoint) {
        view.layoutSubtreeIfNeeded()
        let maximum = max(0, content.frame.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(maximum, max(0, offset.y))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func configureActions() {
        actions.bezelStyle = .inline
        actions.isBordered = false
        actions.font = .systemFont(ofSize: 13)
        actions.setAccessibilityLabel("Application actions")
        actions.addItem(withTitle: "Actions")
        let menu = actions.menu
        let accounts = NSMenuItem(title: "Accounts…", action: #selector(openAccounts(_:)), keyEquivalent: "")
        accounts.target = self
        menu?.addItem(accounts)
        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.target = self
        menu?.addItem(settings)
        menu?.addItem(.separator())
        menu?.addItem(NSMenuItem(title: "Quit AI Usage Stats", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func configureKeyboardNavigation() {
        guard let window = view.window else { return }
        window.autorecalculatesKeyViewLoop = false
        window.recalculateKeyViewLoop()
        var controls: [NSView] = [refreshButton, actions]
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
