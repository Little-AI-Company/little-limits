# First-run flyout review

Reviewed October 9, 2026 against baseline commit `729ce41`. This is a fresh read-only review of the user-rejected first-run surface. The previous critique remains a record of its narrower layout checks.

## Scope and evidence

Native AppKit macOS menu bar utility, pointer and keyboard input, zero connected accounts. The user-supplied light-appearance screenshot shows the actual first-run flyout: a large app title, a prominent Refresh/Actions control group, an account-setup heading, an explanatory paragraph, two gray connection buttons, substantial blank space, and a refresh footer. The existing [empty-state capture](../../assets/design/after-empty-light.png) documents the same structure.

Source inspected: `UsagePanelController.swift` and `ApplicationDelegate.swift` at the named baseline. The empty content size is 440 × 250 points. The source confirms that the command header and refresh footer remain present with no profiles, and that primary-click opens the popover while secondary-click opens an application menu.

No new runtime interaction or accessibility test was performed during this critic pass. Gray connection buttons look subordinate in the supplied screenshot; their color does not prove they are disabled. No full HIG-compliance or measured-contrast claim is made.

## Findings

### F01 · High · A command-only first run is presented as a small dashboard

**Observed:** The app devotes a wide, tall flyout to two setup commands. The title and empty space make it look like a dashboard without content. A person has to scan a presentation layer before choosing the only useful task.

**Source:** `UsagePanelController.desiredSize` reserves 440 × 250 points for the empty state. `ApplicationDelegate.togglePanel` uses the same popover path before any account exists. A native application menu already exists for secondary-click.

