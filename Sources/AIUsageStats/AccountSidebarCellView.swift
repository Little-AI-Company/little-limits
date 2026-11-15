import AppKit
import UsageCore

@MainActor
final class AccountSidebarCellView: NSTableCellView {
    enum Indicator: Equatable {
        case none, useSoon, low, almostOut, limitReached, signInRequired, stale, unavailable, inactive, waitingForSignIn

        init(_ tone: HomeReadingTone) {
            switch tone {
            case .neutral: self = .none
            case .useSoon: self = .useSoon
            case .warning: self = .low
            case .almostOut: self = .almostOut
            case .critical: self = .limitReached
            }
        }

        @MainActor fileprivate var symbol: (name: String, color: NSColor)? {
            switch self {
            case .none: nil
            case .useSoon: ("hourglass", BrandPalette.markBlue)
            case .low: ("exclamationmark.triangle.fill", StateSymbolColor.warning)
            case .almostOut, .limitReached: ("exclamationmark.octagon.fill", BrandPalette.destructive)
            case .signInRequired: ("person.crop.circle.badge.exclamationmark.fill", BrandPalette.destructive)
            case .stale: ("clock", BrandPalette.secondaryLabel)
            case .unavailable: ("exclamationmark.circle", BrandPalette.secondaryLabel)
            case .inactive: ("pause.circle", BrandPalette.secondaryLabel)
            case .waitingForSignIn: ("person.crop.circle.badge.clock", BrandPalette.secondaryLabel)
            }
        }
    }

    struct Display: Equatable {
        let identity: String
        let provider: Provider
        let quotaText: String
        let indicator: Indicator
        let description: String
    }

    private static let quotaFontReduction: CGFloat = 2
    static let lineSpacing: CGFloat = 1

    private let icon = NSImageView()
    private let identity = NSTextField(labelWithString: "")
    private let quota = NSTextField(labelWithString: "")
    private let indicator = NSImageView()
    private var displayed: Display?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.imageScaling = .scaleProportionallyDown
        icon.contentTintColor = BrandPalette.label
        identity.textColor = BrandPalette.label
        identity.lineBreakMode = .byTruncatingTail
        identity.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        quota.font = Self.quotaFont(identitySize: NSFont.systemFontSize)
        quota.textColor = BrandPalette.secondaryLabel
        quota.lineBreakMode = .byTruncatingTail
        quota.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        indicator.imageScaling = .scaleProportionallyDown
        indicator.symbolConfiguration = NSImage.SymbolConfiguration(scale: .small)
        indicator.setContentHuggingPriority(.required, for: .horizontal)
        indicator.setContentCompressionResistancePriority(.required, for: .horizontal)
        for view in [icon, identity, quota, indicator] { view.setAccessibilityElement(false) }
        imageView = icon
        textField = identity
        let quotaLine = NSStackView(views: [indicator, quota])
        quotaLine.orientation = .horizontal
        quotaLine.alignment = .centerY
        quotaLine.spacing = 3
        quotaLine.detachesHiddenViews = true
        let lines = NSStackView(views: [identity, quotaLine])
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = Self.lineSpacing
        lines.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)
        addSubview(lines)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: identity.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            lines.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            lines.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            lines.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ display: Display) {
        guard displayed != display else { return }
        displayed = display
        icon.image = ProviderIcons.images[display.provider]
        identity.stringValue = display.identity
        quota.stringValue = display.quotaText
        if let symbol = display.indicator.symbol {
            indicator.image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil)
            indicator.isHidden = false
        } else {
            indicator.image = nil
            indicator.isHidden = true
        }
        updateIndicatorTint()
        toolTip = display.description
        setAccessibilityLabel(display.description)
    }

    override func layout() {
        let font = Self.quotaFont(identitySize: identity.font?.pointSize ?? NSFont.systemFontSize)
        if quota.font != font { quota.font = font }
        super.layout()
    }

    private func updateIndicatorTint() {
        guard let color = displayed?.indicator.symbol?.color, indicator.contentTintColor != color else { return }
        indicator.contentTintColor = color
    }

    static func quotaFont(identitySize: CGFloat) -> NSFont {
        .monospacedDigitSystemFont(ofSize: max(10, identitySize - quotaFontReduction), weight: .regular)
    }
}

@MainActor
final class HomeSidebarCellView: NSTableCellView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: "house", accessibilityDescription: nil)
        image.imageScaling = .scaleProportionallyDown
        image.contentTintColor = BrandPalette.label
        image.setAccessibilityElement(false)
        let label = NSTextField(labelWithString: "Home")
        label.textColor = BrandPalette.label
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
final class SidebarRowView: NSTableRowView {
    static let selectionCornerRadius: CGFloat = 8
    static let selectionInset: CGFloat = 10

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func drawSelection(in dirtyRect: NSRect) {
        BrandPalette.selectedContentBackground.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: Self.selectionInset, dy: 0), xRadius: Self.selectionCornerRadius, yRadius: Self.selectionCornerRadius).fill()
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
