import SwiftUI
import UsageHistory
import UsageHistoryStore

struct ModelsView: View {
    let state: ModelsPageState

    var body: some View {
        switch state.content {
        case .loading:
            message("Reading model history…")
        case let .unavailable(text):
            message(text)
        case let .loaded(report) where report.isEmpty:
            message("No model history yet. Models appear here after Claude Code or Codex logs are read.")
        case let .loaded(report):
            ModelsReportView(report: report)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ModelsReportView: View {
    let report: ModelMetricsReport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                if report.models.contains(where: \.isSmallSample) {
                    Text("Models marked under \(ModelMetrics.reliableResponseCount.formatted()) have fewer requests than that, so their numbers are noisy.")
                }
                ForEach(HistoryProvider.allCases, id: \.self) { provider in
                    let models = report.models.filter { $0.provider == provider }
                    if !models.isEmpty { ProviderSection(provider: provider, models: models) }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ProviderSection: View {
    let provider: HistoryProvider
    let models: [ModelMetrics]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(MetricDefinition.providerName(provider))
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 32, alignment: .top)],
                      alignment: .leading, spacing: 22) {
                ForEach(MetricDefinition.all(for: provider)) { metric in
                    MetricBlock(metric: metric, models: models)
                }
            }
            PurposeBlock(models: models)
        }
    }
}

private struct MetricBlock: View {
    let metric: MetricDefinition
    let models: [ModelMetrics]

