---
name: ansys-siwave-sipi
description: Post-layout Signal-Integrity / Power-Integrity signoff with ANSYS SIwave (Electronics Desktop / AEDT), driven headlessly from Python via PyAEDT. KiCad/Allegro board in -> DCIR (IR-drop / current-density), PDN impedance Z(f), S-parameters, and coupling/eye out. Use after a board is routed + DRC-clean to validate power-trace width / rail droop, decoupling, and channel SI. The ANSYS toolchain is the SI/PI signoff path on this node -- Cadence Sigrity is NOT licensed here.
---

# ansys-siwave-sipi

> **STATUS: SCAFFOLD (2026-08-06).** The *environment discovery below is VERIFIED* (tools, license,
> install paths — all probed live). The *analysis flow + scripts are UNVALIDATED skeletons* — no
> SIwave solve has been run end-to-end from this repo yet. Expand + verify each step, then promote
> the "TO VALIDATE" markers to "verified" the way `allegro-specctra-routing/SKILL.md` documents its
> proven invocation. Do not present the scripts as tested until a real solve has closed.

## When to use
After a PCB is **routed and DRC-clean**, to answer physics the router can't:
- **DCIR (the first thing to run here):** does a power rail droop out of spec? Current-density
  hot-spots? Via/plane current? — *directly validates power-trace width / IR-drop concerns* (e.g.
  the DAC `PWR` net-class flattened 0.5→0.1 mm; see `pcb/BACKPLANE/GUI_PENDING_ACTIONS.md` §2c).
- **PDN impedance Z(f):** is the power-distribution-network impedance below target across frequency?
  (decoupling adequacy, plane resonance).
- **Channel / net SI:** reflection, crosstalk, insertion/return loss (S-parameters), eye diagrams —
  needs IBIS/SPICE driver-receiver models.

