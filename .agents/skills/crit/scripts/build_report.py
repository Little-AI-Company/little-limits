#!/usr/bin/env python3
"""Render a crit register as a self-contained annotated HTML report.

Usage: python3 build_report.py <register.json> <captures-directory> <output.html>

Standard library only. Counts, sections, and the major list cover open findings;
fixed and wontfix findings render in a resolved list; unverified findings (fixed in
source only) render as awaiting verification and keep the verdict incomplete.

Screenshots referenced by findings are downscaled to JPEG with sips and
embedded as data URIs, so the page has no external image dependencies.
"""

import base64
import html
import json
import subprocess
import sys
import tempfile
from collections import OrderedDict
from pathlib import Path


SURFACE_ORDER = ["status-menu", "home", "account", "settings", "add-account", "platform", "empty", "error"]
SURFACE_NAMES = {
    "status-menu": "Status menu",
    "home": "Home",
    "account": "Account page",
    "settings": "App Settings",
    "add-account": "Add account",
    "platform": "Platform credits",
    "empty": "Empty state",
    "error": "Load failure",
}
SEVERITY_NAMES = {4: "Catastrophic", 3: "Major", 2: "Minor", 1: "Cosmetic", 0: "Not a problem"}


def escape(value) -> str:
    return html.escape(str(value if value is not None else ""))


def embed_image(path: Path, workdir: Path) -> str:
    target = workdir / (path.stem + ".jpg")
    subprocess.run(
        ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "78", "-Z", "1600", str(path), "--out", str(target)],
        check=True,
        capture_output=True,
    )
    return "data:image/jpeg;base64," + base64.b64encode(target.read_bytes()).decode("ascii")


def diagnostic_result(row: dict) -> str:
    """Quick Diagnostic rows are pass, fail, or untested; an evidence gap never renders as pass."""
    result = row.get("result")
    if result not in ("pass", "fail", "untested"):
        sys.exit(f"diagnostic row {row.get('row')} needs result pass, fail, or untested")
    return result


def assessment(findings: list, pending: list, register: dict) -> tuple:
    """Derive the verdict and header from open findings, never from stored text."""
    worst = max((int(finding.get("severity", 0)) for finding in findings), default=0)
    outcomes = [outcome.get("outcome") for outcome in register.get("hig_outcomes", [])]
    if worst >= 4:
        verdict = "Blocked"
    elif worst == 3:
        verdict = "Changes required"
    elif (pending or "untested" in outcomes or register.get("untested")
          or any(row.get("result") == "untested" for row in register.get("diagnostic", {}).get("rows", []))):
        verdict = "Review incomplete"
    elif findings:
        verdict = "Improvements identified"
    else:
        verdict = "Ready for decision"
    score = register.get("diagnostic", {}).get("score")
    parts = [f"UX diagnostic {score}/10"] if score is not None else []
    if outcomes:
        parts.append("HIG " + ", ".join(f"{outcomes.count(name)} {label}" for name, label in
                                        (("pass", "pass"), ("fail", "fail"), ("untested", "untested"), ("na", "N/A"))))
    parts += [verdict, f"Worst open severity {worst}"]
    return f"{verdict}. Worst open severity {worst}.", " · ".join(parts)


def surface_rank(finding: dict) -> int:
    surface = finding.get("surface", "")
    return SURFACE_ORDER.index(surface) if surface in SURFACE_ORDER else len(SURFACE_ORDER)


