import AppKit
import UsageCore

/// Home's Weekly Totals: one text row per pooled window and one Next reset row for each provider, aligned in a
/// grid. The grid is rebuilt only when the displayed lines change. The provider column has one width for every
/// provider, so separate grids (Weekly Totals and each forecast block) start their labels at the same x.
@MainActor
final class HomeTotalsView: NSView {
    private var lines: [HomeTotalLine] = []
    private var grid: NSGridView?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Weekly totals")
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ lines: [HomeTotalLine]) {
        guard lines != self.lines else { return }
        self.lines = lines
        grid?.removeFromSuperview()
        let rows = lines.map { line -> [NSView] in
            let provider = providerView(line.provider)
            let label = HomeText.label(line.label, size: 12)
            let value = HomeText.label(line.value, size: 12, weight: .semibold, digits: true)
            let detail = HomeText.label(line.detail, size: 12, digits: true)
            // The value reads the whole line, so VoiceOver does not repeat the label and detail.
            value.setAccessibilityLabel(line.accessibilityLabel)
            for field in [label, detail] { field.setAccessibilityElement(false) }
            for view in [provider, label, value, detail] where view !== NSGridCell.emptyContentView { view.toolTip = line.toolTip }
            return [provider, label, value, detail]
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 16
        grid.rowSpacing = 4
        // Every field uses one 12-point size, so centered rows line up their text.
        grid.yPlacement = .center
        grid.column(at: 0).width = Self.providerColumnWidth
        grid.translatesAutoresizingMaskIntoConstraints = false
        // A new provider starts after a gap, so each group reads as one block.
        for (index, line) in lines.enumerated() where index > 0 && line.provider != nil {
            grid.row(at: index).topPadding = 6
        }
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        self.grid = grid
    }

    /// The icon, the gap, and the widest provider name.
    private static let providerColumnWidth: CGFloat = {
        let names = Provider.allCases.map { HomeText.label($0.title, size: 12, weight: .semibold).fittingSize.width }
        return ceil(14 + 5 + (names.max() ?? 0))
    }()

    private func providerView(_ provider: Provider?) -> NSView {
        guard let provider else { return NSGridCell.emptyContentView }
        let name = HomeText.label(provider.title, size: 12, weight: .semibold)
        // Each value already names its provider, so VoiceOver does not read the name twice.
        name.setAccessibilityElement(false)
        guard let image = ProviderIcons.images[provider] else { return name }
        let icon = HomePassImageView(image: image)
        icon.contentTintColor = .labelColor
        icon.setAccessibilityElement(false)
        icon.widthAnchor.constraint(equalToConstant: 14).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 14).isActive = true
        let stack = NSStackView(views: [icon, name])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 5
        return stack
    }
}
