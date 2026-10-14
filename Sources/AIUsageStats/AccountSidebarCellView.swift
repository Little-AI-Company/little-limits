import AppKit
import UsageCore

@MainActor
final class AccountSidebarCellView: NSTableCellView {
    struct Display: Equatable {
        let identity: String
        let provider: String
        let summary: AccountQuotaSummary
        let detail: String
    }

    static let singleLineRowHeight: CGFloat = 66
    static let wrappedRowHeight: CGFloat = 82
    /// Source-list column width exceeds the identity field bounds by the cell margins minus label alignment insets.
    static let identityTextWidthInset: CGFloat = 20
    private static let identityFont = NSFont.systemFont(ofSize: 13, weight: .medium)

    private let identity = NSTextField(labelWithString: "")
    private let provider = NSTextField(labelWithString: "")
    private let quota = NSTextField(labelWithString: "")
    private let progress = NSLevelIndicator()
    private var displayed: Display?

    static func rowHeight(for identity: String, columnWidth: CGFloat) -> CGFloat {
        let textWidth = columnWidth - identityTextWidthInset
        guard textWidth > 1 else { return singleLineRowHeight }
        let measured = (identity as NSString).boundingRect(with: NSSize(width: textWidth, height: 64),
                                                           options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                           attributes: [.font: identityFont])
        return measured.height > identityFont.boundingRectForFont.height * 1.5 ? wrappedRowHeight : singleLineRowHeight
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        identity.font = Self.identityFont
        identity.lineBreakMode = .byCharWrapping
        identity.maximumNumberOfLines = 2
        identity.cell?.truncatesLastVisibleLine = true
        identity.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        identity.setContentCompressionResistancePriority(.required, for: .vertical)
        provider.font = .systemFont(ofSize: 11)
        quota.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        quota.alignment = .right
        quota.setContentCompressionResistancePriority(.required, for: .horizontal)
        progress.levelIndicatorStyle = .continuousCapacity
        progress.minValue = 0
        progress.maxValue = 100
        progress.warningValue = 100
        progress.criticalValue = 100
        progress.isEditable = false
        textField = identity
        for view in [identity, provider, quota, progress] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            identity.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            identity.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            identity.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            provider.leadingAnchor.constraint(equalTo: identity.leadingAnchor),
            provider.topAnchor.constraint(equalTo: identity.bottomAnchor, constant: 3),
            quota.leadingAnchor.constraint(greaterThanOrEqualTo: provider.trailingAnchor, constant: 6),
            quota.trailingAnchor.constraint(equalTo: identity.trailingAnchor),
            quota.firstBaselineAnchor.constraint(equalTo: provider.firstBaselineAnchor),
            progress.leadingAnchor.constraint(equalTo: identity.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: identity.trailingAnchor),
            progress.topAnchor.constraint(equalTo: provider.bottomAnchor, constant: 5),
            progress.heightAnchor.constraint(equalToConstant: 5)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func noteColumnWidth(_ columnWidth: CGFloat) {
        let textWidth = columnWidth - Self.identityTextWidthInset
        guard textWidth > 1 else { return }
        identity.preferredMaxLayoutWidth = textWidth
    }

    override func layout() {
        let width = identity.bounds.width
        if width > 0, abs(identity.preferredMaxLayoutWidth - width) > 0.5 {
            identity.preferredMaxLayoutWidth = width
        }
        super.layout()
    }

    func render(_ display: Display) {
        guard displayed != display else { return }
        displayed = display
        identity.stringValue = display.identity
        provider.stringValue = display.provider
        quota.textColor = .labelColor
        progress.isHidden = true
        var severityDescription = ""
        switch display.summary {
        case let .available(remaining, severity, _):
            quota.stringValue = remainingText(remaining) + " left"
            progress.doubleValue = remaining
            progress.isHidden = false
            let color: NSColor
            switch severity {
            case .normal: color = .systemGreen
            case .warning: color = .systemOrange; severityDescription = "Low remaining quota. "
            case .critical: color = .systemRed; severityDescription = "Very low remaining quota. "
            }
            quota.textColor = color
            progress.fillColor = color
            progress.warningFillColor = color
            progress.criticalFillColor = color
        case .unknown: quota.stringValue = "Usage unknown"
        case .inactive: quota.stringValue = "No active quota"
        case .stale: quota.stringValue = "Usage stale"
        case .unavailable: quota.stringValue = "Unavailable"
        case .authenticationRequired: quota.stringValue = "Sign-in required"
        }
        let description = "\(display.provider), \(display.identity). \(quota.stringValue). \(severityDescription)\(display.detail)"
        toolTip = description
        setAccessibilityLabel(description)
        progress.setAccessibilityLabel("Remaining quota")
        for view in [identity, provider, quota, progress] { view.toolTip = description }
    }

    private func remainingText(_ remaining: Double) -> String {
        if remaining == remaining.rounded() { return String(format: "%.0f%%", remaining) }
        // Keep the displayed side of each severity boundary accurate after rounding.
        if remaining > 20, remaining < 20.1 { return ">20%" }
        if remaining < 10, remaining > 9.9 { return "<10%" }
        if remaining > 0, remaining < 0.1 { return "<0.1%" }
        return String(format: "%.1f%%", remaining)
    }
}

@MainActor
final class AccountSidebarTableView: NSTableView {
    var accountMenu: ((Int) -> NSMenu?)?
    var removeSelectedAccount: (() -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        return accountMenu?(row(at: point))
    }

    override func keyDown(with event: NSEvent) {
        if (event.keyCode == 51 || event.keyCode == 117), event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            removeSelectedAccount?()
        } else { super.keyDown(with: event) }
    }
}