def render_finding(finding: dict) -> str:
    severity = int(finding.get("severity", 0))
    references = list(finding.get("heuristic") or [])
    if finding.get("hig_requirement"):
        references.append(finding["hig_requirement"])
    location = finding.get("source_location")
    rows = [
        f'<p class="claim">{escape(finding.get("claim"))}</p>',
        f'<p><span class="label">Fix</span>{escape(finding.get("expected_fix"))}</p>',
    ]
    if finding.get("doctrine"):
        rows.append(f'<p><span class="label">Doctrine</span>{escape(finding["doctrine"])}</p>')
    if finding.get("measurement"):
        rows.append(f'<p><span class="label">Measured</span>{escape(finding["measurement"])}</p>')
    meta = [escape(finding.get("evidence", ""))]
    if location:
        meta.append(f"<code>{escape(location)}</code>")
    if references:
        meta.append(" ".join(f"<code>{escape(reference)}</code>" for reference in references))
    return (
        f'<li class="finding" id="{escape(finding["id"])}" data-severity="{severity}">'
        f'<div class="finding-head"><span class="severity s{severity}">{severity} {SEVERITY_NAMES.get(severity, "")}</span>'
        f'<a class="finding-id" href="#{escape(finding["id"])}">{escape(finding["id"])}</a></div>'
        + "".join(rows)
        + f'<p class="meta">{" · ".join(meta)}</p></li>'
    )


def render_capture(name: str, data_uri: str, findings: list) -> str:
    markers = []
    for finding in findings:
        marker = finding.get("marker") or {}
        if "x" not in marker or "y" not in marker:
            continue
        severity = int(finding.get("severity", 0))
        markers.append(
            f'<a class="marker s{severity}" href="#{escape(finding["id"])}" '
            f'style="left:{float(marker["x"]):.2f}%;top:{float(marker["y"]):.2f}%" '
            f'aria-label="{escape(finding["id"])}: {escape(finding.get("claim"))}">{escape(finding["id"].split("-")[-1])}</a>'
        )
    return (
        f'<figure class="capture"><div class="frame"><img src="{data_uri}" alt="{escape(name)}" loading="lazy">'
        + "".join(markers)
        + f'</div><figcaption><code>{escape(name)}</code></figcaption></figure>'
    )


