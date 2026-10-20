# Little Limits HIG review

**Scope and expected outcome:** [Affected task and surfaces]
**Tested revision:** [Commit plus uncommitted changes, if any]
**Environment:** [macOS, SDK, hardware, packaged Release build, window size]
**Inputs and settings:** [Pointer, keyboard, assistive technology, appearance, actual display preferences]
**Date and sources reviewed:** [Date, source URLs, verification dates]

This report records evidence for the stated scope, not product certification.

## Requirement results

Select applicable IDs from `config/hig-rubric.yaml`. Do not expand a focused review to every surface. `lastVerified` in the catalog records guidance review, not an app test.

| Requirement | Authority | Outcome | Evidence or limit | Finding |
| --- | --- | --- | --- | --- |
| [Rule ID] | [apple-hig/project] | [pass/fail/untested/na] | [Evidence label, source or capture path, steps, result] | [ID if failed] |

- `pass`: available evidence demonstrates the requirement within this scope.
- `fail`: available evidence demonstrates a defect.
- `untested`: evidence is insufficient; name the needed test.
- `na`: the requirement does not apply; give a reason.

Label evidence `measured`, `observed`, `needs device test`, or `assumption`. For a measurement, record native points, actual hit region or font, appearance, background, capture scale, threshold, and source as applicable. Do not report unmeasured contrast as passing.

## Findings

Order by impact on completing the task. Keep finding IDs stable across follow-up reviews.

- **[ID] [Impact] [Concrete problem].** Trigger: [Repeatable steps]. Evidence: [Actual result and source location or runtime capture]. Requirement: [ID and applicable source]. Correction: [Smallest useful change]. Verification: [Observable result and cheapest reliable check].

For a before/after claim, record comparable baseline and changed results under the same conditions. Source inspection is not an observed baseline runtime failure.

## Verification and limits

| Command or interaction | Result | Tested build or revision |
| --- | --- | --- |
| [Exact command or task] | [Observed result, counts, failures, skips, or unavailable environment] | [Revision] |

List outstanding keyboard, VoiceOver, display-preference, empty/failure, provider, older-macOS, Intel, and packaging checks relevant to this scope. Distinguish build, launch, visual inspection, and distribution trust. Keep credentials out of evidence; use demo fixtures for shareable captures. Record durable observed results in `docs/VALIDATION.md`.
