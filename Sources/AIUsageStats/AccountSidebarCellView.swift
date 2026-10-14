import AppKit
import UsageCore

/// A standard single-line source-list row: provider template image, identity, trailing quota text, and a state symbol.
/// The table sets the row height from the person's sidebar size setting.
@MainActor
final class AccountSidebarCellView: NSTableCellView {
    enum Indicator: Equatable {
        case none, low, limitReached, signInRequired, stale

        fileprivate var symbol: (name: String, color: NSColor)? {
            switch self {
            case .none: nil
            case .low: ("exclamationmark.triangle.fill", .systemOrange)
            case .limitReached, .signInRequired: ("exclamationmark.triangle.fill", .systemRed)
            case .stale: ("clock", .secondaryLabelColor)
            }
        }
    }

    struct Display: Equatable {
        let identity: String
        let provider: Provider
        /// Quota text from the most to the least detailed. The row shows the longest one that fits.
        let quotaTexts: [String]
        let indicator: Indicator
        /// Full description for the tooltip and VoiceOver.
        let description: String
    }

    private static let spacing: CGFloat = 6
    private static let indicatorSize: CGFloat = 14
    /// Room kept for the identity before the quota text may use its detailed form.
    private static let identityReserve: CGFloat = 110

    private let icon = NSImageView()
    private let identity = NSTextField(labelWithString: "")
    private let quota = NSTextField(labelWithString: "")
    private let indicator = NSImageView()
    private var displayed: Display?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.imageScaling = .scaleProportionallyDown
        identity.lineBreakMode = .byTruncatingMiddle
        identity.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        identity.setContentHuggingPriority(.defaultLow, for: .horizontal)
        quota.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        quota.textColor = .labelColor
        quota.lineBreakMode = .byTruncatingTail
        quota.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        quota.setContentHuggingPriority(.required, for: .horizontal)
        indicator.imageScaling = .scaleProportionallyDown
        for view in [icon, identity, quota, indicator] { view.setAccessibilityElement(false) }
        imageView = icon
        textField = identity
        let row = NSStackView(views: [icon, identity, quota, indicator])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = Self.spacing
        row.detachesHiddenViews = true
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            indicator.widthAnchor.constraint(equalToConstant: Self.indicatorSize),
            indicator.heightAnchor.constraint(equalToConstant: Self.indicatorSize)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ display: Display) {
        guard displayed != display else { return }
        displayed = display
        icon.image = ProviderIcons.images[display.provider]
        identity.stringValue = display.identity
        if let symbol = display.indicator.symbol {
            indicator.image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil)
            indicator.contentTintColor = symbol.color
            indicator.isHidden = false
        } else {
            indicator.image = nil
            indicator.isHidden = true
        }
        toolTip = display.description
        setAccessibilityLabel(display.description)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        // Match the quota text to the identity font the table chose for the sidebar size setting.
        let pointSize = identity.font?.pointSize ?? NSFont.systemFontSize
        if quota.font?.pointSize != pointSize {
            quota.font = .monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
        }
        selectQuotaText()
    }

    private func selectQuotaText() {
        guard let display = displayed, let font = quota.font else { return }
        let identityWidth = min((display.identity as NSString).size(withAttributes: [.font: identity.font ?? font]).width,
                                Self.identityReserve)
        var available = bounds.width - 6 - 16 - Self.spacing * 2 - identityWidth
        if !indicator.isHidden { available -= Self.indicatorSize + Self.spacing }
        let text = display.quotaTexts.first { ($0 as NSString).size(withAttributes: [.font: font]).width <= available }
            ?? display.quotaTexts.last ?? ""
        if quota.stringValue != text { quota.stringValue = text }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet { quota.cell?.backgroundStyle = backgroundStyle }
    }
}

@MainActor
final class HomeSidebarCellView: NSTableCellView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: "house", accessibilityDescription: nil)
        image.imageScaling = .scaleProportionallyDown
        image.setAccessibilityElement(false)
        let label = NSTextField(labelWithString: "Home")
        label.lineBreakMode = .byTruncatingTail
        label.setAccessibilityElement(false)
        imageView = image
        textField = label
        let row = NSStackView(views: [image, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            row.centerYAnchor.constraint(equalTo: centerYAnchor),
            image.widthAnchor.constraint(equalToConstant: 16),
            image.heightAnchor.constraint(equalToConstant: 16)
        ])
        setAccessibilityLabel("Home")
        setAccessibilityHelp("Show the reset calendar and account usage.")
    }

    required init?(coder: NSCoder) { nil }
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
