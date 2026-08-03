---
name: anatop-rnm-build-run
description: Build/run the anatop EEnet RNM (Makefile targets, paths, EEnet idioms, session resume)
metadata:
  node_type: memory
  type: reference
  originSessionId: 21802111-3f4e-4f5a-acf6-bebb892d3a7f
---

Build dir: `cds/rnm/` (`Makefile`). Every target needs `module load cadence/xcelium/25.09.001`.
The `netlist` target additionally needs the project env: `startPrj msic msic_a0`.

## Makefile targets
`make help` · `netlist` (runams → ../anatop_nl/netlist/netlist.vams; needs startPrj) ·
`rnm` (rnmgen2.py → netlist_ee.sv) · `elab` · `sim` (compile+run tb_anatop → ALL PASS) ·
`waves` (scoped SHM) · `wavesall` (full hier, slow) · `cov` / `covreport` · `clean`.
Full regen from scratch: `startPrj msic msic_a0; make netlist; make rnm; make sim`.

## Key paths
- EE_pkg: `/tools/cadence/xcelium/25.09.001/tools/affirma_ams/etc/dms/EE_pkg.sv` (Makefile `DMS`/`EE`).
- OA leaves: `/projects/msic/msic_a0/analog/oa/msic_a0/<cell>/functional/verilog.sv`
  (dac_dark, thermal, tst_intf, bias_array_vh, pixel_hh, row_drv).
- Generated top: `cds/rnm/netlist_ee.sv` (anatop/array_vh/column). TB: `tb_anatop.sv` (TOP=tb_anatop).
- Extra behavioral leaves substituted in: `col_driver.sv`, `pixel.sv`.
- Compile order (single xrun ⇒ one EE_pkg identity): `EE_pkg.sv` + leaf `.sv`s + `netlist_ee.sv` + TB.
- `dmsLib` referenced via `cds_user.lib`; for runams: nettype views need `.sv` master + dmsLib in cds.lib.

## EEnet driver idioms (read voltage with `.V`)
- ideal V source: `'{V:v, I:0.0, R:0.0}`   ·   V with output R: `'{V:v, I:0.0, R:r}`
- ideal current:  `'{V:`wrealZState, I:i, R:`wrealZState}`   ·   hi-Z: all `wrealZState`
- hi-Z detect: `wrealZState` is NaN-like → test "value not in expected range", not magnitude>1e30.
- SPEC-TODO parameters in leaf models are placeholders (replace with datasheet/extraction values).

## Authoring leaf models from Virtuoso (F9/F10 bindkey)
`cds/bindkeys/RMgenRnm.il` (SKILL) + `rnm_editor.py` (py3.12 tkinter GUI): in a schematic,
select an instance and press F9 -> GUI to set each port type (EEnet/logic) + direction, edit
body, Save -> writes `<cell>/functional/verilog.sv` + repoints master.tag (backs up). F10 =
dry-run to CIW. Idempotent (regenerates port header, preserves body); flags added/deleted pins.
Load via workspace `.cdsinit_user` (loads RMgenRnm.il [F9/F10] + wiretracking.il [F4/F5]).
Globals in RMgenRnm.il: RMrnmPython (needs py3.12+tkinter, NOT system py3.6), RMrnmPyScript,
RMrnmDigitalPats, RMrnmForceInout. Front end that produces the EEnet leaf views the
runams->rnmgen2->xrun flow consumes. Copied into the reference repo at
`dig_msic/dig_msic/verif/model/tools/bindkeys/`.

VIRTUOSO/LIB SETUP: `cds/cds_user.lib` (SOFTINCLUDEd by prj_cds.lib) has
`DEFINE dmsLib /tools/cadence/xcelium/25.09.001/tools/affirma_ams/etc/dms/dmsLib` — the
PRECOMPILED Cadence native RNM packages (EE_pkg::EEnet + cds_rnm_pkg wreal types), giving one
shared type identity (required for EEnet leaves to netlist/elaborate; not auto-included).
Documented in repo `verif/model/doc/virtuoso_setup.md` + `setup/*.example` fragments.

## Resume this work from another terminal
- `cd /projects/msic/msic_a0/users/robson/wksp1/cds` then `claude --continue` (-c, most recent)
  or `claude --resume` (-r, picker). Same host/user; project memory loads either way.
- TIP: launch claude from INSIDE a `startPrj msic msic_a0` shell so the Bash tool inherits
  runams + libs env (otherwise startPrj's project subshell does not persist into the tool shell).
- `startPrj` = `/tools/bin/prod/latest/startPrj` (opens a project subshell; `-s` for in-place).

See [[anatop-rnm-project]], [[rnmgen2-transformer]], [[anatop-config-netlisting]].
