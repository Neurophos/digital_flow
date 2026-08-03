---
name: anatop-rnm-project
description: Full-chip pure-digital real-number model (RNM) of msic_a0/anatop using Cadence EE_pkg::EEnet
metadata:
  node_type: memory
  type: project
  originSessionId: 21802111-3f4e-4f5a-acf6-bebb892d3a7f
---

Full-chip real-number model (RNM) of the `msic_a0` cell `anatop` (imaging chip:
pixel array, DACs, bias, thermal sensors, row drivers, test interface). Goal: run
the WHOLE chip in the digital event kernel — **no Spectre, no analog solver**.

## Official discipline: Cadence native `EE_pkg::EEnet` (wreal & home-grown ee_net are LEGACY)
- `EEnet` = nettype `struct {real V, I, R}` with `res_EE()` doing the full Thevenin/Norton
  KCL solve (V=IT/GT; R=0 ⇒ ideal V source; >1 ideal V ⇒ X conflict; current sum; Z when
  undriven). Provided/precompiled by Cadence at
  `/tools/cadence/xcelium/25.09.001/tools/affirma_ams/etc/dms/EE_pkg.sv` (+ `dmsLib`).
  Because it's a single precompiled package, ALL leaves + the top share ONE type identity —
  this is what made multi-leaf netlisting work (a home-grown nettype hit NOPBIND/DUPIDN/TYCMPAT).
- **LEGACY, do not use going forward:** (a) `wreal` leaf views (`verilog.vams`) — netlist
  fine and coerce natively to plain wires, but voltage-only; the current `dac_dark/functional/
  verilog.v` wreal pilot is superseded. (b) the home-grown `ee_net`/`ee_if`/`ee_switch`
  (`cds/rnm/ee_if.sv`) — keep only as a standalone-bench learning artifact.

## The proven flow (verified end-to-end, full chip elaborates + simulates, exit 0)
`runams` (structure) → `rnmgen2.py` (type-infer + retype wire→EEnet + de-electrify + substitute)
→ `xrun` (pure RNM, *N,MSFLON RNM module, ~395k resolved EEnet nets, NO Spectre).
Details in [[rnmgen2-transformer]]; build/run commands in [[anatop-rnm-build-run]].

## Status (as of last work, Jun 2026)
- All 6 functional leaves rewritten as `EE_pkg::EEnet` `.sv` views in OA
  (`<cell>/functional/verilog.sv`; backups `verilog.v.logic.bak` + `master.tag.bak`):
  dac_dark, thermal, tst_intf, bias_array_vh, pixel_hh, row_drv.
- Full chip: `rnmgen2.py` → `netlist_ee.sv`, TYCMPAT 0, sim PASS (vts = 0.6+code*0.002;
  col_driver col_va = 0.5/1.0 by DAC code; hi-Z when pu_dac off).
- `col_driver` substituted as external behavioral `.sv` leaf; `pixel`/`col_driver` are the
  ONLY device leaves (column=111×pixel+1×col_driver; array_vh=222×column).
- OPEN TODO for fully self-driven zero-Spectre with real pixel function: `pixel` & `col_driver`
  only have SCHEMATIC (transistor) views — need FUNCTIONAL `EEnet` `.sv` views, which requires
  creating new OA cellviews in **Virtuoso** (models drafted in `cds/rnm/{pixel,col_driver}.sv`).

## Authoritative in-repo docs (don't duplicate — read these)
`cds/rnm/README.md` (build/sim/cov), `cds/rnm/rnm_flow.md` (6-phase transistor→RNM derivation
methodology, Spectre as golden reference), `cds/rnm/Makefile` (all targets).

See [[anatop-rnm-build-run]], [[rnmgen2-transformer]], [[anatop-config-netlisting]].
