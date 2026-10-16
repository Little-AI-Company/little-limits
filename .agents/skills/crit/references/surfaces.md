# Surface inventory

Launch each row as its own instance: `open -n "dist/Limits Left.app" --args <flags>`. Add `--dark-appearance` or `--increase-contrast` for appearance variants. Quit the instance (Command-Q in its window, or `kill <pid>`) before the next row. `--demo-empty` and `--demo-load-error` take effect only together with `--demo`; without it the instance loads the real saved accounts, so always pass `--demo` first. Fixture data is fictional; demo mode disables refresh, reconnect, and account changes, so disabled controls in captures are expected and are not findings by themselves.

| Surface | Flags | Navigation after launch | Capture |
| --- | --- | --- | --- |
| status-item | `--demo-home` | None | The system menu bar process owns this window, so the script cannot capture it. Only when no other Limits Left instance is running, capture the menu bar strip with `screencapture -x -R0,0,<screen width in points>,40 <file>` and crop to the demo item before sharing. Otherwise record `status-menu.template-image` as untested. |
| status-menu | `--demo-home --show-menu` | Menu opens itself | `menu` PNG, or computer-use screenshot |
| status-menu-empty | `--demo --demo-empty --show-menu` | Menu opens itself | First-run menu |
| status-menu-error | `--demo --demo-load-error --show-menu` | Menu opens itself | Load failure menu |
| home | `--demo-home --show-home` | None | Calendar plus account table |
| home-states | `--demo-reading-states --show-home` | None | Sign-in, stale, and missing readings |
| home-popover | `--demo-home --show-home` | Click a calendar event | Account popover |
| home-month | `--demo-home --show-home` | Click Month | Month calendar |
| account | `--demo-home --show-home` | Click the first sidebar account | Account page top |
| account-details | same | Scroll to Connection Details, expand Manual balance | Lower account page |
| account-states | `--demo-reading-states --show-home` | Click the sign-in-required and stale accounts | Failure and stale pages |
| settings | `--demo-home --show-home` | Click the gear below the sidebar, and separately press Command-comma | App Settings |
| add-account | `--demo-home --show-home` | Click plus below the sidebar | Provider choice sheet |
| remove-account | `--demo-home --show-home` | Select an account, click minus | Confirmation |
| platform | `--demo-home --show-home` | Account page, Connect API Credits | Platform pane, if demo allows |
| empty | `--demo --demo-empty --show-home` | None | Empty window |
| error | `--demo --demo-load-error --show-home` | None | Load failure window |
| minimum-size | `--demo-home --show-home` | Drag window to its minimum | Layout at 1020 × 640 points |

Keyboard checks while each window surface is open: Tab order, visible focus, Return on the focused control, Escape on sheets and popovers, Command-comma, Command-W, Command-M.
