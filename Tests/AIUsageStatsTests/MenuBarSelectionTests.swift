import Foundation
import Testing
@testable import AIUsageStats

/// The menu bar shows the lowest quota per provider until accounts are chosen; each chosen account then gets
/// its own number. Demo models keep the choice in memory only, so these tests leave user defaults untouched.
@MainActor
@Test func menuBarChoiceMovesBetweenProviderLowestAndChosenAccounts() {
    let model = ApplicationModel(isDemo: true)
    let first = UUID(), second = UUID(), third = UUID()
    #expect(model.menuBarAccountIDs == nil)
    #expect(!model.showsInMenuBar(first))

    model.setShowsInMenuBar(true, for: first)
    model.setShowsInMenuBar(true, for: second)
    model.setShowsInMenuBar(true, for: third)
    #expect(model.menuBarAccountIDs == [first, second, third])

    model.setShowsInMenuBar(false, for: second)
    #expect(model.menuBarAccountIDs == [first, third])

    model.showLowestPerProviderInMenuBar()
    #expect(model.menuBarAccountIDs == nil)
}
