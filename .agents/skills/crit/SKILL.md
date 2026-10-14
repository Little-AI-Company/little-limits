---
name: crit
description: Run a screenshot-backed design critique of the running AI Usage Stats app. Combines Krug's "Don't Make Me Think" and Nielsen heuristics (ux-heuristics) with current Apple macOS HIG and Liquid Glass guidance (apple-hig-expert) into one ranked finding register and report. Use when asked for a design crit, UX review, UI audit, or "the UI is rough, review it". Assessment only unless the user grants implementation.
metadata:
  adapted-from: little-worker .agents/skills/crit (2026-10-14), rewritten for native AppKit capture
---

# Crit

A crit answers one question per surface: can someone glance at this and know how much Claude and Codex quota is left, on which account, and what to do next, without thinking? Evidence comes from the packaged app, not from source alone.

Read `AGENTS.md`, `docs/STRATEGY.md`, and `docs/NATIVE-DESIGN.md` first. Then read the [ux-heuristics skill](../ux-heuristics/SKILL.md) and the [apple-hig-expert skill](../apple-hig-expert/SKILL.md) with its [macOS component guidance](../apple-hig-expert/references/macos-components.md). Those skills own their assessments. This skill owns capture, the finding register, and the report.

`NATIVE-DESIGN.md` records the current design. It is not a defense: a crit may find that a documented decision fails the user. Report that as a finding with the doctrine quoted, so the owner can decide whether to change the doctrine.

## Scope and authority

- A request to crit, audit, or review authorizes assessment only. Make no product changes unless the user grants implementation for this crit.
- Use demo fixtures only. Never capture the user's real instance, real emails, or credentials. Leave any already running instance alone; `capture_windows.swift` filters by process ID for this reason.
- Keep captures and working files under ignored `.crit/<review-id>/`. Commit only the text report under `docs/design/crits/`.

## 1. Capture

1. Package once with `scripts/package_app.sh`. Record the commit and whether the tree is clean.
2. Launch each fixture as its own instance with `open -n "dist/AI Usage Stats.app" --args <flags>`, find its PID with `pgrep -nf "AIUsageStats <first flag>"`, and quit it before the next fixture. The [surface inventory](references/surfaces.md) lists fixtures, flags, and navigation steps.
3. Capture windows with `swift .agents/skills/crit/scripts/capture_windows.swift .crit/<review-id>/captures <appearance>-<surface> <pid>`. It first removes earlier files with that prefix, then writes one PNG per app-owned window (window, menu, sheet, popover) plus a JSON manifest with frames in points and backing scale. Divide pixel measurements by `backingScale` to get points.
4. Navigation inside the window (sidebar rows, gear, plus, minus, disclosures, popovers) needs a pointer. The shell is not an Accessibility client, so drive the app with the computer-use tools, then capture with the script. A computer-use screenshot is acceptable evidence when the script cannot reach a transient surface such as an open menu.
5. Capture light and dark (`--dark-appearance`). Capture `--increase-contrast` for the main surfaces. Resize to the 1020 × 640 point minimum once. A surface that could not be captured is listed as untested, never inferred.
6. Exercise keyboard paths while capturing: Tab through Home and an account page, arrow and Return in the status menu, Escape on every sheet and popover, Command-comma, Command-W. Record what focus did. VoiceOver output is untested unless actually run.

## 2. Assess

Run the two audits independently, then merge. When delegating, give each reviewer the captures, the manifest, the doctrine files, and only its own skill. Suggested models: Opus for the UX and HIG audits, Sonnet for the source cross-check, Haiku for the copy scan.

- **UX audit** (ux-heuristics): per surface, the Trunk Test and Quick Diagnostic, then Nielsen findings rated 0 to 4 by frequency, impact, and persistence. Ask "where would a first-time user hesitate?" for each surface.
- **HIG audit** (apple-hig-expert): one outcome per rubric requirement, `pass`, `fail`, `untested`, or `na` with a reason. Measure control sizes and text in points from captures. Do not report unmeasured contrast as a pass.
- **Source cross-check**: confirm each candidate finding against the Swift source (file and line), and find what captures cannot show: accessibility labels, keyboard equivalents, hard-coded colors or sizes, custom drawing that ignores display preferences.
- **Copy scan**: every visible string checked against [Writing](https://developer.apple.com/design/human-interface-guidelines/writing), the project's no em dash rule, ellipsis rules, capitalization consistency, and one term per concept.

Drop any candidate that is speculation, a taste disagreement without a heuristic or HIG rule behind it, or contradicted by source. Keep a short `non_findings` list for plausible concerns that are correct as designed.

## 3. Register and verdict

Write the merged register in the [register schema](references/register-schema.md): one record per defect, stable `SURFACE-NN` IDs, screenshot plus percentage marker, heuristic and HIG IDs, severity, evidence label, claim, and smallest fix. Order by severity, then surface order, then ID.

Derive the verdict from open findings, never by averaging:

| Condition | Verdict |
| --- | --- |
| Any severity 4 | Blocked |
| Any severity 3 | Changes required |
| Only 1 and 2, but a material requirement untested | Review incomplete |
| Only 1 and 2 | Improvements identified |
| None open, all material requirements tested | Ready for decision |

Never call the result HIG compliant or release ready. Header format: `UX diagnostic 4/10 · HIG 9 pass, 6 fail, 5 untested, 3 N/A · Changes required · Worst open severity 3`.

## 4. Report

1. Write `docs/design/crits/<review-id>.md`: header, scope and environment, verdict, a short "what a first-time user experiences" walkthrough, the ranked findings, HIG outcomes table, non-findings, untested list, and a proposed fix order grouped into small PR-sized batches.
2. Render the annotated HTML with `python3 .agents/skills/crit/scripts/build_report.py .crit/<review-id>/register.json .crit/<review-id>/captures .crit/<review-id>/report.html` and publish it as an Artifact when the user wants to see or share it. Screenshots must be demo data only. Each marker links to its finding.
3. Report exact commands, the tested revision, skipped checks, and limits.

## Fix pass

Only with explicit implementation authority. Pick up to three small, high-confidence findings, fix them on a branch, run `swift test` and `swift build -c release`, repackage, recapture the affected surfaces with the same flags and appearance, and append a before and after section to the report. Keep implementation, verification, and commits as separate claims.
