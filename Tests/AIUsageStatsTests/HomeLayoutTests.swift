import AppKit
import Testing
@testable import AIUsageStats

/// Home content at the minimum window width beside a 260 pt sidebar: every account row and column is
/// visible without a nested vertical scroller or horizontal scrolling.
@Test @MainActor
func homeTableShowsEveryRowAndColumnAtTheMinimumWidth() async throws {
    _ = NSApplication.shared
    let model = ApplicationModel(isDemo: true)
    await model.load()
    let home = HomeViewController(model: model)
    home.isAccountLoadComplete = { true }
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
                          styleMask: [.titled, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    window.contentView = home.view
    home.render()
    window.contentView?.layoutSubtreeIfNeeded()
    var pending: [NSView] = [home.view]
    var found: NSTableView?
    while let view = pending.popLast() {
        if let table = view as? NSTableView, table.accessibilityLabel() == "Account usage" { found = table; break }
        pending.append(contentsOf: view.subviews)
    }
    let table = try #require(found)
    let clip = try #require(table.enclosingScrollView?.contentView)
    #expect(table.numberOfRows == model.profiles.count)
    let columnExtent = table.rect(ofColumn: table.numberOfColumns - 1).maxX
    #expect(columnExtent <= clip.bounds.width + 1)
    #expect(table.frame.height <= clip.bounds.height + 0.5)
    #expect(table.tableColumns.allSatisfy { $0.width >= $0.minWidth })
    #expect(home.toolbarItemIdentifiers.contains(.homeRefreshAll))
    #expect(!home.windowSubtitle.isEmpty)
}
