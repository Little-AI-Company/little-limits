# Finding register

One JSON record per defect in `.crit/<review-id>/register.json`. The register feeds the report, the annotated HTML (`scripts/build_report.py`, standard library only), and any later fix pass. Auditors may hand off YAML; the merged register is JSON.

```json
{
  "title": "Little Limits Design Crit",
  "review": "2026-10-14-baseline",
  "revision": "bb445d3",
  "environment": "macOS 27.0.1, Apple silicon, packaged Release, 2x display",
  "walkthrough": ["One paragraph per step of a first-time user's experience."],
  "fix_batches": [{ "title": "1. Make the status menu readable.", "why": "Scope and files.", "findings": ["MENU-01"] }],
  "findings": [
    {
      "id": "HOME-01",
      "surface": "home",
      "also_on": ["account"],
      "screenshot": "light-home-window.png",
      "marker": { "x": 32.6, "y": 51.4 },
      "source": "both",
      "heuristic": ["krug.dont-make-me-think", "nielsen.8"],
      "hig_requirement": "window.toolbar.grouping",
      "severity": 3,
      "evidence": "observed",
      "measurement": "Refresh All 18 pt tall at 2x capture",
      "source_location": "Sources/AIUsageStats/HomeViewController.swift:120",
      "doctrine": "NATIVE-DESIGN.md: ...",
      "claim": "One sentence describing the defect and who it hurts.",
      "expected_fix": "Smallest change that removes the defect.",
      "status": "open"
    }
  ],
  "diagnostic": { "score": 4, "rows": [{ "row": 8, "text": "Does it work without hover?", "result": "untested", "findings": [] }] },
  "hig_outcomes": [{ "id": "window.toolbar.grouping", "outcome": "fail", "evidence": "source: ...", "findings": ["HOME-01"] }],
  "non_findings": [{ "surface": "status-menu", "claim": "Gray account section headers are the documented native exception." }],
  "untested": [{ "requirement": "accessibility.name-role-value-state", "needed": "VoiceOver pass over Home and the status menu" }]
}
```

Field values: `source` is `ux`, `hig`, or `both`. `evidence` is `measured`, `observed`, `source`, `needs device test`, or `assumption`. `status` is `open`, `fixed`, `unverified` (fixed in source, no runtime evidence yet), or `wontfix`. Diagnostic `result` and HIG `outcome` are `pass`, `fail`, `untested`, or `na` (diagnostic rows have no `na`). `marker` is a percentage of the screenshot's width and height.

## Rules

- Every finding has a screenshot and marker, or a source location with `evidence: source`. No evidence, no finding.
- The same defect on several surfaces is one record; list the others in `also_on` and mark the most visible capture.
- Severity weighs frequency, impact, and persistence. A defect on the glance path (status item, status menu, Home top) is more frequent than one in the manual balance editor.
- HIG-only findings get the orchestrator's severity with a one-line rationale.
- Surface order for sorting: status-menu, home, account, settings, add-account, platform, empty, error.
- Quick Diagnostic: start at 10, subtract 2 per failed row whose worst open finding is severity 3 or 4, otherwise 1. Untested rows are not scored and never render as pass.
- `build_report.py` derives the verdict and header from open findings, HIG outcomes, and the diagnostic score; the register does not store them.
- A later round keeps finding IDs. Set `status` to `fixed` only with an after capture or test that shows the defect gone, and to `unverified` when only source shows it; counts, sections, and the verdict use open findings only.
