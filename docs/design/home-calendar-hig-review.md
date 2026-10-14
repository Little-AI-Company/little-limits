# Home calendar HIG review

The project-specific Apple HIG review supports the two-week calendar with a flat account comparison table. The final mockups address ambiguous account identity, obscured date labels, percentage meaning, repeated table text, and missing freshness and failure examples.

## Scope and evidence

**Expected outcome:** A person can identify the account and quota window for each next reset, compare the latest readings, and recognize unavailable or stale data.

**Reviewed revision:** `0485bbec496a18c32cdecd96e087a586f7c586bf`, with existing uncommitted source, documentation, skill, and design work. The review and this mockup pass do not modify application source.

**Surface:** Generated Home window concept, selected by default. Baseline: [two-week account comparison](../../assets/design/home-calendar-explorations/two-week-account-comparison.png).

**Environment:** Static dark image, reported by the reviewer as 1592 × 994 image pixels. Actual macOS version, SDK, native window dimensions, capture scale, hardware, and display preferences are unknown. The application targets macOS 14. Image dimensions are not AppKit point measurements.

**Inputs:** Proposed pointer, selection, and detail states. Keyboard, VoiceOver, contrast, runtime refresh, and account isolation remain untested.

**Review date:** October 13, 2026. A newly assigned subagent applied [the project Apple HIG skill](../../.agents/skills/apple-hig-expert/SKILL.md), including its project profile, design principles, visual design, accessibility, rubric, and audit template. Relevant live Apple content was checked through Apple documentation JSON where the HTML required JavaScript.

The results below describe the baseline screenshot. The implementation column records changes to image concepts, not verified AppKit behavior or HIG certification.

## Requirement results

| Requirement | Authority | Baseline result | Evidence or limit |
| --- | --- | --- | --- |
| `design.principles.task-purpose` | Apple HIG | Pass within visual scope | Observed: Home, reset calendar, account table, date navigation, and refresh make monitoring understandable |
| `project.readings.identity-units-freshness` | Project | Fail | Observed: calendar events identify only providers, and table rows have no observation time |
| `project.readings.unknown-failure-recovery` | Project | Untested | Observed: some missing and nonapplicable states appear, but stale, sign-in required, and missing readings are absent |
| `appearance.materials.hierarchy` | Apple HIG | Untested | Observed flat content; native material implementation cannot be established from pixels |
| `appearance.color.legibility` | Apple HIG | Untested | Needs device test: actual appearance backgrounds and measured contrast |
| `layout.native-adaptation` | Apple HIG | Untested | Needs device test: compact windows, long identities, enlarged text, and scrolling |
| `accessibility.native-control-size` | Apple HIG | Untested | Needs device test: actual native hit regions and point dimensions |
| `accessibility.name-role-value-state` | Apple HIG | Untested | Needs device test: event and table semantics with VoiceOver |
| `accessibility.keyboard-focus` | Apple HIG | Untested | Needs device test: selection, Return, Escape, tab order, and focus restoration |
| `settings.native-access` | Apple HIG | Untested | Sidebar action observed; app-menu Settings and Command-comma are outside the image |
| `project.window.context-preservation` | Project | Untested | Needs device test: refresh, navigation, sheets, close, and reopen |
| `project.performance.quiet-interface` | Project | Untested | Needs device test: redraw and animation behavior |
| `status-menu.native-presentation` | Apple HIG | N/A | This review concerns the window, not the status menu |
| `project.platform.session-isolation` | Project | N/A | No Platform browser or credential operation is proposed |

## Findings and mockup changes

| Finding | Impact | Baseline observation | Final design correction |
| --- | --- | --- | --- |
| HIG-HOME-01 | High | Provider icons cannot distinguish two accounts from the same provider | Every event includes a short account identity matching the sidebar and table; full fictional email remains in the table and details |
| HIG-HOME-02 | High | The flyout covers second-week date labels | Place a compact flyout beside the selected event; keep all date labels, events, and the table clear |
| HIG-HOME-03 | High | Percentages on future dates can appear to predict capacity after reset | Use Reset calendar and a visible latest-reading and timezone label; retain the named quota scope and only reported next resets |
| HIG-HOME-04 | Medium | Repeated remaining labels, dates, timezones, and countdowns obscure comparison | Use descriptive table headers, aligned percentages, one compact reset line per cell, actual model name, and one Updated time per account |
| HIG-HOME-05 | Medium | The baseline does not show stale, sign-in required, or unknown usage | Add a separate state view with neutral dated history, Reconnect…, and Unknown; keep all accounts listed and omit unconfirmed calendar events |
| HIG-HOME-06 | Medium | Plan, earned-reset count, expiry, and focus meanings need explicit limits | Use optional plan names without invented multipliers; label earned resets as counts with expiry; retain native-looking event selection and View Account |

