import AppKit
import Testing
@testable import AIUsageStats
import UsageCore

@MainActor
private func descendants<View: NSView>(of root: NSView, as type: View.Type) -> [View] {
    var pending = [root]
    var found: [View] = []
    while let view = pending.popLast() {
        if let match = view as? View { found.append(match) }
        pending.append(contentsOf: view.subviews)
    }
    return found
}

@MainActor
private func menuItem(_ action: Selector) -> NSMenuItem {
    NSMenuItem(title: "", action: action, keyEquivalent: "")
}

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
    let toolbarItems = { window.toolbar?.items.map(\.itemIdentifier) ?? [] }
    #expect(window.title == "personal@example.invalid")
    #expect(toolbarItems().contains(NSToolbarItem.Identifier("AccountRefreshAll")))
    #expect(window.frame == originalFrame)
    // File menu account commands: demo accounts cannot be reconnected or removed; Open Billing reaches the account
    // page through the split view controller even while keyboard focus is in the sidebar.
    #expect(!controller.validateMenuItem(menuItem(#selector(WindowCommandHandling.reconnectSelectedAccount(_:)))))
    #expect(!controller.validateMenuItem(menuItem(#selector(WindowCommandHandling.removeSelectedAccount(_:)))))
    let billing = #selector(WindowCommandHandling.openSelectedAccountBilling(_:))
    let billingTarget = window.contentViewController?.supplementalTarget(forAction: billing, sender: nil)
    let accountPage = try #require(billingTarget as? AccountDetailViewController)
    #expect(accountPage.validateMenuItem(menuItem(billing)))
    controller.showSettings()
    #expect(window.title == "Settings")
    #expect(toolbarItems() == [.toggleSidebar, .sidebarTrackingSeparator])
    #expect(window.frame == originalFrame)
    controller.showHome()
    #expect(window.title == "Home")
    #expect(!toolbarItems().contains(NSToolbarItem.Identifier("AccountRefreshAll")))
    #expect(window.frame == originalFrame)
    #expect(window.contentViewController?.supplementalTarget(forAction: billing, sender: nil) == nil)
}

/// Each account identity has line 1 to itself: it is not truncated when it fits the sidebar, and a longer one
/// keeps the whole line instead of yielding to quota text. Line 2 names the limiting window with the state word.
@Test @MainActor
func sidebarRowsGiveTheIdentityItsOwnLineAndNameTheLimitingWindow() async throws {
    _ = NSApplication.shared
    let model = ApplicationModel(isDemo: true)
    await model.load()
    let controller = AccountsWindowController(model: model)
    controller.isAccountLoadComplete = { true }
    controller.render()
    let window = try #require(controller.window)
    defer { window.close() }
    let root = try #require(window.contentView)
    root.layoutSubtreeIfNeeded()
    let rows = descendants(of: root, as: AccountSidebarCellView.self)
    #expect(rows.count == model.profiles.count)
    var quotaLines: Set<String> = []
    for row in rows {
        row.layoutSubtreeIfNeeded()
        let identity = try #require(row.textField)
        let fits = identity.intrinsicContentSize.width <= identity.frame.width + 0.5
        let spansLine = identity.convert(identity.bounds, to: row).maxX >= row.bounds.width - 4.5
        #expect(fits || spansLine, "\(identity.stringValue) yields its line")
        if identity.stringValue == "personal@example.invalid" { #expect(fits) }
        quotaLines.formUnion(descendants(of: row, as: NSTextField.self).filter { $0 !== identity }.map(\.stringValue))
    }
    #expect(quotaLines == ["39% left · Weekly", "18% left, Low · 5-hour", "0% left, Limit reached · 5-hour", "Unavailable"])
}

/// The add-account sheet sizes to its explanation for each provider, so no text or button is clipped.
@Test @MainActor
func addAccountSheetFitsItsContentForEachProvider() throws {
    _ = NSApplication.shared
    let sheet = AddAccountSheetController(provider: .codex)
    let window = try #require(sheet.window)
    let root = try #require(window.contentView)
    let picker = try #require(descendants(of: root, as: NSPopUpButton.self).first)
    for provider in [Provider.codex, .claude] {
        picker.selectItem(withTitle: InterfaceFormatting.provider(provider))
        picker.sendAction(picker.action, to: picker.target)
        root.layoutSubtreeIfNeeded()
        #expect(!root.hasAmbiguousLayout)
        #expect(root.frame.size == root.fittingSize)
        for view in descendants(of: root, as: NSView.self) where view is NSTextField || view is NSButton {
            let frame = view.convert(view.bounds, to: root)
            #expect(root.bounds.contains(frame), "\(view) is clipped")
            if let label = view as? NSTextField, label.cell?.wraps == true {
                #expect(label.intrinsicContentSize.height <= label.frame.height + 0.5, "\(label.stringValue) is clipped")
            }
        }
    }
}
