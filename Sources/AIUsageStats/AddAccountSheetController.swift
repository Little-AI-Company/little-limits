import AppKit
import UsageCore

/// Attached sheet that chooses the provider for Add Account… and explains how that provider signs in.
@MainActor
final class AddAccountSheetController: NSWindowController {
    private let providerPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    private let explanation = InterfaceControls.label("", size: 12)
    /// Width of the text column. The sheet height follows the fitted content for the chosen provider.
    private static let contentWidth: CGFloat = 380
    private static let margin: CGFloat = 20

    init(provider: Provider) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth + Self.margin * 2, height: 180),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.title = "Add Account"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        providerPicker.addItems(withTitles: Provider.allCases.map(InterfaceFormatting.provider))
        providerPicker.selectItem(at: Provider.allCases.firstIndex(of: provider) ?? 0)
        providerPicker.target = self
        providerPicker.action = #selector(selectProvider(_:))
        providerPicker.setAccessibilityLabel("Provider")
        let title = InterfaceControls.label("Add Account", size: 13, weight: .bold)
        let providerRow = NSStackView(views: [InterfaceControls.label("Provider:", size: 13), providerPicker])
        providerRow.orientation = .horizontal
        providerRow.alignment = .firstBaseline
        providerRow.spacing = 8
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let proceed = NSButton(title: "Continue", target: self, action: #selector(proceed(_:)))
        proceed.keyEquivalent = "\r"
        // Trailing gravity keeps Continue at the trailing edge of the full-width button row.
        let buttons = NSStackView()
        buttons.setViews([cancel, proceed], in: .trailing)
        buttons.orientation = .horizontal
        buttons.spacing = 12
        let content = InterfaceControls.stack([title, providerRow, explanation, buttons], spacing: 14)
        content.setCustomSpacing(20, after: explanation)
        content.translatesAutoresizingMaskIntoConstraints = false
        if let root = window.contentView {
            root.addSubview(content)
            NSLayoutConstraint.activate([
                content.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: Self.margin),
                content.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -Self.margin),
                content.topAnchor.constraint(equalTo: root.topAnchor, constant: Self.margin),
                content.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -Self.margin),
                content.widthAnchor.constraint(equalToConstant: Self.contentWidth),
                explanation.widthAnchor.constraint(equalTo: content.widthAnchor),
                buttons.trailingAnchor.constraint(equalTo: content.trailingAnchor)
            ])
        }
        explanation.preferredMaxLayoutWidth = Self.contentWidth
        window.initialFirstResponder = providerPicker
        updateExplanation()
    }

    required init?(coder: NSCoder) { nil }

    /// The completion handler keeps this controller alive until the sheet ends. `onContinue` runs after the sheet
    /// detaches, so the next step can attach its own sheet.
    func present(in parent: NSWindow, onContinue: @escaping (Provider) -> Void) {
        guard let window, parent.attachedSheet == nil else { return }
        parent.beginSheet(window) { [self] response in
            guard response == .continue else { return }
            let provider = selectedProvider
            Task { @MainActor in onContinue(provider) }
        }
    }

    private var selectedProvider: Provider {
        let index = providerPicker.indexOfSelectedItem
        return Provider.allCases.indices.contains(index) ? Provider.allCases[index] : .claude
    }

    private func updateExplanation() {
        explanation.stringValue = selectedProvider == .claude
            ? "Opens claude.ai in your browser to sign in to this Claude subscription and read its usage. API Credits use a separate Claude Platform sign-in that you can connect later on the account page."
            : "If the Codex CLI on this Mac is signed in, you can use that login. Otherwise Terminal opens to sign in to a separate Codex login for this account through the official browser flow. Your existing CLI login is never changed."
        fitWindowToContent()
    }

    /// Sizes the sheet to the fitted content, so the explanation and buttons are never clipped when the text changes.
    private func fitWindowToContent() {
        guard let window, let root = window.contentView else { return }
        root.layoutSubtreeIfNeeded()
        let size = root.fittingSize
        guard window.contentRect(forFrameRect: window.frame).size != size else { return }
        window.setContentSize(size)
    }

    /// The second Add Codex Account step, shown only when this Mac's Codex CLI is already signed in with ChatGPT.
    static func chooseCodexLogin(_ login: CodexCurrentLogin, in window: NSWindow) async -> CodexLoginChoice {
        let alert = NSAlert()
        alert.messageText = "Add Codex Account"
        let identity = login.email.map { " as \($0)" } ?? ""
        alert.informativeText = "The Codex CLI on this Mac is signed in\(identity). AI Usage Stats can read that login without changing it.\n\nA ChatGPT web or desktop-app login is only reusable when the Codex CLI on this Mac is signed in."
        alert.addButton(withTitle: login.email.map { "Use Current Codex Login (\($0))" } ?? "Use Current Codex Login")
        alert.addButton(withTitle: "Sign In with a Different Account…")
        // NSAlert assigns Escape to the button titled Cancel.
        alert.addButton(withTitle: "Cancel")
        let response = await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        switch response {
        case .alertFirstButtonReturn: return .useCurrentLogin
        case .alertSecondButtonReturn: return .signInSeparately
        default: return .cancel
        }
    }

    @objc private func selectProvider(_ sender: Any?) { updateExplanation() }

    @objc private func cancel(_ sender: Any?) { end(.cancel) }

    @objc private func proceed(_ sender: Any?) { end(.continue) }

    private func end(_ response: NSApplication.ModalResponse) {
        withExtendedLifetime(self) {
            guard let window, let parent = window.sheetParent else { return }
            parent.endSheet(window, returnCode: response)
            window.orderOut(nil)
        }
    }
}
