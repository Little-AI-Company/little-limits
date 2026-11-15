import AppKit

@MainActor
final class UsageOverviewTableView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    private let scroll = HomeNestedScrollView()
    private let table = NSTableView()
    private var rows: [HomeAccountRow] = []
    private var headings = HomeColumnHeadings(session: "Session", weekly: "Weekly", other: "Other limits")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        table.style = .fullWidth
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.allowsColumnReordering = false
        table.allowsColumnSelection = false
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.selectionHighlightStyle = .none
        table.gridStyleMask = .solidHorizontalGridLineMask
        table.gridColor = BrandPalette.separator
        table.intercellSpacing = NSSize(width: 8, height: 4)
        table.rowSizeStyle = .custom
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Account usage")
        for column in Column.all {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
            tableColumn.headerCell = PaperHeaderCell(textCell: column.defaultTitle)
            tableColumn.title = column.defaultTitle
            tableColumn.minWidth = column.minimumWidth
            tableColumn.maxWidth = 640
            tableColumn.width = column.initialWidth
            tableColumn.resizingMask = [.autoresizingMask, .userResizingMask]
            tableColumn.headerToolTip = column.help
            table.addTableColumn(tableColumn)
        }
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = true
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .none
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.documentView = table
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)
        setContentCompressionResistancePriority(NSLayoutConstraint.Priority(250), for: .horizontal)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize {
        let header = table.headerView?.frame.height ?? 0
        let spacing = table.intercellSpacing.height
        let body = rows.indices.reduce(CGFloat(0)) { $0 + tableView(table, heightOfRow: $1) + spacing }
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(header + max(body, 36)))
    }

    override func layout() {
        super.layout()
        fitColumnsToClipView()
    }

    private func fitColumnsToClipView() {
        let width = scroll.contentView.bounds.width
        guard width > 1, table.numberOfColumns > 0 else { return }
        let extent = table.rect(ofColumn: table.numberOfColumns - 1).maxX
        if abs(extent - width) > 1 { table.sizeToFit() }
    }

    func apply(rows: [HomeAccountRow], headings: HomeColumnHeadings) {
        let rowsChanged = rows != self.rows
        let headingsChanged = headings != self.headings
        guard rowsChanged || headingsChanged else { return }
        let selectedAccountID = self.rows.indices.contains(table.selectedRow) ? self.rows[table.selectedRow].id : nil
        let tableHadFocus = window?.firstResponder === table
        let scrollOrigin = scroll.contentView.bounds.origin
        self.rows = rows
        self.headings = headings
        if headingsChanged { applyHeadings() }
        if rowsChanged {
            invalidateIntrinsicContentSize()
            table.reloadData()
            if let selectedAccountID, let row = rows.firstIndex(where: { $0.id == selectedAccountID }) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            } else {
                table.deselectAll(nil)
            }
            table.layoutSubtreeIfNeeded()
            scroll.contentView.scroll(to: scrollOrigin)
            scroll.reflectScrolledClipView(scroll.contentView)
            if tableHadFocus {
                window?.makeFirstResponder(table)
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, rows.indices.contains(row) else { return nil }
        let record = rows[row]
        switch tableColumn.identifier.rawValue {
        case Column.account.rawValue:
            let cell = reuse(tableColumn.identifier, in: tableView) { AccountCell(frame: .zero) }
            cell.render(record)
            return cell
        case Column.session.rawValue:
            let cell = reuse(tableColumn.identifier, in: tableView) { MeterCell(frame: .zero) }
            cell.render(record.session)
            return cell
        case Column.weekly.rawValue:
            let cell = reuse(tableColumn.identifier, in: tableView) { MeterCell(frame: .zero) }
            cell.render(record.weekly)
            return cell
        case Column.other.rawValue:
            let cell = reuse(tableColumn.identifier, in: tableView) { MeterCell(frame: .zero) }
            cell.render(record.other)
            return cell
        case Column.earned.rawValue:
            let cell = reuse(tableColumn.identifier, in: tableView) { MeterCell(frame: .zero) }
            cell.render(record.earned)
            return cell
        case Column.updated.rawValue:
            let cell = reuse(tableColumn.identifier, in: tableView) { UpdatedCell(frame: .zero) }
            cell.render(primary: record.updatedPrimary, secondary: record.updatedSecondary)
            return cell
        default:
            return nil
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard rows.indices.contains(row) else { return 36 }
        let record = rows[row]
        let account = AccountCell.height(for: record)
        let meters = [record.session, record.weekly, record.other, record.earned].map(MeterCell.height(for:))
        let updated = UpdatedCell.height(primary: record.updatedPrimary, secondary: record.updatedSecondary)
        return max(36, account, updated, meters.max() ?? 0)
    }

    private func applyHeadings() {
        title(headings.session, for: .session, help: HomeInterfaceFormatting.sessionColumnHelp)
        title(headings.weekly, for: .weekly, help: HomeInterfaceFormatting.weeklyColumnHelp)
        title(headings.other, for: .other, help: HomeInterfaceFormatting.otherColumnHelp)
        title(Column.earned.defaultTitle, for: .earned, help: HomeInterfaceFormatting.earnedColumnHelp)
        title("Updated", for: .updated, help: HomeInterfaceFormatting.updatedColumnHelp)
        title("Account", for: .account, help: "Provider, account, and reported plan.")
    }

    private func title(_ title: String, for column: Column, help: String) {
        guard let tableColumn = table.tableColumns.first(where: { $0.identifier.rawValue == column.rawValue }) else { return }
        tableColumn.title = title
        tableColumn.headerToolTip = help
    }

    private func reuse<View: NSView>(_ identifier: NSUserInterfaceItemIdentifier, in table: NSTableView, make: () -> View) -> View {
        if let existing = table.makeView(withIdentifier: identifier, owner: self) as? View {
            return existing
        }
        let view = make()
        view.identifier = identifier
        return view
    }
}

private enum Column: String, CaseIterable {
    case account
    case session
    case weekly
    case other
    case earned
    case updated

    static var all: [Column] { allCases }

    var defaultTitle: String {
        switch self {
        case .account: "Account"
        case .session: "Session"
        case .weekly: "Weekly"
        case .other: "Other limits"
        case .earned: "Earned resets"
        case .updated: "Updated"
        }
    }

    var minimumWidth: CGFloat {
        switch self {
        case .account: 120
        case .session, .weekly: 110
        case .other: 112
        case .earned: 108
        case .updated: 84
        }
    }

    var initialWidth: CGFloat {
        switch self {
        case .account: 200
        case .session, .weekly: 136
        case .other: 168
        case .earned: 152
        case .updated: 108
        }
    }

    var help: String {
        switch self {
        case .account: "Provider, account, and reported plan."
        case .session: HomeInterfaceFormatting.sessionColumnHelp
        case .weekly: HomeInterfaceFormatting.weeklyColumnHelp
        case .other: HomeInterfaceFormatting.otherColumnHelp
        case .earned: HomeInterfaceFormatting.earnedColumnHelp
        case .updated: HomeInterfaceFormatting.updatedColumnHelp
        }
    }
}

private final class PaperHeaderCell: NSTableHeaderCell {
    override init(textCell string: String) {
        super.init(textCell: string)
        textColor = BrandPalette.secondaryLabel
    }

    required init(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView) {
        BrandPalette.contentBackground.setFill()
        cellFrame.fill()
        BrandPalette.separator.setFill()
        let hairline = controlView.isFlipped ? cellFrame.maxY - 1 : cellFrame.minY
        NSRect(x: cellFrame.minX, y: hairline, width: cellFrame.width, height: 1).fill()
        drawInterior(withFrame: cellFrame, in: controlView)
    }
}

@MainActor
private final class AccountCell: NSTableCellView {
    private let icon = NSImageView()
    private let titleField = HomeText.label("", size: 13, weight: .semibold)
    private let planField = HomeText.label("", size: 13, color: BrandPalette.secondaryLabel)
    private let identityField = HomeText.label("", size: 12, color: BrandPalette.secondaryLabel)
    private let statusField = HomeText.label("", size: 12)
    private let statusLine = NSStackView()
    private var statusSymbol: NSImageView?
    private let lines = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        planField.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        planField.setContentHuggingPriority(.required, for: .horizontal)
        let titleLine = NSStackView(views: [titleField, planField])
        titleLine.orientation = .horizontal
        titleLine.alignment = .firstBaseline
        titleLine.spacing = 6
        titleLine.detachesHiddenViews = true
        statusLine.orientation = .horizontal
        statusLine.alignment = .centerY
        statusLine.spacing = 4
        statusLine.addArrangedSubview(statusField)
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 2
        lines.detachesHiddenViews = true
        lines.translatesAutoresizingMaskIntoConstraints = false
        for line in [titleLine, identityField, statusLine] {
            lines.addArrangedSubview(line)
        }
        addSubview(icon)
        addSubview(lines)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            lines.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            lines.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            lines.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ row: HomeAccountRow) {
        let image = ProviderIcons.images[row.provider]
        if icon.image !== image { icon.image = image }
        icon.contentTintColor = BrandPalette.label
        icon.isHidden = image == nil
        titleField.stringValue = row.title
        planField.stringValue = row.plan ?? ""
        planField.isHidden = row.plan == nil
        identityField.stringValue = row.identity
        identityField.setAccessibilityLabel(row.identityIsEmail ? "Verified email \(row.identity)" : "Email unavailable")
        statusField.stringValue = row.status ?? ""
        statusLine.isHidden = row.status == nil
        statusSymbol?.removeFromSuperview()
        statusSymbol = nil
        if let state = row.state, let status = row.status, let symbol = HomeText.stateSymbol(state, description: status) {
            statusLine.insertArrangedSubview(symbol, at: 0)
            statusSymbol = symbol
        }
        toolTip = row.toolTip
        setAccessibilityLabel(row.accessibilityLabel)
    }

    static func height(for row: HomeAccountRow) -> CGFloat {
        var height: CGFloat = 14 + 18 + 17
        if row.status != nil { height += 17 }
        return height
    }
}

