#!/usr/bin/env python3
"""
Convert a JasperGold text results report to a self-contained HTML file.

Usage:
    python3 jg_html_report.py <results.txt> <output.html>
"""

import re
import sys
import html as esc
from pathlib import Path

# ---------------------------------------------------------------------------
# Parsing
# ---------------------------------------------------------------------------

def parse_header(txt):
    fields = {}
    for key, pattern in [
        ("version",  r"^\s+([\d.]+[a-z0-9]+\s+\d+ bits.*?)$"),
        ("host",     r"Host Name:\s+(.+)"),
        ("user",     r"User Name:\s+(.+)"),
        ("date",     r"Printed on:\s+(.+)"),
        ("workdir",  r"Working Directory:\s+(.+)"),
        ("top",      r"Top Level Module\s+:\s+(.+)"),
        ("clocks",   r"Clocks\s+:\s+(.+)"),
        ("resets",   r"Resets\s+:\s+(.+)"),
    ]:
        m = re.search(pattern, txt, re.MULTILINE)
        fields[key] = m.group(1).strip() if m else ""
    return fields


def parse_summary(txt):
    counts = {}
    for key, pattern in [
        ("assertions",   r"assertions\s+:\s+(\d+)"),
        ("proven",       r"-\s+proven\s+:\s+(\d+)"),
        ("cex",          r"-\s+cex\s+:\s+(\d+)"),
        ("undetermined", r"-\s+undetermined\s+:\s+(\d+)"),
        ("covers",       r"covers\s+:\s+(\d+)"),
        ("covered",      r"-\s+covered\s+:\s+(\d+)"),
        ("unreachable",  r"-\s+unreachable\s+:\s+(\d+)"),
        ("assumptions",  r"assumptions\s+:\s+(\d+)"),
    ]:
        m = re.search(pattern, txt)
        counts[key] = int(m.group(1)) if m else 0
    return counts


def parse_results_table(txt):
    """Parse the compact RESULTS table into a list of row dicts."""
    m = re.search(r"={20,}\nRESULTS\n={20,}(.*?)={20,}", txt, re.DOTALL)
    if not m:
        return []
    block = m.group(1)
    rows = []
    for line in block.splitlines():
        # e.g. [1]   full.name.ast_foo   proven   PRE   Infinite   0.000 s
        m2 = re.match(
            r"\[(\d+)\]\s+([\w.:]+)\s+([\w]+)\s+([\w]+)\s+([\w]+)\s+([\d.]+)\s*s",
            line.strip()
        )
        if not m2:
            continue
        idx, fullname, result, engine, bound, time_s = m2.groups()
        short = fullname.split(".")[-1]
        kind  = "cover" if (short.startswith("cov_") or "precondition" in short) else \
                "assume" if short.startswith("asm_") else "assert"
        rows.append({
            "idx":     int(idx),
            "short":   short,
            "full":    fullname,
            "result":  result,
            "engine":  engine,
            "bound":   bound,
            "time":    float(time_s),
            "kind":    kind,
        })
    return rows


# ---------------------------------------------------------------------------
# HTML rendering
# ---------------------------------------------------------------------------

RESULT_CLASS = {
    "proven":      "ok",
    "covered":     "ok",
    "cex":         "fail",
    "unreachable": "warn",
    "undetermined":"warn",
    "error":       "fail",
    "temporary":   "info",
}

CSS = """
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: 'Segoe UI', Arial, sans-serif; background: #f4f6f9;
       color: #222; font-size: 14px; padding: 24px; }
h1 { font-size: 20px; font-weight: 600; margin-bottom: 4px; }
.subtitle { color: #666; font-size: 12px; margin-bottom: 24px; }
.cards { display: flex; gap: 16px; flex-wrap: wrap; margin-bottom: 24px; }
.card { background: #fff; border-radius: 8px; padding: 16px 24px;
        box-shadow: 0 1px 4px rgba(0,0,0,.1); min-width: 140px; }
.card .num  { font-size: 32px; font-weight: 700; line-height: 1.1; }
.card .lbl  { font-size: 12px; color: #888; margin-top: 2px; }
.card.green .num { color: #1a7f37; }
.card.red   .num { color: #cf222e; }
.card.blue  .num { color: #0969da; }
.card.gray  .num { color: #6e7781; }
table { width: 100%; border-collapse: collapse; background: #fff;
        border-radius: 8px; box-shadow: 0 1px 4px rgba(0,0,0,.1);
        overflow: hidden; }
thead th { background: #1b2a4a; color: #fff; text-align: left;
           padding: 10px 12px; font-size: 12px; font-weight: 600;
           letter-spacing: .04em; }
tbody tr:nth-child(even) { background: #f9fafb; }
tbody tr:hover { background: #eef2ff; }
td { padding: 7px 12px; font-size: 12px; border-bottom: 1px solid #e5e7eb; }
td.name { font-family: monospace; font-size: 11px; word-break: break-all; }
.badge { display: inline-block; padding: 2px 8px; border-radius: 12px;
         font-size: 11px; font-weight: 600; }
.ok   { background: #d1fae5; color: #065f46; }
.fail { background: #fee2e2; color: #991b1b; }
.warn { background: #fef3c7; color: #92400e; }
.info { background: #e0e7ff; color: #3730a3; }
.meta { background: #fff; border-radius: 8px; padding: 16px 20px;
        box-shadow: 0 1px 4px rgba(0,0,0,.1); margin-bottom: 24px;
        display: grid; grid-template-columns: max-content 1fr; gap: 4px 16px; }
.meta .k { font-size: 11px; color: #888; font-weight: 600;
           text-transform: uppercase; letter-spacing: .04em; }
.meta .v { font-size: 12px; font-family: monospace; }
.filters { margin-bottom: 12px; display: flex; gap: 8px; flex-wrap: wrap; }
.filters button { padding: 4px 12px; border: 1px solid #d1d5db; border-radius: 6px;
                  background: #fff; cursor: pointer; font-size: 12px; }
.filters button.active { background: #1b2a4a; color: #fff; border-color: #1b2a4a; }
"""

