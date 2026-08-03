---
name: rnm-mixed-signal
description: Real-Number Models (RNM) of analog blocks for mixed-signal sim on Neurophos SoCs. Two flows — the PROVEN netlist-assembly flow (rnmgen2 + hand-authored EEnet leaves, make rnm/sim, runs today) and the PROSPECTIVE 6-phase Spectre-driven auto-derivation flow (rnm_flow.md, PoC on pixel_hh, still pending proof). Use when modeling AnaTop/analog, authoring a leaf, refreshing the netlist, or evaluating the auto-derivation flow.
---

# RNM / Mixed-Signal Modeling (analog↔digital integration)

There are **two flows** in `verif/model`. Know which you're using.

## What RNM buys
Simulate analog behavior at **digital speed** (event-driven, no Spectre in the
loop) using real-valued electrical nets (`EE_pkg::EEnet` — V/I/R with Kirchhoff
resolution) instead of transistor-level. Discipline: Cadence native `EEnet`, not
`wreal`/user nettypes; digital nets stay `logic`.

---

## Flow A — PROVEN (runs today): netlist assembly from hand-authored leaves

The AnaTop full-chip RNM that `make rnm`/`make sim` build and pass today. Leaf
behavioral models are **hand-authored** (source of truth); `rnmgen2` assembles
them into a typed netlist.

```
runams (structural OA netlist)
   -> rnmgen2.py (type-infer wire->EEnet, de-electrify R->short,
                  substitute behavioral leaves, stamp net roles)
   -> xrun (pure RNM, event-driven, live role assertions -> ALL PASS)
```
- **rnmgen2** (`verif/model/tools/rnmgen2.py`): seeds exact port types from the
  hand-authored leaf `.sv`; fixpoint-infers each net (`EEnet` iff it touches ≥1
  EEnet port and 0 logic ports; `conflict` reported, left logic); retypes the
  hierarchy; **de-electrifies primitives** (2-terminal R → ideal short, MOS/cap
  dropped — the leaves carry behavior); stamps VDD/GND/bias **roles** into bound
  checkers.
- **Leaves** (`src/leaves/*.sv`) authored/edited from Virtuoso via the F9/F10
  bindkey (`tools/bindkeys/{rnm_editor.py,RMgenRnm.il}`). **Roles**
  (`src/roles/ee_roles.sv`): `chk_vdd/gnd/bias/diff` assertions catch mis-wired
  power/bias.
- **Self-contained** via the committed netlist snapshot
  (`verif/model/netlist/…/netlist.vams`): `make rnm` + `make sim` need no OA
  workspace. `make netlist` only *refreshes* the snapshot from live OA (needs
  `startPrj`).
- This is also the environment described in the `uvm-system-level` skill (§B).

**Status: proven — this is the working flow. Use it now.**

---

## Flow B — PROSPECTIVE (pending proof): 6-phase auto-derivation from Spectre

Documented in `verif/model/doc/rnm_flow.md`. Goal: instead of hand-authoring leaf
equations, **automatically derive** them from transistor-level Spectre, closing
the loop. **Proof-of-concept block: `pixel_hh`** (S/H + source-follower).
Principle: *Spectre is the golden reference and extraction engine — no transistors
are replaced; they run as-is and produce the equations the RNM implements.*

```
Phase 1  Topology analysis (automated)          -> topology_map.txt
Phase 2  Designer questionnaire (checkpoint 1)  -> questionnaire.md
Phase 3  Spectre stimuli gen (semi-auto)        -> tb1_sf.vams … tb4_res.sps
Phase 4  Transfer-equation extraction (semi)    -> equation_table.txt (+ pixel_hh_extract.py)
Phase 5  Designer equation review (checkpoint 2)-> review_session.md   [loop back to 3/4 if fail]
Phase 6  RNM code-gen + validation overlay      -> verilog.sv (OA view) + validation_overlay.png/csv
```
Key principles (rnm_flow.md): one equation per testbench (no parameter
correlation); resistors characterized from the PDK (TB4), **not** idealized;
two human checkpoints (2 before sim, 5 before code); **fail-fast** — Phases 1–2
decide suitability before any Spectre budget is spent.

### Applicability (decide in Phase 1–2, before sim investment)
- **Runs as-is:** sampling/S-H, continuous-time buffer (SF/CS), reference/bias,
  level shifter, switch/mux.
- **Requires modification:** strongly nonlinear (escalate fit order / piecewise),
  feedback-dependent output impedance (characterize with real load), multi-cycle
  state (add state vars), oscillator (model freq-vs-control, not V-transfer).
- **Not suitable (flag early):** PLL/DLL closed-loop, strongly-distributed RC,
  mixed-domain (optical/thermal/RF — outside EEnet V/I scope).

**Status: PROSPECTIVE / NOT YET PROVEN.** The phase artifacts above are the
intended end-state, demonstrated only as a PoC on `pixel_hh`; the flow is not yet
proven end-to-end or generalized across AnaTop blocks. Today, leaves for Flow A
are still hand-authored. Before relying on Flow B: reproduce the `pixel_hh` PoC,
validate the overlay error against Spectre per corner, and confirm the extraction
scripts (`pixel_hh_extract.py` and the auto-TB generation) exist and run — much of
Phases 3–4 is described as "semi-automated" and may need the manual pieces filled.

---

## Relationship
Flow B *feeds* Flow A: a proven Phase-6 model becomes a hand-off-quality leaf that
`rnmgen2` (Flow A) assembles into the full-chip RNM. Until Flow B is proven, new
leaves are authored by hand (Virtuoso bindkey) and validated ad hoc.

## Sources (MSIC)
Flow A: `verif/model/{README.md,Makefile}`, `verif/model/tools/rnmgen2.py`,
`tools/bindkeys/{rnm_editor.py,RMgenRnm.il}`, `src/{leaves,roles}/`,
`netlist/`, `doc/EEnet_README.md`.
Flow B (prospective): `verif/model/doc/rnm_flow.md`,
`verif/model/doc/rnm_questionnaire.csv`,
`verif/model/doc/context/{anatop-rnm-build-run,anatop-rnm-project,rnmgen2-transformer}.md`,
`verif/model/doc/{virtuoso_setup,virtuoso_bindkeys}.md`.
