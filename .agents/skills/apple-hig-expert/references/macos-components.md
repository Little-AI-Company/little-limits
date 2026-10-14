# macOS component guidance

Live HIG pages reviewed October 14, 2026 against [What's new in design](https://developer.apple.com/design/whats-new/). Nothing relevant was published after October 13. The June 8, 2026 updates to Menus, Sidebars, Scroll views, and Design principles and the March 24, 2026 Sheets update apply to this app. Rules below are short paraphrases for checking a crit; the linked page owns the exact wording. Where the app makes a deliberate local choice, `docs/NATIVE-DESIGN.md` records it and a crit reports the difference instead of silently overriding it.

## Window chrome

- **Sidebars** ([source](https://developer.apple.com/design/human-interface-guidelines/sidebars)): on macOS 26 and later the sidebar floats in the Liquid Glass layer above content. Do not paint a solid background behind it. Row height follows the person's sidebar size setting in General settings. Sidebar symbols use the accent color unless a fixed color carries meaning. Do not hide the sidebar by default; offer show and hide commands. Do not put critical items at the bottom of the sidebar.
- **Toolbars** ([source](https://developer.apple.com/design/human-interface-guidelines/toolbars)): about three groups at most, organized by function and frequency, with navigation separate from actions. Toolbar items have no bezel. Every toolbar item also exists as a menu bar command. Use the prominent style for at most one key action, on the trailing side. Avoid custom toolbar backgrounds and tints; rely on the scroll edge effect. Window titles should not repeat the app name and should stay short.
- **Scroll views** ([source](https://developer.apple.com/design/human-interface-guidelines/scroll-views)): use a scroll edge effect only where a scroll view passes under floating controls such as a toolbar or pinned table header. Prefer the automatic style. One effect per edge.
- **Windows and layout** ([windows](https://developer.apple.com/design/human-interface-guidelines/windows), [layout](https://developer.apple.com/design/human-interface-guidelines/layout)): use system window appearance. Keep bottom bars small and keep critical content and controls away from the window bottom. Do not place solid or semi-opaque backgrounds behind Liquid Glass controls.
- **Settings** ([source](https://developer.apple.com/design/human-interface-guidelines/settings)): Settings lives in the app menu with Command-comma. Apple describes a separate settings window with a pane-switching toolbar, a title that matches the pane, dimmed minimize and zoom, and reopening on the last pane. This app deliberately hosts App Settings inside the management window; a crit evaluates whether that choice costs discoverability rather than reporting it as an automatic failure.

## Controls and presentations

- **Buttons** ([source](https://developer.apple.com/design/human-interface-guidelines/buttons)): add an ellipsis when a push button opens another window, sheet, or view that needs input. Use one or two prominent buttons per view. Square add and remove buttons belong inside or directly under the list they affect, not in the toolbar. Image buttons need about 10 points of padding.
- **Menus** ([source](https://developer.apple.com/design/human-interface-guidelines/menus)): verb-first, title-case labels without articles. Ellipsis when more input follows. Icons only on key actions, and either every item in a group has one or none does. Show keyboard shortcuts. One submenu level with about five items or fewer.
- **Sheets** ([source](https://developer.apple.com/design/human-interface-guidelines/sheets)): modal and attached to the parent window, one at a time. Pair Done with Cancel, or use Back in a multi-step flow; do not show all three together.
- **Alerts** ([source](https://developer.apple.com/design/human-interface-guidelines/alerts)): default button trailing, Cancel leading, Cancel never default. Avoid OK except for purely informational alerts, and avoid Yes and No. Use the destructive style only for an action the person did not deliberately choose.
- **Popovers** ([source](https://developer.apple.com/design/human-interface-guidelines/popovers)): one at a time; use an alert, not a popover, for warnings.

## Data display

- **Charts and calendars** ([source](https://developer.apple.com/design/human-interface-guidelines/charts)): give each mark a full-value accessibility label with its date, not a subjective word. Do not rely on color alone; separate adjacent marks. Use a fixed 0 to 100 percent range for usage. Do not hide critical information behind hover or click.
- **Typography** ([source](https://developer.apple.com/design/human-interface-guidelines/typography)): macOS text styles are Body 13, Callout 12, Subheadline 11, Footnote and Caption 10, Title 3 15, Title 2 17 points. macOS has no Dynamic Type.
- **Color** ([source](https://developer.apple.com/design/human-interface-guidelines/color)): semantic system colors with light, dark, and increased-contrast variants. Do not convey state by color alone. Do not tint the backgrounds of several controls.

## Writing

([source](https://developer.apple.com/design/human-interface-guidelines/writing)) Start action labels with a verb. Use one capitalization style per element type. Use "your" sparingly and avoid "we". Error text says what happened and how to fix it. Describe what a setting does when it is on.

## Menu bar extra

([source](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar)) The menu bar is 24 points tall; use template images. Do not depend on the extra being visible or in a fixed position, because the system may hide it when space runs out. Make the same functions reachable elsewhere, for example from the app's window or Dock menu.

## Not verified

The reviewed pages give no checkable macOS rule for concentric corner radii, window corner changes, or macOS 26 and 27 control size tiers. Do not report those as HIG failures without a newer source.