JS = """
function filter(kind) {
    document.querySelectorAll('.filters button').forEach(b => b.classList.remove('active'));
    event.target.classList.add('active');
    document.querySelectorAll('tbody tr').forEach(r => {
        r.style.display = (kind === 'all' || r.dataset.kind === kind) ? '' : 'none';
    });
}
"""

def badge(result):
    cls = RESULT_CLASS.get(result, "info")
    return f'<span class="badge {cls}">{esc.escape(result)}</span>'


def render_html(header, summary, rows, src_path):
    assertions = [r for r in rows if r["kind"] == "assert"]
    covers     = [r for r in rows if r["kind"] == "cover"]
    assumes    = [r for r in rows if r["kind"] == "assume"]

    proven  = summary["proven"]
    cex     = summary["cex"]
    covered = summary["covered"]
    total_a = summary["assertions"]
    total_c = summary["covers"]

    all_pass = (cex == 0 and summary["undetermined"] == 0
                and summary["unreachable"] == 0)
    status_badge = badge("proven") if all_pass else badge("cex")

    table_rows = ""
    for r in rows:
        table_rows += (
            f'<tr data-kind="{r["kind"]}">'
            f'<td>{r["idx"]}</td>'
            f'<td class="name">{esc.escape(r["short"])}</td>'
            f'<td>{badge(r["result"])}</td>'
            f'<td>{esc.escape(r["engine"])}</td>'
            f'<td>{esc.escape(r["bound"])}</td>'
            f'<td>{r["time"]:.3f} s</td>'
            f'<td>{esc.escape(r["kind"])}</td>'
            f'</tr>\n'
        )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>pf_ed Formal Results</title>
<style>{CSS}</style>
</head>
<body>
<h1>pf_ed &mdash; Formal Verification Results &nbsp; {status_badge}</h1>
<div class="subtitle">
  {esc.escape(header.get('date',''))} &nbsp;&bull;&nbsp;
  {esc.escape(header.get('user',''))}@{esc.escape(header.get('host',''))} &nbsp;&bull;&nbsp;
  Source: {esc.escape(Path(src_path).name)}
</div>

<div class="meta">
  <span class="k">Top</span>     <span class="v">{esc.escape(header.get('top',''))}</span>
  <span class="k">Clock</span>   <span class="v">{esc.escape(header.get('clocks',''))}</span>
  <span class="k">Reset</span>   <span class="v">{esc.escape(header.get('resets',''))}</span>
  <span class="k">Tool</span>    <span class="v">{esc.escape(header.get('version',''))}</span>
</div>

<div class="cards">
  <div class="card green">
    <div class="num">{proven}/{total_a}</div>
    <div class="lbl">Assertions proven</div>
  </div>
  <div class="card {'red' if cex else 'green'}">
    <div class="num">{cex}</div>
    <div class="lbl">Counterexamples</div>
  </div>
  <div class="card blue">
    <div class="num">{covered}/{total_c}</div>
    <div class="lbl">Cover points hit</div>
  </div>
  <div class="card gray">
    <div class="num">{len(assumes)}</div>
    <div class="lbl">Assumptions</div>
  </div>
</div>

<div class="filters">
  Show:
  <button class="active" onclick="filter('all')">All ({len(rows)})</button>
  <button onclick="filter('assert')">Assertions ({len(assertions)})</button>
  <button onclick="filter('cover')">Covers ({len(covers)})</button>
  <button onclick="filter('assume')">Assumptions ({len(assumes)})</button>
</div>

<table>
  <thead>
    <tr>
      <th>#</th><th>Name</th><th>Result</th>
      <th>Engine</th><th>Bound</th><th>Time</th><th>Kind</th>
    </tr>
  </thead>
  <tbody>
{table_rows}  </tbody>
</table>
<script>{JS}</script>
</body>
</html>
"""


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    if len(sys.argv) != 3:
        sys.exit(f"usage: {sys.argv[0]} <results.txt> <output.html>")

    src, dst = sys.argv[1], sys.argv[2]
    txt = Path(src).read_text(errors="replace")

    header  = parse_header(txt)
    summary = parse_summary(txt)
    rows    = parse_results_table(txt)

    if not rows:
        sys.exit(f"error: no results rows parsed from {src}")

    Path(dst).write_text(render_html(header, summary, rows, src))
    print(f"written: {dst}  ({len(rows)} rows)")


if __name__ == "__main__":
    main()
