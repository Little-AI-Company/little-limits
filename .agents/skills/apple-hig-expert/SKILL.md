---
name: apple-hig-expert
description: Design or review AI Usage Stats using current Apple Human Interface Guidelines for its native macOS AppKit status menu, account management, settings, and isolated Claude Platform sign-in. Use for interface and accessibility work in this repository.
license: MIT
metadata:
  version: 3.0.0
  author: Alireza Rezvani
  adapted-by: AI Usage Stats contributors
  category: design
  updated: "2026-10-14"
---

# Apple HIG Expert

Apply current Apple Human Interface Guidelines (HIG) to this app's actual tasks and AppKit architecture. Preserve the source skill's distinction between observed behavior, measurements, and untested assumptions. A review records evidence; it does not certify accessibility, HIG compliance, or distribution readiness.

## Establish the context

Read the repository's `AGENTS.md`, `docs/STRATEGY.md`, `docs/NATIVE-DESIGN.md`, and the affected source before proposing changes. Read [project-profile.md](references/project-profile.md) for the app's surfaces, data meanings, and verification paths. Questions and review requests remain read-only unless the user asks for implementation.

Record the surface, macOS version, SDK, window size, input methods, appearance settings, and available evidence. Distinguish the status menu, account overview, manual editor, App Settings, subscription sign-in sheet, and isolated Platform browser. A screenshot or source inspection cannot establish keyboard behavior, VoiceOver output, or account isolation.

## Select guidance

- Read [design-principles.md](references/design-principles.md) when choosing structure or weighing product tradeoffs.
- Read [visual-design.md](references/visual-design.md) for typography, color, layout, menu icons, and Liquid Glass.
- Read [accessibility.md](references/accessibility.md) for control sizes, contrast, focus, display settings, and assistive technology.
- Read [macos-components.md](references/macos-components.md) for current sidebar, toolbar, scroll edge, settings, sheet, alert, chart, writing, and menu bar extra rules.
- Use [hig-rubric.yaml](config/hig-rubric.yaml) for stable requirement IDs, source URLs, and verification dates. Its `apple-hig` and `project` authorities keep Apple recommendations separate from this repository's decisions.

This product monitors accounts; it does not generate content or execute agent tasks. Do not add a generative AI workflow because the app's name includes AI. Its ordinary controls are native, so browser DOM measurements, CSS rules, and web component contracts do not apply. Use native inspection instead of importing the source skill's browser measurement scripts or their Bun dependency.

## Design or review

For design work, establish the task and accurate data states first, then choose standard AppKit components. Preserve the macOS 14 deployment target and Swift 6 concurrency checks. Verify availability before recommending a newer API; prefer native fallback behavior to a compatibility abstraction.

For a review:

1. Define the observable result and scope. Select only requirements relevant to the affected interaction.
2. Verify the applicable live Apple sources. Compare project guidance with the current code and identify stale notes explicitly.
3. Use the cheapest reliable check: source review for implementation facts, native inspection for dimensions and semantics, and the packaged app for behavior.
4. Record each selected requirement as `pass`, `fail`, `untested`, or `na`. Support findings with a source location or runtime evidence and the smallest useful correction.

Use [hig-audit-template.md](templates/hig-audit-template.md) for a requested audit. Label evidence `measured`, `observed`, `needs device test`, or `assumption`. Report findings and limits without a synthetic score. Keep untested behavior unknown rather than treating standard components or successful compilation as a pass.

For before/after claims, compare the same task, element, build configuration, OS, appearance, input, units, and rule. Record the tested revision and any uncommitted changes. Native dimensions use points; Retina screenshot pixels are not points without the capture scale.

Follow the verification requirements in `AGENTS.md`. Changed native UI requires packaging and interaction checks; documentation-only skill updates require reference review and `git diff --check`. Put durable observed evidence in `docs/VALIDATION.md`. Keep screenshots and reports free of credentials and use demo data for shareable captures.

## Keep guidance current

The applicable HIG sources were reviewed on October 13, 2026, and the component pages in `macos-components.md` on October 14, 2026, including Apple-hosted documentation JSON where the HTML required JavaScript. Review [What's new in design](https://developer.apple.com/design/whats-new/) and the relevant live HIG page before a time-sensitive recommendation, especially after WWDC or a September release.

Record the URL and actual review date. Reachability alone is not verification. Update only the rules whose meaning was checked; preserve earlier dates for unreviewed claims. Current Apple documentation owns Apple guidance, and repository documentation owns local product decisions. Report conflicts rather than silently promoting a local preference into an Apple requirement.
