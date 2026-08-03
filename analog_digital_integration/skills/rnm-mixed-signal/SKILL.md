---
name: rnm-mixed-signal
description: Real-Number Models (RNM) of analog blocks for mixed-signal sim on Neurophos SoCs. Two flows — the PROVEN netlist-assembly flow (rnmgen2 + hand-authored EEnet leaves, runs today) and the PROSPECTIVE 6-phase Spectre-driven auto-derivation flow (still pending proof, PoC on pixel_hh). Use when modeling analog, authoring an EEnet leaf, or evaluating the auto-derivation flow. Bundled: rnmgen2 + authoring tools (scripts/), full flow docs + examples (references/).
---

# RNM / Mixed-Signal Modeling (analog↔digital integration)

Everything this skill needs is bundled here — no external repo paths:
- `scripts/rnmgen2.py` — the netlist transformer.
- `scripts/bindkeys/{RMgenRnm.il,rnm_editor.py}` — Virtuoso EEnet-leaf authoring.
- `references/` — the full flow docs (`rnm_flow.md`, `EEnet_README.md`,
  `rnm_questionnaire.csv`, Virtuoso setup, decision-log `context/`) and
  `references/examples/` (a role checker `ee_roles.sv`, an EEnet leaf
  `dac_dark.sv`, and the flow `Makefile.rnm-flow`).

There are **two flows**. Know which you're using.

## What RNM buys
Simulate analog behavior at **digital speed** (event-driven, no Spectre in the
loop) using real-valued electrical nets (`EE_pkg::EEnet` — V/I/R with Kirchhoff
resolution). Discipline: Cadence native `EEnet`, not `wreal`/user nettypes;
digital nets stay `logic`. See `references/EEnet_README.md`.

---

## Flow A — PROVEN (runs today): netlist assembly from hand-authored leaves

Leaf behavioral models are **hand-authored** (source of truth); `rnmgen2`
assembles them into a typed netlist. Build with the flow Makefile
(`references/examples/Makefile.rnm-flow`): `make rnm` then `make sim`.

```
runams (structural netlist)
   -> scripts/rnmgen2.py (type-infer wire->EEnet, de-electrify R->short,
                          substitute behavioral leaves, stamp net roles)
   -> xrun (pure RNM, event-driven, live role assertions -> ALL PASS)
```
- **rnmgen2** (`scripts/rnmgen2.py`): seeds exact port types from the hand-authored
  leaf `.sv`; fixpoint-infers each net (`EEnet` iff it touches ≥1 EEnet port and 0
  logic ports; `conflict` reported, left logic); retypes the hierarchy;
  **de-electrifies primitives** (2-terminal R → ideal short, MOS/cap dropped — the
  leaves carry behavior); stamps VDD/GND/bias **roles** into bound checkers. Design
  notes: `references/context/rnmgen2-transformer.md`.
- **Leaves** authored/edited from Virtuoso via the F9/F10 bindkey
  (`scripts/bindkeys/{rnm_editor.py,RMgenRnm.il}`; usage `references/virtuoso_bindkeys.md`,
  setup `references/virtuoso_setup.md`). Example leaf: `references/examples/dac_dark.sv`.
- **Roles** (`references/examples/ee_roles.sv`): `chk_vdd/gnd/bias/diff` assertions
  catch mis-wired power/bias.
- **Self-contained** via a committed netlist snapshot in the *consuming project*:
  `make rnm` + `make sim` need no OA workspace; `make netlist` refreshes the
  snapshot from live OA (needs `startPrj`). Build/run details:
  `references/context/anatop-rnm-build-run.md`.

**Status: proven — this is the working flow. Use it now.**

---

## Flow B — PROSPECTIVE (pending proof): 6-phase auto-derivation from Spectre

Full spec: `references/rnm_flow.md`. Goal: instead of hand-authoring leaf
equations, **automatically derive** them from transistor-level Spectre.
**PoC block: `pixel_hh`** (S/H + source-follower). Principle: *Spectre is the
golden reference and extraction engine — no transistors are replaced.*

```
Phase 1  Topology analysis (automated)          -> topology_map.txt
Phase 2  Designer questionnaire (checkpoint 1)  -> questionnaire.md   (template: references/rnm_questionnaire.csv)
Phase 3  Spectre stimuli gen (semi-auto)        -> tb1_sf.vams … tb4_res.sps
Phase 4  Transfer-equation extraction (semi)    -> equation_table.txt (+ pixel_hh_extract.py)
Phase 5  Designer equation review (checkpoint 2)-> review_session.md   [loop to 3/4 if fail]
Phase 6  RNM code-gen + validation overlay      -> verilog.sv (OA view) + validation_overlay.png/csv
```
Principles: one equation per testbench; resistors characterized from the PDK
(TB4), not idealized; two human checkpoints; **fail-fast** (Phases 1–2 decide
suitability before Spectre budget). Applicability matrix (runs-as-is /
requires-modification / not-suitable) is in `references/rnm_flow.md`.

**Status: PROSPECTIVE / NOT YET PROVEN.** The phase artifacts are the intended
end-state, demonstrated only as a PoC on `pixel_hh`; not proven end-to-end or
generalized across AnaTop. Today, Flow A leaves are still hand-authored. Before
relying on Flow B: reproduce the `pixel_hh` PoC, validate the overlay error vs
Spectre per corner, and confirm the "semi-automated" Phase 3–4 pieces
(`pixel_hh_extract.py`, auto-TB generation) actually exist and run.

---

## Relationship
Flow B *feeds* Flow A: a proven Phase-6 model becomes a hand-off-quality leaf that
`rnmgen2` (Flow A) assembles into the full-chip RNM. Until Flow B is proven, new
leaves are authored by hand.

## Provenance
Distilled from the Neurophos MSIC `verif/model` RNM environment; the bundled
`references/` and `scripts/` are snapshots — regenerate against the live source if
the flow evolves.
