import AppKit

/// Account detail anchored in the reset popover. One account, every reported window.
@MainActor
final class UsageEventDetailsViewController: NSViewController {
    var onViewAccount: ((UUID) -> Void)?
    var onReturn: (() -> Void)?

    private let root = DetailRootView()
    private let scroll = NSScrollView()
    private let document = DetailDocumentView()
    private let stack = NSStackView()
    private let viewAccountButton = NSButton(title: "View Account", target: nil, action: nil)
    private var accountID: UUID?
    private var applied: HomeDetailContent?

    override func loadView() {
        root.onReturn = { [weak self] in self?.onReturn?() }
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        viewAccountButton.target = self
        viewAccountButton.action = #selector(viewAccount(_:))
        viewAccountButton.bezelStyle = .rounded
        viewAccountButton.controlSize = .regular
        viewAccountButton.keyEquivalent = ""
        viewAccountButton.setAccessibilityLabel("View Account")
        viewAccountButton.setAccessibilityHelp("Press Space to open this account.")
        root.addSubview(scroll)
        document.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -12),
            stack.widthAnchor.constraint(equalToConstant: 328)
        ])
        view = root
    }

    func apply(_ content: HomeDetailContent) {
        if !isViewLoaded { _ = view }
        let changesAccount = accountID != content.accountID
        let accountActionHadFocus = view.window?.firstResponder === viewAccountButton
        accountID = content.accountID
        guard content != applied else {
            updatePreferredSize()
            return
        }
        applied = content
        replaceRows(with: content)
        updatePreferredSize()
        if changesAccount {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        } else if accountActionHadFocus {
            view.window?.makeFirstResponder(viewAccountButton)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onReturn?()
    }

    private func replaceRows(with content: HomeDetailContent) {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let heading = NSTextField(wrappingLabelWithString: content.heading)
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        heading.textColor = .labelColor
        heading.preferredMaxLayoutWidth = 328
        heading.setAccessibilityLabel(content.heading)
        stack.addArrangedSubview(heading)
        for row in content.rows {
            stack.addArrangedSubview(rowView(row))
        }
        let updated = NSTextField(wrappingLabelWithString: content.updated)
        updated.font = .systemFont(ofSize: 12)
        updated.textColor = .labelColor
        updated.preferredMaxLayoutWidth = 328
        updated.toolTip = content.updatedToolTip
        updated.setAccessibilityLabel(content.updated)
        stack.addArrangedSubview(updated)
        stack.addArrangedSubview(viewAccountButton)
        var spoken = [content.heading]
        for row in content.rows {
            spoken.append("\(row.label), \(row.value)")
            if let detail = row.detail { spoken.append(detail) }
        }
        spoken.append(content.updated)
        root.setAccessibilityLabel(spoken.joined(separator: ". "))
    }

    private func rowView(_ row: HomeDetailContent.Row) -> NSView {
        let group = NSStackView()
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 1
        let label = NSTextField(wrappingLabelWithString: row.label)
        label.font = .systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .labelColor
        label.preferredMaxLayoutWidth = 328
        let value = NSTextField(wrappingLabelWithString: row.value)
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.textColor = row.tone.textColor
        value.preferredMaxLayoutWidth = 328
        group.addArrangedSubview(label)
        group.addArrangedSubview(value)
        if let detail = row.detail {
            let detailField = NSTextField(wrappingLabelWithString: detail)
            detailField.font = .systemFont(ofSize: 11)
            detailField.textColor = .secondaryLabelColor
            detailField.preferredMaxLayoutWidth = 328
            group.addArrangedSubview(detailField)
        }
        group.toolTip = row.toolTip
        group.setAccessibilityLabel("\(row.label), \(row.value). \(row.detail ?? "")")
        return group
    }

    private func updatePreferredSize() {
        stack.layoutSubtreeIfNeeded()
        let fitting = stack.fittingSize.height + 24
        let height = min(max(fitting, 140), 480)
        preferredContentSize = NSSize(width: 360, height: height)
    }

    @objc private func viewAccount(_ sender: Any?) {
        guard let accountID else { return }
        onViewAccount?(accountID)
    }
}

@MainActor
private final class DetailDocumentView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class DetailRootView: NSView {
    var onReturn: (() -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        switch event.charactersIgnoringModifiers {
        case "\r", "\u{3}":
            onReturn?()
            return true
        default:
            return super.performKeyEquivalent(with: event)
        }
    }
}
