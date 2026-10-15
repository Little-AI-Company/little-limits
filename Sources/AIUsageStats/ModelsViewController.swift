import AppKit
import Observation
import SwiftUI
import UsageHistory
import UsageHistoryStore

/// What the Models page shows. Replaced only when the report changes, so an unchanged reload does not redraw.
@MainActor @Observable
final class ModelsPageState {
    enum Content: Equatable {
        case loading
        case unavailable(String)
        case loaded(ModelMetricsReport)
    }

    var content = Content.loading
}

/// The Models page: per-model behavior metrics from the local usage history, hosted in the AppKit window.
@MainActor
final class ModelsViewController: NSViewController, WindowToolbarContributor {
    private let model: ApplicationModel
    private let state = ModelsPageState()
    private var demoDatabase: HistoryDatabase?
    private var isLoading = false
    private var reloadsAgain = false
    var onToolbarStateChange: (() -> Void)?

    init(model: ApplicationModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = NSHostingView(rootView: ModelsView(state: state))
    }

    let toolbarItemIdentifiers: [NSToolbarItem.Identifier] = []
    func makeToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem? { nil }

    var windowSubtitle: String {
        guard case let .loaded(report) = state.content, let first = report.firstResponseAt,
              let last = report.lastResponseAt else { return model.isDemo ? "Demo data" : "" }
        let range = "\(first.formatted(date: .abbreviated, time: .omitted)) to \(last.formatted(date: .abbreviated, time: .omitted))"
        return model.isDemo ? "Demo data · \(range)" : range
    }

    /// Reads the report off the main thread. A reload requested while one runs starts once that one finishes.
    func reload() {
        guard !isLoading else { reloadsAgain = true; return }
        isLoading = true
        Task {
            let content = await readContent()
            if state.content != content {
                state.content = content
                onToolbarStateChange?()
            }
            isLoading = false
            if reloadsAgain {
                reloadsAgain = false
                reload()
            }
        }
    }

    private func readContent() async -> ModelsPageState.Content {
        do {
            guard let database = try await database() else {
                return .unavailable(model.historyDatabaseError ?? "Model history is not available.")
            }
            return .loaded(try await database.modelMetrics())
        } catch {
            return .unavailable("Could not read model history: \(error.localizedDescription)")
        }
    }

    /// Demo mode reads fictional rows from a temporary database, never the user's history.
    private func database() async throws -> HistoryDatabase? {
        guard model.isDemo else { return model.historyDatabase }
        if let demoDatabase { return demoDatabase }
        let created = try await Task.detached(priority: .userInitiated) { try ModelsDemoHistory.makeDatabase() }.value
        demoDatabase = created
        return created
    }
}

@MainActor
final class ModelsSidebarCellView: NSTableCellView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let image = NSImageView()
        image.image = NSImage(systemSymbolName: "chart.bar.xaxis", accessibilityDescription: nil)
        image.imageScaling = .scaleProportionallyDown
        image.setAccessibilityElement(false)
        let label = NSTextField(labelWithString: "Models")
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
        setAccessibilityLabel("Models")
        setAccessibilityHelp("Show how each Claude and Codex model behaves, from local logs.")
    }

    required init?(coder: NSCoder) { nil }
}