The reviewer recommended compact, unique event labels in line with Apple's [design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles). The positioning correction follows Apple's [popover guidance](https://developer.apple.com/design/human-interface-guidelines/popovers): preserve the originating item and essential context. Descriptive headings and consistent row values follow [lists and tables guidance](https://developer.apple.com/design/human-interface-guidelines/lists-and-tables).

The final dark flyout opens to the left of the selected Codex event. It temporarily overlaps part of the account sidebar and an empty calendar cell, while preserving every date label, reported event, and comparison-table row. Its arrow stays attached to the selected event. This is a visual placement proposal; the packaged app must verify native placement at different window and screen positions.

The proposed event details must eventually be accessible by click and keyboard as well as hover. A selected-looking image does not establish working keyboard access. See [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility) and [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards).

## Final mockup set

- [Light overview](../../assets/design/home-calendar-final/home-final-light.png): the default Home view, with all reported example resets and a comparison table.
- [Dark view with account details](../../assets/design/home-calendar-final/home-final-dark.png): the same normal data, with a selected event and compact details.
- [Unavailable and stale readings](../../assets/design/home-calendar-final/home-final-reading-states.png): a fresh Claude account, a Claude account requiring sign-in, dated Codex history, and unknown Codex usage.
- [ImageGen prompts](../../assets/design/home-calendar-final/prompts.json): generation prompts and the review changes they implement.

Normal and failure examples use fictional accounts and readings. All percentages describe the last observation. Credit expiry is separate from quota reset. Unknown percentages do not become zero. The actual implementation must adapt to returned model scopes rather than assuming every Claude account has Fable 5.

## Final visual recheck

The same subagent reapplied the project skill to the three saved final images. It found no material unresolved visual defects. These outcomes are limited to the displayed design, with native behavior still untested.

| Finding | Final visual outcome | Evidence |
| --- | --- | --- |
| HIG-HOME-01 | Pass | Account identity and quota scope appear on every normal calendar event; full identity remains in the table and details |
| HIG-HOME-02 | Pass | All 14 dates, all 9 normal events, Home selection, and the full table remain visible; the flyout points directly to the selected event |
| HIG-HOME-03 | Pass | Reset calendar and latest-reading wording distinguish observed readings from future reset instants |
| HIG-HOME-04 | Pass | Light and dark share normal readings and layout; concise values and per-account update times support comparison |
| HIG-HOME-05 | Pass within visual scope | All 4 accounts remain listed; the state view shows only 3 fresh events, neutral history, separate sign-in and unknown states, and Reconnect |
| HIG-HOME-06 | Pass | Plan names have no inferred multipliers; earned-reset expiry remains separate; selected-event details offer View Account without reset consumption |

For implementation, the reviewer suggested changing the stale row's Reported timing label to Last reported reset. This clarifies that the adjacent time belongs to the historical quota reset, while the Updated column supplies the observation time.

Image metadata: light and dark are 1516 × 1038 pixels; the state view is 1515 × 1038 pixels. These are file dimensions, not native window or control measurements.

## Verification and limits

The subagent visually reviewed the baseline, relevant source contracts, and final images; it ran no app builds, provider requests, or native interaction checks. Prompt JSON parsed successfully; all 6 local audit links resolved; all 3 PNG signatures were verified. The 2 text artifacts passed trailing-whitespace and final-newline checks. `git diff --check` passed. The separate `git diff --no-index --check /dev/null` checks returned exit 1 for each new text file with no whitespace diagnostics, reflecting added-file differences.

No runtime compliance, contrast, point sizing, VoiceOver, keyboard, performance, Intel, or minimum-macOS claims are made. Those checks remain for the packaged AppKit implementation. The existing application validation log remains unchanged by this mockup pass.
