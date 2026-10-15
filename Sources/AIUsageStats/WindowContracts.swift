import AppKit

/// A page in the AI Usage Stats window that places its controls in the window toolbar.
/// The window controller asks the visible page for items after the sidebar tracking
/// separator and shows `windowSubtitle` under the page title.
@MainActor
protocol WindowToolbarContributor: AnyObject {
    var toolbarItemIdentifiers: [NSToolbarItem.Identifier] { get }
    func makeToolbarItem(_ identifier: NSToolbarItem.Identifier) -> NSToolbarItem?
    var windowSubtitle: String { get }
    /// Set by the window controller; the page calls it when its subtitle or item set changes.
    var onToolbarStateChange: (() -> Void)? { get set }
}

/// Main menu commands dispatched through the responder chain with a nil target.
/// The Home page implements the period commands, the window controller implements
/// `addAccount(_:)`, `reconnectSelectedAccount(_:)`, and `removeSelectedAccount(_:)`, `moveSelectedAccountUp(_:)`, and `moveSelectedAccountDown(_:)` for the selected
/// account, the account page implements `openSelectedAccountBilling(_:)` and `refreshSelectedAccount(_:)`, and the application
/// delegate implements `refreshAllAccounts(_:)`.
@MainActor
@objc protocol WindowCommandHandling {
    @objc optional func showPreviousPeriod(_ sender: Any?)
    @objc optional func showNextPeriod(_ sender: Any?)
    @objc optional func showCurrentPeriod(_ sender: Any?)
    @objc optional func showMonthPeriod(_ sender: Any?)
    @objc optional func showTwoWeekPeriod(_ sender: Any?)
    /// View > Sort Accounts; the sender's tag selects the order.
    @objc optional func chooseAccountSortOrder(_ sender: Any?)
    @objc optional func refreshAllAccounts(_ sender: Any?)
    @objc optional func addAccount(_ sender: Any?)
    /// File > Reconnect… for the selected account.
    @objc optional func reconnectSelectedAccount(_ sender: Any?)
    /// File > Refresh Account for the account page's account.
    @objc optional func refreshSelectedAccount(_ sender: Any?)
    /// File > Open Billing for the selected account.
    @objc optional func openSelectedAccountBilling(_ sender: Any?)
    /// File > Delete Account… for the selected account; asks for confirmation.
    @objc optional func removeSelectedAccount(_ sender: Any?)
    /// File > Move Up and Move Down for the selected account.
    @objc optional func moveSelectedAccountUp(_ sender: Any?)
    @objc optional func moveSelectedAccountDown(_ sender: Any?)
}
