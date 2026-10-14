import AppKit
import Testing
@testable import AIUsageStats

@Test @MainActor
func accountNavigationPreservesTheUserWindowSize() async throws {
    _ = NSApplication.shared
    let model = ApplicationModel(isDemo: true)
    await model.load()
    let controller = AccountsWindowController(model: model)
    controller.isAccountLoadComplete = { true }
    controller.render()
    let window = try #require(controller.window)
    defer { window.close() }
    window.setContentSize(NSSize(width: 1_360, height: 840))
    let originalFrame = window.frame
    let root = try #require(window.contentView)
    var descendants = [root]
    var sidebar: NSTableView?
    while let view = descendants.popLast() {
        if let table = view as? NSTableView, table.accessibilityLabel() == "Sidebar" {
            sidebar = table
            break
        }
        descendants.append(contentsOf: view.subviews)
    }
    let accountList = try #require(sidebar)
    accountList.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
    #expect(window.title.contains("personal@example.invalid"))
    #expect(window.frame == originalFrame)
    controller.showSettings()
    #expect(window.title == "App Settings")
    #expect(window.frame == originalFrame)
    controller.showHome()
    #expect(window.title == "AI Usage Stats")
    #expect(window.frame == originalFrame)
}
