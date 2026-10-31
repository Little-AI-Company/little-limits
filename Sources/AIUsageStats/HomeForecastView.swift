import AppKit
import Charts
import SwiftUI
import UsageCore
import UsageHistory

@MainActor
final class HomeForecastView: NSView {
    var onRangeChange: ((HomeForecastRange) -> Void)?

    private let rangePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let blocks = NSStackView()
    private var forecasts: [HomeProviderForecast] = []
    private var notice: String?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let title = NSTextField(labelWithString: "Forecast")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        rangePopUp.addItems(withTitles: HomeForecastRange.allCases.map(\.title))
        rangePopUp.controlSize = .small
        rangePopUp.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
        rangePopUp.target = self
        rangePopUp.action = #selector(chooseRange(_:))
        rangePopUp.setAccessibilityLabel("Forecast range")
        rangePopUp.toolTip = "Choose how far the forecast projects. The chart shows the same length of history before Now."
        let header = NSStackView(views: [title, rangePopUp])
        header.orientation = .horizontal
        header.alignment = .firstBaseline
        header.spacing = 8
        blocks.orientation = .vertical
        blocks.alignment = .leading
        blocks.spacing = 12
        blocks.detachesHiddenViews = true
        let column = NSStackView(views: [header, blocks])
        column.orientation = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.translatesAutoresizingMaskIntoConstraints = false
        addSubview(column)
        NSLayoutConstraint.activate([
            column.leadingAnchor.constraint(equalTo: leadingAnchor),
            column.trailingAnchor.constraint(equalTo: trailingAnchor),
            column.topAnchor.constraint(equalTo: topAnchor),
            column.bottomAnchor.constraint(equalTo: bottomAnchor),
            blocks.widthAnchor.constraint(equalTo: column.widthAnchor)
        ])
    }

    required init?(coder: NSCoder) { nil }

    var selectedRange: HomeForecastRange {
        HomeForecastRange(rawValue: rangePopUp.indexOfSelectedItem) ?? .nextWeek
    }

    func apply(_ forecasts: [HomeProviderForecast], notice: String?, range: HomeForecastRange) {
        if rangePopUp.indexOfSelectedItem != range.rawValue { rangePopUp.selectItem(at: range.rawValue) }
        rangePopUp.isHidden = notice != nil || forecasts.allSatisfy { $0.chart == nil }
        guard forecasts != self.forecasts || notice != self.notice else { return }
        let previous = self.forecasts
        self.forecasts = forecasts
        self.notice = notice
        if let notice {
            replaceBlocks(with: [plainLine(notice)])
            return
        }
        let existing = blocks.arrangedSubviews.compactMap { $0 as? HomeForecastBlockView }
        if existing.count == forecasts.count, zip(previous, forecasts).allSatisfy({ $0.provider == $1.provider && ($0.notice == nil) == ($1.notice == nil) }) {
            for (view, forecast) in zip(existing, forecasts) { view.apply(forecast) }
            return
        }
        replaceBlocks(with: forecasts.map { forecast in
            let view = HomeForecastBlockView()
            view.apply(forecast)
            return view
        })
    }

    private func replaceBlocks(with views: [NSView]) {
        for view in blocks.arrangedSubviews {
            blocks.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        for view in views {
            blocks.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: blocks.widthAnchor).isActive = true
        }
    }

    private func plainLine(_ text: String) -> NSTextField {
        let line = NSTextField(wrappingLabelWithString: text)
        line.font = .systemFont(ofSize: 12)
        line.textColor = .labelColor
        return line
    }

    @objc private func chooseRange(_ sender: NSPopUpButton) {
        onRangeChange?(selectedRange)
    }
}

@MainActor
private final class HomeForecastBlockView: NSView {
    private let lines = HomeTotalsView()
    private let notice = NSTextField(wrappingLabelWithString: "")
    private let chart = NSHostingView(rootView: HomeForecastChart(model: nil))
    private var model: HomeForecastChartModel?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        lines.setAccessibilityLabel("Forecast")
        notice.font = .systemFont(ofSize: 12)
        notice.textColor = .labelColor
        chart.sizingOptions = []
        let stack = NSStackView(views: [notice, lines, chart])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.detachesHiddenViews = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            lines.widthAnchor.constraint(equalTo: stack.widthAnchor),
            chart.widthAnchor.constraint(equalTo: stack.widthAnchor),
            chart.heightAnchor.constraint(equalToConstant: 150)
        ])
    }

    required init?(coder: NSCoder) { nil }

    func apply(_ forecast: HomeProviderForecast) {
        notice.stringValue = forecast.notice ?? ""
        notice.isHidden = forecast.notice == nil
        lines.apply(forecast.lines)
        lines.isHidden = forecast.lines.isEmpty
        chart.isHidden = forecast.chart == nil
        if forecast.chart != model {
            model = forecast.chart
            chart.rootView = HomeForecastChart(model: forecast.chart)
        }
    }
}

struct HomeForecastChart: View {
    let model: HomeForecastChartModel?

    var body: some View {
        if let model {
            Chart {
                ForEach(Array(model.history.enumerated()), id: \.offset) { index, run in
                    ForEach(run, id: \.date) { point in
                        LineMark(x: .value("Time", point.date), y: .value("Remaining", point.remainingPercent),
                                 series: .value("Line", "History \(index)"))
                            .foregroundStyle(Color.primary)
                            .lineStyle(StrokeStyle(lineWidth: 1.5))
                            .accessibilityLabel("History, \(dateText(point.date, model: model))")
                            .accessibilityValue(valueText(point.remainingPercent, model: model))
                    }
                }
                ForEach(model.projection, id: \.date) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Remaining", point.remainingPercent),
                             series: .value("Line", "Projection"))
                        .foregroundStyle(Color.primary)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                        .accessibilityLabel("Projection, \(dateText(point.date, model: model))")
                        .accessibilityValue(valueText(point.remainingPercent, model: model))
                }
                RuleMark(x: .value("Now", model.now))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .center, spacing: 2) {
                        Text("Now").font(.system(size: 10)).foregroundStyle(Color.primary)
                    }
            }
            .chartXScale(domain: model.start...model.end)
            .chartYScale(domain: 0...max(100, model.capacityPercent))
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: 0, through: max(100, model.capacityPercent), by: 100))) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let percent = value.as(Double.self) { Text("\(Int(percent))%") }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                    AxisGridLine()
                    AxisTick()
                    AxisValueLabel(format: model.end.timeIntervalSince(model.start) > 2 * 86_400
                                   ? .dateTime.weekday(.abbreviated) : .dateTime.hour())
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(model.accessibilityLabel)
            .transaction { $0.animation = nil }
            .padding(.top, 14)
        } else {
            Color.clear
        }
    }

    private func dateText(_ date: Date, model: HomeForecastChartModel) -> String {
        HomeInterfaceFormatting.scheduleText(date, now: model.now, calendar: .current)
    }

    private func valueText(_ remaining: Double, model: HomeForecastChartModel) -> String {
        "\(RemainingPercentText.format(remaining)) of \(Int(model.capacityPercent))% left"
    }
}