    var body: some View {
        let readings = models.map { metric.reading($0) }
        let largest = readings.compactMap { $0?.value }.max() ?? 0
        VStack(alignment: .leading, spacing: 6) {
            Text(metric.title).font(.headline).accessibilityAddTraits(.isHeader)
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 5) {
                ForEach(Array(zip(models, readings)), id: \.0.id) { model, reading in
                    let fraction = reading.map { metric.isShare ? $0.value : largest > 0 ? $0.value / largest : 0 }
                    GridRow {
                        ModelNameText(model: model)
                        MetricBar(fraction: fraction)
                        Text(reading?.text ?? metric.emptyText).monospacedDigit().fixedSize().gridColumnAlignment(.trailing)
                        Text(reading?.detail ?? "").monospacedDigit().foregroundStyle(.secondary).fixedSize()
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(InterfaceFormatting.modelDisplayName(model.model))
                    .accessibilityValue(accessibilityValue(model: model, reading: reading) + ". Model identifier \(model.model)")
                    .help("\(model.model). \(accessibilityValue(model: model, reading: reading))")
                }
            }
            .font(.callout)
            if let footnote = metric.footnote {
                Text(footnote).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func accessibilityValue(model: ModelMetrics, reading: MetricReading?) -> String {
        var parts = [reading.map { [$0.text, $0.spokenDetail].filter { !$0.isEmpty }.joined(separator: ", ") } ?? metric.emptyText]
        if model.isSmallSample {
            parts.append("Fewer than \(ModelMetrics.reliableResponseCount.formatted()) requests, noisy")
        }
        return parts.joined(separator: ". ")
    }
}

private struct ModelNameText: View {
    let model: ModelMetrics

    var body: some View {
        let name = InterfaceFormatting.modelDisplayName(model.model)
        Text(model.isSmallSample ? "\(name) (under \(ModelMetrics.reliableResponseCount.formatted()))" : name).fixedSize()
    }
}

private struct MetricBar: View {
    let fraction: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Rectangle().fill(.quaternary)
                if let fraction {
                    Rectangle().fill(Color.primary).frame(width: proxy.size.width * min(max(fraction, 0), 1))
                }
            }
        }
        .frame(minWidth: 40, maxWidth: .infinity, minHeight: 8, maxHeight: 8)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

private struct PurposeBlock: View {
    let models: [ModelMetrics]
    private static let purposes: [(InlineScriptPurpose, String, Color)] = [
        (.editsFileInPlace, "Edits a file in place", .blue),
        (.writesFile, "Writes a new file", .teal),
        (.readsJSON, "Reads JSON", .orange),
        (.other, "Other", .gray)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("What the inline Python does").font(.headline).accessibilityAddTraits(.isHeader)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 5) {
                GridRow {
                    Text("Model")
                    Color.clear.frame(height: 1).gridCellUnsizedAxes(.vertical)
                    ForEach(Self.purposes, id: \.0) { _, title, color in
                        HStack(spacing: 4) {
                            Rectangle().fill(color).frame(width: 8, height: 8).accessibilityHidden(true)
                            Text(title)
                        }
                        .gridColumnAlignment(.trailing)
                    }
                    Text("Scripts").gridColumnAlignment(.trailing)
                }
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
                ForEach(models) { model in
                    let total = model.inlinePythonPurposes.values.reduce(0, +)
                    GridRow {
                        ModelNameText(model: model)
                        stackedBar(model.inlinePythonPurposes, total: total)
                        ForEach(Self.purposes, id: \.0) { purpose, _, _ in
                            Text(share(model.inlinePythonPurposes[purpose] ?? 0, of: total)).monospacedDigit()
                        }
                        Text(total.formatted()).monospacedDigit()
                    }
                    .help(model.model)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(InterfaceFormatting.modelDisplayName(model.model))
                    .accessibilityValue(accessibilityValue(model, total: total) + ". Model identifier \(model.model)")
                }
            }
            .font(.callout)
            Text("Groups come from ordered keyword rules on the script. Shares of inline Python scripts with a known purpose.")
                .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stackedBar(_ counts: [InlineScriptPurpose: Int], total: Int) -> some View {
        GeometryReader { proxy in
            HStack(spacing: 1) {
                if total > 0 {
                    ForEach(Self.purposes, id: \.0) { purpose, _, color in
                        let count = counts[purpose] ?? 0
                        if count > 0 {
                            Rectangle().fill(color)
                                .frame(width: max(0, proxy.size.width * Double(count) / Double(total) - 1))
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary)
        }
        .frame(minWidth: 80, maxWidth: .infinity, minHeight: 8, maxHeight: 8)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private func share(_ count: Int, of total: Int) -> String {
        total > 0 ? (Double(count) / Double(total)).formatted(.percent.precision(.fractionLength(0))) : "No data"
    }

    private func accessibilityValue(_ model: ModelMetrics, total: Int) -> String {
        guard total > 0 else { return "No inline Python" }
        var parts = Self.purposes.map { purpose, title, _ in
            "\(title) \(share(model.inlinePythonPurposes[purpose] ?? 0, of: total))"
        }
        parts.append("\(total.formatted()) scripts")
        if model.isSmallSample {
            parts.append("Fewer than \(ModelMetrics.reliableResponseCount.formatted()) requests, noisy")
        }
        return parts.joined(separator: ", ")
    }
}

private struct MetricReading {
    let value: Double
    let text: String
    let detail: String
    var spokenDetail: String { unit.isEmpty ? detail : "\(detail) \(unit)" }
    var unit = ""
}

private struct MetricDefinition: Identifiable {
    let title: String
    let footnote: String?
    let isShare: Bool
    let emptyText: String
    let reading: (ModelMetrics) -> MetricReading?
    var id: String { title }

    static func providerName(_ provider: HistoryProvider) -> String {
        switch provider {
        case .claude: "Claude"
        case .codex: "Codex"
        }
    }

    static func all(for provider: HistoryProvider) -> [MetricDefinition] {
        [
            MetricDefinition(title: "Requests", footnote: nil, isShare: false, emptyText: "0") { model in
                MetricReading(value: Double(model.responseCount), text: model.responseCount.formatted(), detail: "")
            },
            MetricDefinition(
                title: "Output speed, tok/s (approximate)",
                footnote: "Median output tokens, thinking included, per second from the prompt or tool result to the response's last log line. Includes the wait before the first token, so compare within one provider.",
                isShare: false, emptyText: "No data") { model in
                model.outputSpeed.map {
                    MetricReading(value: $0.median, text: $0.median.formatted(.number.precision(.fractionLength(0))),
                                  detail: "\($0.sampleCount.formatted()) responses")
                }
            },
            MetricDefinition(
                title: "Steps per turn",
                footnote: "Mean model calls before the agent stops and replies, in sessions with tool use.",
                isShare: false, emptyText: "No data") { model in
                model.stepsPerTurn.map {
                    MetricReading(value: $0.mean, text: $0.mean.formatted(.number.precision(.fractionLength(1))),
                                  detail: "\($0.sampleCount.formatted()) turns")
                }
            },
            share(title: "Thinking share of output tokens", footnote: "Responses with a known final token count only.",
                  unit: "tokens", compact: true) { $0.thinkingTokens },
            share(title: "Responses with parallel tool calls",
                  footnote: provider == .codex ? "Also counts one exec call that runs two or more commands."
                      : "Two or more tool calls in one response.",
                  unit: "responses") { $0.parallelToolCallResponses },
            share(title: "Uses grep instead of rg",
                  footnote: provider == .claude ? "Shell searches only. The Grep tool is not counted." : "Shell searches only.",
                  unit: "searches") { $0.grepSearches },
            share(title: "Commands piped into head or tail", footnote: nil, unit: "commands") { $0.headOrTailPipes },
            MetricDefinition(title: "git status runs per commit", footnote: "Successful commits only.", isShare: false,
                             emptyText: "No commits") { model in
                model.gitStatusPerCommit.value.map {
                    MetricReading(value: $0, text: $0.formatted(.number.precision(.fractionLength(1))),
                                  detail: "\(model.gitStatusPerCommit.count.formatted()) runs, \(model.gitStatusPerCommit.total.formatted()) commits")
                }
            },
            MetricDefinition(title: "Mean shell command length, chars", footnote: "Heredocs raise the mean.",
                             isShare: false, emptyText: "No data") { model in
                model.commandLength.map {
                    MetricReading(value: $0.mean, text: $0.mean.formatted(.number.precision(.fractionLength(0))),
                                  detail: "median \($0.median.formatted(.number.precision(.fractionLength(0))))")
                }
            },
            MetricDefinition(
                title: "Commands running inline code",
                footnote: provider == .codex
                    ? "Inline Python or JavaScript. Each command inside a code-mode script counts as one shell command."
                    : "Inline Python or JavaScript, such as a heredoc into python3 or node -e.",
                isShare: true, emptyText: "No data") { model in
                model.inlineCode.value.map {
                    MetricReading(value: $0, text: percent($0),
                                  detail: "Python \(percent(model.inlinePython.value ?? 0)), JS \(percent(model.inlineJavaScript.value ?? 0))")
                }
            },
            share(title: "Saved script runs", footnote: "Running a saved script file. Not counted as inline code.",
                  unit: "commands") { $0.savedScriptRuns },
            share(title: "Inline code outside the busiest project",
                  footnote: "Inline code share of commands outside the project where this model runs the most commands. Project names are not stored.",
                  unit: "commands") { $0.inlineOutsideBusiestProject },
            MetricDefinition(title: "Inline script length, lines", footnote: "Median, with the 90th percentile beside it.",
                             isShare: false, emptyText: "No data") { model in
                model.inlineScriptLines.map {
                    MetricReading(value: $0.median, text: $0.median.formatted(.number.precision(.fractionLength(0))),
                                  detail: "p90 \($0.percentile90.formatted(.number.precision(.fractionLength(0))))")
                }
            }
        ]
    }

    private static func share(title: String, footnote: String?, unit: String, compact: Bool = false,
                              ratio: @escaping (ModelMetrics) -> MetricRatio) -> MetricDefinition {
        MetricDefinition(title: title, footnote: footnote, isShare: true, emptyText: "No data") { model in
            let ratio = ratio(model)
            func number(_ value: Int) -> String {
                compact ? value.formatted(.number.notation(.compactName)) : value.formatted()
            }
            return ratio.value.map {
                MetricReading(value: $0, text: percent($0), detail: "\(number(ratio.count)) of \(number(ratio.total))", unit: unit)
            }
        }
    }

    private static func percent(_ value: Double) -> String {
        value.formatted(.percent.precision(.fractionLength(1)))
    }
}
