import AppKit
import UsageCore

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
            value.setAccessibilityLabel(line.accessibilityLabel)
            for field in [label, detail] { field.setAccessibilityElement(false) }
            for view in [provider, label, value, detail] where view !== NSGridCell.emptyContentView { view.toolTip = line.toolTip }
            return [provider, label, value, detail]
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 16
        grid.rowSpacing = 4
        grid.yPlacement = .center
        grid.column(at: 0).width = Self.providerColumnWidth
        grid.translatesAutoresizingMaskIntoConstraints = false
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

    private static let providerColumnWidth: CGFloat = {
        let names = Provider.allCases.map { HomeText.label($0.title, size: 12, weight: .semibold).fittingSize.width }
        return ceil(14 + 5 + (names.max() ?? 0))
    }()

    private func providerView(_ provider: Provider?) -> NSView {
        guard let provider else { return NSGridCell.emptyContentView }
        let name = HomeText.label(provider.title, size: 12, weight: .semibold)
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