Not for on-chip EM (that's EMX/Virtuoso) or circuit sim (Spectre).

## Environment on this node — VERIFIED (probed 2026-08-06)
**Cadence Sigrity is NOT available.** No `PowerSI`/`PowerDC`/`SystemSI`/`3DEM`/Aurora-SI feature on
any Cadence license server (checked `27000@fs1`, `27018@fs1`, `27020@fs1`). The `sigritythermal`
(in Spectre) and `_allegroSigrity_private` (in SPB) binaries exist but are unlicensed. **Use ANSYS.**

**ANSYS Electronics Desktop (AEDT) 2025.1** — the SI/PI signoff toolchain:
- Install: `/tools/ansys/electronics/2025.1/v251/AnsysEM` · binary `ansysedt`
- License: `ANSYSLMD_LICENSE_FILE=27018@fs1` (vendor `ansyslmd`, port 62667). `module load ansys` sets it.
- Licensed features (3 seats each, valid to 2026-12-10):

| Feature (FlexLM) | Tool | Role |
|---|---|---|
| `elec_solve_siwave`, `siwave_level1` | **SIwave** | DCIR, PDN Z(f), S-params, resonance — *the Sigrity PowerSI+PowerDC equivalent* |
| `elec_solve_hfss` | **HFSS** | full-wave 3D EM (vias, connectors, breakouts) |
| `elec_solve_q3d` | **Q3D** | RLCG parasitic extraction |
| `elec_solve_icepak` | **Icepak** | thermal / CFD |
| `elec_solve_maxwell` | Maxwell | low-freq EM |
| `anshpc_pack` | HPC | parallel-solve seats |

Probe it yourself: `scripts/check_siwave_env.sh`.

## The flow (KiCad -> SIwave) — TO VALIDATE
```
routed dac_brd.kicad_pcb / backplane_disp.kicad_pcb
   │  1. kicad-cli pcb export odb  (or ipc2581)          scripts/export_kicad_odb.sh   [command verifiable]
   ▼
   board.odb (ODB++ zip)
   │  2. PyAEDT: Siwave().import_layout / edb import      scripts/siwave_dcir.py        [SKELETON]
   ▼
   SIwave project (.siw) with stackup + nets
   │  3. set REAL fab stackup (Er, loss tangent, Cu wt, dielectric heights) — NOT the
   │     representative make_12layer_v4 heights
   │  4. DCIR: define VRM source pins + load sink currents per rail;  solve
   │     PDN:  define ports at loads;  frequency sweep;  solve
   │     SYZ:  assign IBIS/SPICE at driver/receiver;  solve
   ▼
   5. parse: IR-drop table/CSV, current-density, Touchstone .sNp (S-params), Z(f)   [Claude-parseable]
   6. iterate: widen traces / add decoupling / adjust stackup -> re-route -> re-solve
```

## Automation — can Claude drive it? YES (via PyAEDT), same shape as SPECCTRA
- **PyAEDT** = ANSYS's Python API for AEDT (SIwave/HFSS/Q3D/Icepak). Headless with
  `non_graphical=True`; AEDT `-ng` batch usually needs **no Xvfb** (unlike the SPECCTRA Motif GUI).
- **Claude owns:** ODB++/IPC-2581 export, PyAEDT project build, source/sink + stackup setup, batch
  solve, and result parsing (IR-drop CSV, Touchstone, Z(f)).
- **User provides / validates:** per-rail **current budgets**, **IBIS/SPICE models** (FPGA/ADC
  vendor), the **real fab stackup**, and **pass/fail thresholds** (target Z, eye mask, max IR-drop).
  Wrong current budgets => meaningless IR-drop.
- **User reviews:** field / current-density heatmaps, eye diagrams (Claude reads numbers, not images).

## Prerequisites
- `module load ansys` (sets `ANSYSLMD_LICENSE_FILE=27018@fs1`, `ELECTRONICS_INST_DIR`).
- **PyAEDT is NOT in the node python yet** → `pip install pyaedt` (user site) or use AEDT's bundled
  Python: `/tools/ansys/electronics/2025.1/v251/AnsysEM/commonfiles/CPython/.../python`. [TO VALIDATE: exact path]
- `kicad-cli` for the ODB++/IPC-2581 export (present; see `kicad-pcb-flow`).
- A routed, DRC-clean `.kicad_pcb`.

## Board-specific starting inputs (MSOP2_DRV_BRD)
- **DAC board rails** (from the on-card regulators): `+1V0` (FPGA VCCINT, ≈0.3 A — the tight one,
  ±5% => <50 mV budget), `+1V8` (VCCAUX/VCCADC), `+3V3` (VCCO/digital), `+5V_ANA` (6× AD5380 +
  15× ADS7953 analog). [TO EXPAND: real per-rail current budgets from the power tree / BOM.]
- **First analysis to run:** SIwave **DCIR on `+1V0` and `+5V_ANA`** — settles the PWR-width question.
- Stackup: use the fab's actual 12-layer stackup, not the representative heights in
  `pcb/DAC_BRD/kicad/make_12layer_v4.py` (flagged there).

## TO EXPAND (open items — verify hands-on, then document as proven)
1. Exact PyAEDT import path for KiCad ODB++ → EDB/SIwave (EDB `import_layout` vs `Siwave` class; may
   need IPC-2581 or an intermediate). Confirm net/stackup fidelity after import.
2. AEDT bundled-Python path + minimum `pip install pyaedt` that imports cleanly on this node.
3. Headless batch invocation (`ansysedt -ng -features=...` / PyAEDT `non_graphical`) + license
   checkout name mapping (which feature each analysis pulls).
4. DCIR setup API: pin groups, source (VRM) + sink (load) current definitions, result export to CSV.
5. Parsing recipes: IR-drop table, current-density max, Touchstone S-params, Z(f) — turn into
   pass/fail vs thresholds.
6. Runtime/mesh sizing on a 12-layer, ~1200-net board; HPC (`anshpc_pack`) seats.

## References
- Discovery + rationale: memory `si-pi-toolchain-ansys-aedt`; power-current/IR-drop concern in
  `pcb/BACKPLANE/GUI_PENDING_ACTIONS.md` §2c and `pcb/DAC_BRD/kicad/make_12layer_v4.py`.
- Upstream flow (routing that precedes this): `allegro-specctra-routing`, `kicad-pcb-flow`.
- ANSYS: PyAEDT docs (aedt.docs.pyansys.com), SIwave DCIR/PDN user guide.