@MainActor
private final class MeterCell: NSTableCellView {
    private let lines = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 6
        lines.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lines)
        NSLayoutConstraint.activate([
            lines.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            lines.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            lines.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ cell: HomeMeterCell) {
        for view in lines.arrangedSubviews {
            lines.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let records = Self.records(in: cell)
        for record in records {
            let group = NSStackView()
            group.orientation = .vertical
            group.alignment = .leading
            group.spacing = 1
            for line in record.preface {
                group.addArrangedSubview(HomeText.label(line, size: 12, color: BrandPalette.secondaryLabel))
            }
            if !record.primary.isEmpty {
                let primary = record.isQuiet
                    ? HomeText.label(record.primary, size: 13, color: BrandPalette.secondaryLabel)
                    : HomeText.label(record.primary, size: 13, weight: .semibold, digits: true)
                var value: [NSView] = [primary]
                if let symbol = HomeText.stateSymbol(record.tone, size: 12) { value.insert(symbol, at: 0) }
                if value.count == 1 {
                    group.addArrangedSubview(primary)
                } else {
                    let line = NSStackView(views: value)
                    line.orientation = .horizontal
                    line.alignment = .centerY
                    line.spacing = 4
                    group.addArrangedSubview(line)
                }
                if let word = record.tone.word { group.addArrangedSubview(HomeText.label(word, size: 13)) }
            }
            if let secondary = record.secondary {
                group.addArrangedSubview(HomeText.label(secondary, size: 12, color: BrandPalette.secondaryLabel))
            }
            if let tertiary = record.tertiary {
                group.addArrangedSubview(HomeText.label(tertiary, size: 12, color: BrandPalette.secondaryLabel))
            }
            lines.addArrangedSubview(group)
        }
        let spoken = records.map(\.accessibilityLabel).joined(separator: ". ")
        toolTip = spoken
        setAccessibilityLabel(spoken)
    }

    static func height(for cell: HomeMeterCell) -> CGFloat {
        let records = records(in: cell)
        let body = records.reduce(CGFloat(0)) { total, record in
            var line: CGFloat = (record.primary.isEmpty ? 0 : 18) + CGFloat(record.preface.count) * 16
            if record.tone.word != nil, !record.primary.isEmpty { line += 17 }
            if record.secondary != nil { line += 16 }
            if record.tertiary != nil { line += 16 }
            return total + line + 6
        }
        return 12 + body
    }

    private static func records(in cell: HomeMeterCell) -> [HomeReadingLine] {
        switch cell {
        case .message(let line): [line]
        case .meters(let lines): lines
        }
    }
}

@MainActor
private final class UpdatedCell: NSTableCellView {
    private let primaryField = HomeText.label("", size: 13, weight: .regular, digits: true)
    private let secondaryField = HomeText.label("", size: 12, color: BrandPalette.secondaryLabel)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let lines = NSStackView(views: [primaryField, secondaryField])
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 1
        lines.translatesAutoresizingMaskIntoConstraints = false
        addSubview(lines)
        NSLayoutConstraint.activate([
            lines.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            lines.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            lines.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(primary: String, secondary: String?) {
        primaryField.stringValue = primary
        secondaryField.stringValue = secondary ?? ""
        secondaryField.isHidden = secondary == nil
        let spoken = secondary.map { "\(primary), \($0)" } ?? primary
        toolTip = spoken
        setAccessibilityLabel(spoken)
    }

    static func height(primary: String, secondary: String?) -> CGFloat {
        secondary == nil ? 32 : 50
    }
}