**Correction:** Use a standard `NSMenu` for primary-click while the account list is empty. Put the provider connection commands directly in that menu. Let native menu rendering, selection, keyboard navigation, sizing, and dismissal supply the interaction. Keep a data-rich account panel for the state in which account readings exist. This is a product recommendation, not an Apple prohibition on empty popovers: Apple describes [menus](https://developer.apple.com/design/human-interface-guidelines/menus) as a familiar, space-efficient way to present commands, and [popovers](https://developer.apple.com/design/human-interface-guidelines/popovers) as focused temporary information/functionality.

**Observable acceptance:** On a fresh launch with zero accounts, ordinary click opens a compact native menu with connection commands immediately visible. There is no app-title banner, glass command enclosure, wide blank canvas, or scroll region. After the first account is saved, ordinary click opens the usage panel.

### F02 · High · Irrelevant controls are more prominent than setup, and real commands are hidden

**Observed:** Refresh is disabled but remains inside the most visually distinct header control group. Actions is visible while the actual commands behind it are hidden. The footer describes automatic refresh even though there is no account to refresh. Setup is below all of this.

**Source:** `loadView` always constructs Refresh and Actions. `render` disables Refresh when profiles are empty but still writes Automatic refresh every 5 minutes. `configureActions` hides Accounts, Settings, and Quit behind the generic Actions label.

**Correction:** Remove Refresh and refresh scheduling copy from the zero-account surface. Present the commands by name, with setup first and Settings/Quit in a separate menu group. Do not make a user open Actions to find those commands. Refresh belongs in the populated-data context where it can do something useful. [Apple's menu organization guidance](https://developer.apple.com/design/human-interface-guidelines/menus) supports ordering the important actions first, grouping related commands, and keeping labels clear.

**Observable acceptance:** Zero-account primary-click shows Connect Claude Code…, Connect Codex…, a separator, Settings…, and Quit AI Usage Stats. No Refresh item or refresh footer appears. Each command opens its existing native destination directly, and the menu closes before a setup or settings window opens. Cancellation leaves the account list unchanged.

### F03 · Medium · First-run explanation asks people to understand implementation before choosing an account

**Observed:** “quota reporting” and “Each account keeps a separate profile” describe implementation. Neither is needed to choose Claude or Codex. The paragraph, large heading, and large app title create three reading levels for a two-command decision. The connection buttons look less prominent than the header group.

**Source:** `rebuildAccountList` places the technical explanation in the first-run surface. The existing provider connection dialogs already explain the actual integration and ask for its required configuration.

**Correction:** Keep the first surface to named commands and, if useful, a single short noninteractive No Accounts Connected state line. Use Connect Claude Code… to name the actual subscription-quota integration; Connect Codex… names the other provider. Explain prerequisites, configuration selection, isolated login, and what happens next in the corresponding setup dialog. Do not imply that arbitrary Claude web accounts can be connected if the implementation requires Claude Code. This applies Apple's [clear menu-label guidance](https://developer.apple.com/design/human-interface-guidelines/menus) without disguising the integration limits.

**Observable acceptance:** A new user can choose a provider without reading a technical paragraph or learning the term profile. The selected setup dialog clearly names the integration, states the required sign-in/configuration, exposes its editable choices, and offers Cancel. No configuration or credential change occurs until the user completes the explicit connection step.

## Recommended first-run structure

```text
No Accounts Connected
Connect Claude Code…
Connect Codex…
────────────────────────
Settings…
Quit AI Usage Stats
```

Use actual `NSMenuItem` instances, native separators, and the existing setup/settings actions. The first state line is optional; it must not become another large heading or a disabled-looking setup action. Preserve the established data-rich panel after accounts exist. A native menu solves the first-run task more directly than reducing padding or adding more glass.

## Previous review blind spot

The earlier review verified aligned values, reduced overflow, source attribution, and focus behavior, then accepted the empty-state prompt because its text and buttons were present. It did not adequately judge whether the presentation matched the first-run task or whether chrome and irrelevant controls dominated that task. The statement that no major design issue remained was too broad for the checks performed. This review corrects that scope with a separate first-run finding set; passing the prior density checks does not resolve F01 through F03.

## Verification after implementation

Check the actual packaged app with zero accounts through its ordinary status-item click. Confirm command ordering, provider-dialog selection, menu dismissal by Escape and outside click, arrow-key/Return activation, and cancellation without writes. Then verify that a populated or fictional demo account list still opens its usage panel and retains the separate quota, credit, reset, and expiry semantics. Report VoiceOver, real sign-in, and unsupported runtime environments as untested unless they are directly exercised.

## October 10 implementation outcomes

The initial F01 through F03 findings above are preserved. The revised component paths were inspected independently in the captures below; interaction results were supplied by the implementation verifier.

### Evidence

- [Baseline first-run popover](../../assets/design/flyout-before.png): the actual `729ce41` popover. It confirms the title banner, prominent Refresh/Actions enclosure, technical explanation, broad empty area, and refresh footer described in the initial findings.
- [Native menu validation](../../assets/design/flyout-menu-validation.png): the same real `NSMenu` component used by the revised empty-account path, opened from a clearly labeled validation host. Its menu entries are Add Claude Account…, Add Codex Account…, Accounts…, Settings…, and Quit AI Usage Stats, with a separator between setup and application commands. The menu has no separate Refresh, generic Actions item, banner, explanatory paragraph, or footer. Controls visible behind the menu belong to the validation host and are not part of the first-run menu.
- [Configured account popover](../../assets/design/flyout-configured-validation.png): a real populated `NSPopover` with a disposable local Claude profile and no credentials. It exposes Refresh, Accounts…, Settings…, and Quit directly, without the previous special glass command enclosure. Missing quota and API balances remain explicitly Unavailable rather than fabricated.

### Finding outcomes

| ID | Outcome | Evidence and limits |
| --- | --- | --- |
| F01 | Implemented and observed in the native component paths | The empty-account command surface is now a compact standard menu. The populated popover remains available after adding a disposable local profile. The validation host establishes the actual menu component and its contents; normal status-item anchoring was not visually verified. |
| F02 | Implemented and observed | The empty menu exposes named commands directly and contains no Refresh, Actions layer, or refresh footer. The configured popover also exposes Accounts, Settings, and Quit directly. Arrow-key/Return selection of Codex and pointer selection of Claude reached the correct native setup dialogs in verifier checks. |
| F03 | Implemented and observed for the provider-choice task | Technical quota/profile explanation is removed from the first-run menu. Add Claude Account… and Add Codex Account… make the provider choice explicit; the final wording is simpler than the initial proposed integration-specific labels. The verifier confirmed routing to the correct provider dialogs and canceled both without authentication or persisted account changes. Completed sign-in and the full dialog explanation were not independently reviewed in these captures. |

The verifier used native Arrow Down and Return to select Codex and a pointer action to select Claude. Both dialogs were canceled without authentication or writes. A separate disposable Claude configuration started as an empty local configuration with no credentials; its profile was added solely to exercise the configured-account presentation. The profile was removed through the app, the account table was verified empty, and the temporary configuration settings were verified restored. These are reported runtime observations, distinct from the screenshot inspection.

F01 through F03 are resolved for the implemented and observed component paths. The available evidence does not establish ordinary status-item anchoring: the menu-only app exposed no inspectable accessibility window to the automation tool, so the menu was checked through the labeled validation host. The configured capture shows the real populated popover component, but does not independently prove its normal status-item entry or anchor. Live authentication, real provider readings, VoiceOver, and full HIG compliance remain unverified. The earlier review blind spot remains recorded above.
