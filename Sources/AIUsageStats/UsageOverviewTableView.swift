import AppKit

/// Account usage table. Rows stay in saved profile order. The table is as tall as its rows, so the
/// Home document does the vertical scrolling; columns share the width and fit the minimum window.
@MainActor
final class UsageOverviewTableView: NSView, NSTableViewDataSource, NSTableViewDelegate {
    var onReconnect: ((UUID) -> Void)?

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
        table.intercellSpacing = NSSize(width: 8, height: 4)
        table.rowSizeStyle = .custom
        table.usesAlternatingRowBackgroundColors = false
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        table.setAccessibilityLabel("Account usage")
        for column in Column.all {
            let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(column.rawValue))
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

    /// Header plus every row, so no row is clipped and no nested vertical scroller appears.
    override var intrinsicContentSize: NSSize {
        let header = table.headerView?.frame.height ?? 0
        let spacing = table.intercellSpacing.height
        let body = rows.indices.reduce(CGFloat(0)) { $0 + tableView(table, heightOfRow: $1) + spacing }
        return NSSize(width: NSView.noIntrinsicMetric, height: ceil(header + max(body, 36)))
    }

    /// AppKit autoresizes columns only once they already fill the clip view, so fit them when they do not.
    override func layout() {
        super.layout()
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
        let reconnectAccountID = focusedReconnectAccountID()
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
            if let reconnectAccountID {
                if let row = rows.firstIndex(where: { $0.id == reconnectAccountID && $0.showsReconnect }) {
                    table.scrollRowToVisible(row)
                    let cell = table.view(atColumn: 0, row: row, makeIfNecessary: true) as? AccountCell
                    if cell?.focusReconnect() != true {
                        window?.makeFirstResponder(table)
                    }
                } else {
                    window?.makeFirstResponder(table)
                }
            } else if tableHadFocus {
                window?.makeFirstResponder(table)
            }
        }
    }

    private func focusedReconnectAccountID() -> UUID? {
        guard let responder = window?.firstResponder as? NSView else { return nil }
        var ancestor: NSView? = responder
        while let candidate = ancestor {
            if let cell = candidate as? AccountCell, cell.isReconnectControl(responder) {
                return cell.accountID
            }
            if candidate === table { break }
            ancestor = candidate.superview
        }
        return nil
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let tableColumn, rows.indices.contains(row) else { return nil }
        let record = rows[row]
        switch tableColumn.identifier.rawValue {
        case Column.account.rawValue:
            let cell = reuse(tableColumn.identifier, in: tableView) { AccountCell(frame: .zero) }
            cell.render(record)
            if onReconnect != nil {
                cell.onReconnect = { [weak self] in self?.onReconnect?(record.id) }
            } else {
                cell.onReconnect = nil
            }
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

    /// Minimums sum to 628 pt plus 48 pt spacing: the content width of the 1020 pt minimum window
    /// beside a 260 pt sidebar, less 32 pt margins.
    var minimumWidth: CGFloat {
        switch self {
        case .account: 140
        case .session, .weekly: 96
        case .other: 120
        case .earned: 104
        case .updated: 72
        }
    }

    /// Initial widths sum to 900 pt plus spacing, inside the default window; uniform resizing shares the rest.
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

@MainActor
private final class AccountCell: NSTableCellView {
    var onReconnect: (() -> Void)? {
        didSet { reconnectButton.isEnabled = onReconnect != nil }
    }
    private(set) var accountID: UUID?
    private let icon = NSImageView()
    private let titleField = HomeText.label("", size: 13, weight: .semibold)
    private let identityField = HomeText.label("", size: 12)
    private let planField = HomeText.label("", size: 12, color: .secondaryLabelColor)
    private let statusField = HomeText.label("", size: 12)
    private let reconnectButton = NSButton(title: "Reconnect…", target: nil, action: nil)
    private let lines = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        lines.orientation = .vertical
        lines.alignment = .leading
        lines.spacing = 2
        lines.detachesHiddenViews = true
        lines.translatesAutoresizingMaskIntoConstraints = false
        reconnectButton.target = self
        reconnectButton.action = #selector(reconnect(_:))
        reconnectButton.bezelStyle = .rounded
        reconnectButton.controlSize = .regular
        reconnectButton.font = .systemFont(ofSize: NSFont.systemFontSize)
        reconnectButton.setAccessibilityLabel("Reconnect")
        for field in [titleField, identityField, planField, statusField] {
            lines.addArrangedSubview(field)
        }
        lines.addArrangedSubview(reconnectButton)
        addSubview(icon)
        addSubview(lines)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            icon.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            lines.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            lines.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            lines.topAnchor.constraint(equalTo: topAnchor, constant: 6)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func render(_ row: HomeAccountRow) {
        accountID = row.id
        let image = ProviderIcons.images[row.provider]
        if icon.image !== image { icon.image = image }
        icon.contentTintColor = .labelColor
        icon.isHidden = image == nil
        titleField.stringValue = row.title
        identityField.stringValue = row.identity
        identityField.setAccessibilityLabel(row.identityIsEmail ? "Verified email \(row.identity)" : "Email unavailable")
        planField.stringValue = row.plan ?? ""
        planField.isHidden = row.plan == nil
        statusField.stringValue = row.status ?? ""
        statusField.isHidden = row.status == nil
        reconnectButton.isHidden = !row.showsReconnect
        reconnectButton.setAccessibilityLabel("Reconnect \(row.title)")
        reconnectButton.setAccessibilityIdentifier("home.reconnect.\(row.id.uuidString)")
        toolTip = row.toolTip
        setAccessibilityLabel(row.accessibilityLabel)
    }

    static func height(for row: HomeAccountRow) -> CGFloat {
        var lines: CGFloat = 2
        if row.plan != nil { lines += 1 }
        if row.status != nil { lines += 1 }
        var height = 12 + lines * 18
        if row.showsReconnect { height += 30 }
        return height
    }

    func isReconnectControl(_ view: NSView) -> Bool { view === reconnectButton }

    func focusReconnect() -> Bool {
        guard !reconnectButton.isHidden, reconnectButton.isEnabled else { return false }
        return window?.makeFirstResponder(reconnectButton) ?? false
    }

    @objc private func reconnect(_ sender: Any?) { onReconnect?() }
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
            let primary = record.isQuiet
                ? HomeText.label(record.primary, size: 12, color: .secondaryLabelColor)
                : HomeText.label(record.primary, size: 12, weight: .semibold, digits: true)
            if let symbol = HomeText.stateSymbol(record.tone) {
                let value = NSStackView(views: [symbol, primary])
                value.orientation = .horizontal
                value.alignment = .centerY
                value.spacing = 3
                group.addArrangedSubview(value)
            } else {
                group.addArrangedSubview(primary)
            }
            if let secondary = record.secondary {
                group.addArrangedSubview(HomeText.label(secondary, size: 11, color: .secondaryLabelColor))
            }
            if let tertiary = record.tertiary {
                group.addArrangedSubview(HomeText.label(tertiary, size: 11, color: .secondaryLabelColor))
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
            var line: CGFloat = 18
            if record.secondary != nil { line += 15 }
            if record.tertiary != nil { line += 15 }
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
    private let primaryField = HomeText.label("", size: 12, weight: .regular, digits: true)
    private let secondaryField = HomeText.label("", size: 11, color: .secondaryLabelColor)

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
        secondary == nil ? 32 : 48
    }
}
