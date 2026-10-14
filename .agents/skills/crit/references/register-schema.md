# Finding register

One YAML record per defect. The register feeds the report, the annotated HTML, and any later fix pass.

```yaml
review: 2026-10-14-baseline
revision: bb445d3            # plus "dirty" when the tree had changes
environment: macOS 27.0.1, Apple silicon, packaged Release, 2x display
findings:
  - id: HOME-01                # SURFACE-NN, stable across rounds
    surface: home
    screenshot: light-home-window.png
    marker: { x: 32.6, y: 51.4 }  # percent of image width and height
    source: ux                 # ux, hig, or both
    heuristic: [krug.dont-make-me-think, nielsen.8]
    hig_requirement: window.toolbar.grouping
    severity: 3                # 0 to 4, from the UX scale
    evidence: observed         # measured, observed, source, needs device test, assumption
    measurement: "Refresh All 18 pt tall at 2x capture"   # when measured
    source_location: Sources/AIUsageStats/HomeViewController.swift:120
    doctrine: "NATIVE-DESIGN.md: ..."   # quote when a documented decision is involved
    claim: One sentence describing the defect and who it hurts.
    expected_fix: Smallest change that removes the defect.
    status: open               # open, fixed, wontfix
non_findings:
  - surface: status-menu
    claim: Gray account section headers look like subtitles but are the documented native exception.
untested:
  - requirement: accessibility.name-role-value-state
    needed: VoiceOver pass over Home and the status menu
```

## Rules

- Every finding has a screenshot and marker, or a source location with `evidence: source`. No evidence, no finding.
- The same defect on several surfaces is one record listing every surface; use the most visible capture for the marker.
- Severity weighs frequency, impact, and persistence. A defect on the glance path (status item, status menu, Home top) is more frequent than one in the manual balance editor.
- HIG-only findings get the orchestrator's severity with a one-line rationale.
- Surface order for sorting: status-item, status-menu, home, account, settings, add-account, platform, empty, error.
- Quick Diagnostic: start at 10, subtract 2 per failed row whose worst finding is severity 3 or 4, otherwise 1. Name the finding IDs behind each failed row.
