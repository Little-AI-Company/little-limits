import AppKit

@MainActor
protocol WindowToolbarContributor: AnyObject {
    var toolbarItemIdentifiers: [NSToolbarItem.Identifier] { get }
    func makeToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem?
    var windowSubtitle: String { get }
    var onToolbarStateChange: (() -> Void)? { get set }
}

@MainActor
@objc protocol WindowCommandHandling {
    @objc optional func showPreviousPeriod(_ sender: Any?)
    @objc optional func showNextPeriod(_ sender: Any?)
    @objc optional func showCurrentPeriod(_ sender: Any?)
    @objc optional func showMonthPeriod(_ sender: Any?)
    @objc optional func showTwoWeekPeriod(_ sender: Any?)
    @objc optional func chooseAccountSortOrder(_ sender: Any?)
    @objc optional func refreshAllAccounts(_ sender: Any?)
    @objc optional func addAccount(_ sender: Any?)
    @objc optional func reconnectSelectedAccount(_ sender: Any?)
    @objc optional func refreshSelectedAccount(_ sender: Any?)
    @objc optional func openSelectedAccountBilling(_ sender: Any?)
    @objc optional func removeSelectedAccount(_ sender: Any?)
    @objc optional func moveSelectedAccountUp(_ sender: Any?)
    @objc optional func moveSelectedAccountDown(_ sender: Any?)
}