def main() -> None:
    if len(sys.argv) != 4:
        sys.exit("usage: build_report.py <register.json> <captures-directory> <output.html>")
    register = json.loads(Path(sys.argv[1]).read_text())
    captures = Path(sys.argv[2])
    output = Path(sys.argv[3])
    ordered = sorted(
        register.get("findings", []),
        key=lambda finding: (-int(finding.get("severity", 0)), surface_rank(finding), finding["id"]),
    )
    findings = [finding for finding in ordered if finding.get("status", "open") == "open"]
    pending = [finding for finding in ordered if finding.get("status") == "unverified"]
    resolved = [finding for finding in ordered if finding.get("status") in ("fixed", "wontfix")]

    by_surface: "OrderedDict[str, list]" = OrderedDict((surface, []) for surface in SURFACE_ORDER)
    for finding in findings:
        by_surface.setdefault(finding.get("surface", "other"), []).append(finding)

    sections = []
    with tempfile.TemporaryDirectory() as temporary:
        workdir = Path(temporary)
        for surface, surface_findings in by_surface.items():
            if not surface_findings:
                continue
            screenshots: "OrderedDict[str, list]" = OrderedDict()
            for finding in surface_findings:
                name = finding.get("screenshot")
                if name and not (captures / name).exists():
                    sys.exit(f"{finding['id']}: screenshot {name} is missing from {captures}")
                if not name and finding.get("evidence") in ("observed", "measured"):
                    sys.exit(f"{finding['id']}: {finding['evidence']} evidence needs a screenshot")
                if name:
                    screenshots.setdefault(name, []).append(finding)
            figures = "".join(
                render_capture(name, embed_image(captures / name, workdir), grouped)
                for name, grouped in screenshots.items()
            )
            items = "".join(render_finding(finding) for finding in surface_findings)
            sections.append(
                f'<section class="surface" id="surface-{escape(surface)}">'
                f'<h2>{escape(SURFACE_NAMES.get(surface, surface))} <span class="count">{len(surface_findings)}</span></h2>'
                f'<div class="surface-body"><div class="captures">{figures or "<p class=meta>Source evidence only. Not captured this run.</p>"}</div>'
                f'<ol class="findings">{items}</ol></div></section>'
            )

    counts = {severity: sum(1 for finding in findings if int(finding.get("severity", 0)) == severity) for severity in (4, 3, 2, 1)}
    count_line = " · ".join(f'<span class="severity s{s}">{counts[s]} × {s}</span>' for s in (4, 3, 2, 1) if counts[s])
    top = "".join(
        f'<li><a href="#{escape(f["id"])}">{escape(f["id"])}</a> {escape(f.get("claim"))}</li>'
        for f in findings
        if int(f.get("severity", 0)) >= 3
    )
    walkthrough = "".join(f"<p>{escape(paragraph)}</p>" for paragraph in register.get("walkthrough", []))
    open_ids = {finding["id"] for finding in findings}
    batches = "".join(
        f'<li><strong>{escape(batch["title"])}</strong> {escape(batch.get("why", ""))} '
        + " ".join(f'<a href="#{escape(i)}">{escape(i)}</a>' for i in batch_ids)
        + "</li>"
        for batch in register.get("fix_batches", [])
        if (batch_ids := [i for i in batch.get("findings", []) if i in open_ids])
    )
    hig_rows = "".join(
        f'<tr><td><code>{escape(o["id"])}</code></td><td class="outcome {escape(o["outcome"])}">{escape(o["outcome"])}</td>'
        f'<td>{escape(o.get("evidence", ""))}</td><td>{" ".join(f"<a href=#{escape(i)}>{escape(i)}</a>" for i in o.get("findings", []) or [])}</td></tr>'
        for o in register.get("hig_outcomes", [])
    )
    diagnostic_rows = "".join(
        f'<tr><td>{escape(r["text"])}</td><td class="outcome {diagnostic_result(r)}">{diagnostic_result(r)}</td>'
        f'<td>{" ".join(f"<a href=#{escape(i)}>{escape(i)}</a>" for i in r.get("findings", []) or [])}</td></tr>'
        for r in register.get("diagnostic", {}).get("rows", [])
    )
    non_findings = "".join(
        f'<li><strong>{escape(n.get("surface"))}</strong> {escape(n.get("claim"))}</li>' for n in register.get("non_findings", [])
    )
    untested = "".join(
        f'<li><code>{escape(u.get("requirement", ""))}</code> {escape(u.get("needed"))}</li>' for u in register.get("untested", [])
    )

    verdict, header = assessment(findings, pending, register)
    resolved_items = "".join(
        f'<li id="{escape(f["id"])}"><a href="#{escape(f["id"])}">{escape(f["id"])}</a> <span class="outcome">{escape(f.get("status"))}</span> {escape(f.get("claim"))}</li>'
        for f in resolved
    )
    pending_items = "".join(
        f'<li id="{escape(f["id"])}"><a href="#{escape(f["id"])}">{escape(f["id"])}</a> {escape(f.get("claim"))} '
        f'<span class="meta">{escape(f.get("round_note", ""))}</span></li>'
        for f in pending
    )
    template = (Path(__file__).with_name("report_template.html")).read_text()
    page = (
        template.replace("{{title}}", escape(register.get("title", "Design Crit")))
        .replace("{{header}}", escape(header))
        .replace("{{environment}}", escape(register.get("environment", "")))
        .replace("{{revision}}", escape(register.get("revision", "")))
        .replace("{{verdict}}", escape(verdict))
        .replace("{{counts}}", count_line)
        .replace("{{top}}", top)
        .replace("{{walkthrough}}", walkthrough)
        .replace("{{batches}}", batches)
        .replace("{{sections}}", "".join(sections))
        .replace("{{diagnostic}}", diagnostic_rows)
        .replace("{{hig}}", hig_rows)
        .replace("{{non_findings}}", non_findings)
        .replace("{{untested}}", untested)
        .replace("{{resolved}}", resolved_items or "<li>None</li>")
        .replace("{{pending}}", pending_items or "<li>None</li>")
    )
    output.write_text(page)
    print(f"wrote {output} ({output.stat().st_size // 1024} KB, {len(findings)} open, {len(pending)} unverified, {len(resolved)} resolved)")


if __name__ == "__main__":
    main()
