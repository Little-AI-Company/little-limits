import AppKit

@MainActor
final class AccountReadingView: NSView {
    struct Reading: Equatable {
        let label: String
        let value: String
        let timing: String
        let detail: String
    }

    private var readings: [Reading] = []
    private var grid: NSGridView?

    func render(_ readings: [Reading]) {
        guard self.readings != readings else { return }
        self.readings = readings
        grid?.removeFromSuperview()
        let rows = readings.map { reading -> [NSView] in
            let label = InterfaceControls.label(reading.label, size: 13)
            let value = InterfaceControls.label(reading.value, size: 15, weight: .semibold)
            let timing = InterfaceControls.label(reading.timing, size: 12)
            label.widthAnchor.constraint(equalToConstant: 112).isActive = true
            value.widthAnchor.constraint(equalToConstant: 108).isActive = true
            for field in [label, value, timing] {
                field.toolTip = reading.detail
            }
            return [label, value, timing]
        }
        let grid = NSGridView(views: rows)
        grid.columnSpacing = 12
        grid.rowSpacing = 10
        grid.rowAlignment = .firstBaseline
        grid.xPlacement = .fill
        grid.translatesAutoresizingMaskIntoConstraints = false
        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        self.grid = grid
    }
}
