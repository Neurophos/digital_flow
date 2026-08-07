---
name: ai-artifact-separation
description: Separate internal/AI working artifacts from shareable engineering deliverables using a `.ai/` convention, so a repo can be handed to an external party (PCB design house, foundry, vendor, customer) by simply deleting every `.ai/` directory. Use when preparing a repo for external handoff/review, structuring a component's docs+scripts, consolidating scattered docs, or deciding where a generated/status/intermediate/tooling artifact belongs.
---

# ai-artifact-separation

## When to use
- Preparing a repo (or subtree) to hand to an **external party** for review — a PCB design house, package/substrate house, foundry, IP vendor, or customer — where internal notes, AI working docs, and generator tooling must **not** ship.
- Deciding where any artifact lives: is it a **deliverable** or an **internal/AI working artifact**?
- Consolidating a component's sprawling docs into a clean, reviewable set.
- Adding a repeatable **handoff build** (clone → strip → zip).

The core idea: keep one repo that serves both the internal team (with all the AI‑generated status, findings, generators, scratch) **and** external review, by putting everything internal under `.ai/` so a share is *clone + delete every `.ai/`*.

## The convention
Anything under **any `.ai/` directory is internal** (AI/working, not shipped). Everything else is a deliverable. Per component:

```
<component>/
  doc/            deliverable docs — ideally exactly SPEC + THEORY_OF_OPERATION      [SHARED]
  <design>/       the actual design (kicad/, rtl/, …)                                 [SHARED]
  .ai/scripts/    generators + tooling (the code that produces the design)            [internal]
  .ai/doc/        status / findings / handoff / intermediate & reference artifacts    [internal]
  .ai/scratch/    experiments, *_PROPOSED/_mockup/.orig/.bak, dsn/ses route trials     [internal]
```

| Belongs in a shared path | Belongs in `.ai/` |
|---|---|
| Specs, theory of operation, ICDs, BOM, mechanical/stackup/fab data, design‑rationale (ADRs, architecture, feasibility) a reviewer benefits from | Status/tracking/findings/handoff notes, install/tooling guides, generated `NETLIST.md`/reports, intermediate/scratch (`_PROPOSED`, `_mockup`, `.orig`, `.dsn`/`.ses` trials) |
| The design source that IS the deliverable (KiCad project + libs; released RTL) | The **generator/tooling** that *produces* it (`gen_*.py`, `make_*`, place/route scripts) |

**Hard invariant:** a shared (non‑`.ai/`) document must **never link into `.ai/`** — after the share deletes `.ai/`, such a link dangles. Cross‑links may go `.ai/ → shared`, never `shared → .ai/`; where a shared doc referenced a now‑internal doc, repoint it to the SHARED doc that absorbed the content, else drop the link to plain text.

## Flow
1. **Classify, don't delete.** Move internal artifacts into `.ai/` with `git mv` (preserve history); never lose content.
2. **Per component, consolidate `doc/` to two files:** a **SPEC** (reference: parts, pinouts, interfaces, values, BOM) and a **THEORY_OF_OPERATION** (how it works, end‑to‑end). Fold the scattered design‑refs/ICDs/notes into those; move the originals to `.ai/doc/` for reference. Non‑doc assets (PDFs, images, data CSVs, proofs) → `.ai/doc/` too unless a shared doc needs them.
3. **Scripts → `.ai/scripts/`.** Repoint each generator's OUTPUT path to the deliverable dir (e.g. `OUT=../../kicad`), NOT its own new location — see Gotchas.
4. **Non‑deliverable whole trees** (for a PCB handoff: FPGA RTL, firmware, verification, bring‑up) either move their status‑md into per‑tree `.ai/doc/` (source stays) or are dropped entirely by the handoff script's allow‑list — decide per audience.
5. **Automate the handoff:** a script that fresh‑clones the committed HEAD, `find . -type d -name .ai -prune -exec rm -rf {} +`, drops non‑deliverable top‑level trees (allow‑list), and zips — named by the release `git describe` tag. (Reference implementation: MSOP2's `scripts/make_pcb_handoff.sh`.)
6. **Verify before shipping (gates):**
   - no internal leak outside `.ai/`: `git ls-files | grep -vE '(^|/)\.ai/' | grep -Ei 'FINDINGS|NEXT_STEPS|_PROPOSED|_mockup|NETLIST\.md|\.(dsn|ses|orig|bak)$'` → empty
   - no shared→`.ai/` links: grep shared `*.md` for `](…/.ai/…)` → empty
   - no dangling relative links in shared `*.md`
   - **share dry‑run**: copy the tree, delete all `.ai/`, confirm the design opens (kicad‑cli DRC / RTL elaborates) and 0 dangling links.

## Gotchas
- **Generator output‑path coupling is the #1 breakage.** Generators typically do `HERE=dirname(__file__); OUT=HERE` (write to their own dir). After moving the script to `.ai/scripts/`, its output would land in `.ai/scripts/` — repoint `OUT`/`LIB`/`DOC` to the deliverable dir (`../../kicad`, `../doc`, `../.ai/doc`). Verify by re‑running and checking the diff is move‑only.
- **`${KIPRJMOD}` / relative lib refs:** move a KiCad project and its `lib/` + `*.pretty` + tables together, or 3D‑model/footprint refs break. Renaming the whole project dir (e.g. `gen/`→`kicad/`) is safest.
- **Shared→`.ai/` dangling links** appear only *after* the share deletes `.ai/` — the pre‑delete tree looks fine. Run the share dry‑run, not just an in‑place link check.
- **Obsidian `![[embed]]` images** don't render outside Obsidian and break when the image moves to `.ai/` — treat such notes as internal, or convert to plain markdown with the image kept alongside the shared doc.
- **Keep changelog/revision‑history rows** — they are *meant* to record history; don't scrub them when removing "historical narrative" from body text.
- **`git mv`, not delete+add**, so blame/history survives; the share is a snapshot (drop `.git`).
- **Don't ship what the audience can't use:** for a PCB handoff, FPGA/firmware trees are noise — allow‑list only `pcb/` + `doc/` (+ README).

## Sources
Distilled from the MSOP2_DRV_BRD repo's design‑house handoff prep:
`.ai/README.md` (the convention + share recipe + invariant), `.ai/doc/REPO_CLEANUP_PLAN.md` (full
per‑area manifest, generator‑path fixes, verification gates), and `scripts/make_pcb_handoff.sh` (the
clone→strip→zip release builder). The per‑board `doc/` = SPEC + THEORY_OF_OPERATION pattern and the
verified 0‑leak / 0‑dangling share dry‑run are the worked example.
