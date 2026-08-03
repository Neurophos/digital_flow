---
name: rnmgen2-transformer
description: How wire→EEnet propagation across the anatop netlist hierarchy actually works (rnmgen2.py)
metadata:
  node_type: memory
  type: reference
  originSessionId: 21802111-3f4e-4f5a-acf6-bebb892d3a7f
---

`runams` does NOT auto-retype: the generated `netlist.vams` declares all real nets as plain
`wire`. So connecting `EEnet` leaves needs a post-processor — `cds/rnm/rnmgen2.py` (the
proven tool; `rnmgen.py`/`retyper.py`/`autoclassify.py` are earlier/partial attempts).

## Netlister picks HDL language from the view's MASTER FILE (master.tag 2nd line)
- `verilog.v` → plain Verilog-2001 (SV/nettype/wreal keywords REJECTED, *E,EXPMPA/EXPSMC)
- `verilog.vams` → Verilog-AMS (`wreal` OK) — legacy path
- `verilog.sv` → SystemVerilog (`EEnet` nettype OK) — **the EEnet leaves use this**

## rnmgen2.py algorithm (what beat 110k TYCMPAT down to 0)
1. Seed exact port types from the leaf `.sv` views (real EEnet leaves only; NOT pixel/col_driver
   which are structural in the netlist unless substituted).
2. A net is `EEnet` iff it touches an `EEnet` port AND NO `logic` port (flag conflict if both).
3. BIDIRECTIONAL propagation — push parent `EEnet` nets DOWN into child ports and up
   (e.g. `vdacd1` EEnet at anatop must reach `array_vh.vdacd1`).
4. De-electrify foundry resistors → ideal short; treat their terminals as `EEnet` (voltage).
5. IGNORE primitives when typing. Declare implicit nets. Inject `import EE_pkg::*;`.
6. Substitute external `.sv` leaves: a netlist module also given as a `.sv` leaf is DROPPED
   from the emit and the behavioral one binds (used for `col_driver`; works for any module).
Output: `cds/rnm/netlist_ee.sv`.

## Leaf type-consistency fixes that were required (else cross-module TYCMPAT)
- `dac_dark` `ibg`/`iti` → `logic` (they are 3-bit digital trim, not analog current).
- `row_drv` `ph_smp*`/`diag_en*` outputs → `logic` (digital controls; match `pixel_hh`).
- Sampling phases & trim codes = `logic`; bias currents/voltages = `EEnet`. The same physical
  net MUST be the same type (and packed-ness) in every module it touches.

## Gotchas
- Run python with `env -u LD_LIBRARY_PATH -u PYTHONHOME python3` (Cadence env breaks system python).
- In EEnet models, use continuous `assign` (NOT `always @(*)`) when reading nettype members.
- Heuristic/regex retyping of the full ~24k-instance netlist FAILS (name-based net classification
  collides across modules); rnmgen2's per-net inference from leaf port types is the correct tool.

## Roles add-on (VERIFIED Jun 2026) — `cds/rnm/ee_roles.sv` + additive rnmgen2 stamping
- A nettype CANNOT be `typedef`'d (xmvlog `*E,NTIINV`). So net "roles" (VDD/GND/bias/
  signal/diff) are NOT types — they are conveyed by NAME + bound assertion checkers over the
  single `EEnet` identity. (Only a distinct, incompatible nettype could be a "role type" → don't.)
- `ee_roles.sv`: scalar checkers `chk_vdd/chk_gnd/chk_bias/chk_diff` (read `.V`, `ee_isval()`
  skips hi-Z `wrealZState`) + bus wrappers `chk_*_bus #(.N())` that genvar-loop the scalar one.
  `tb_roles.sv` PASSES: in-range silent, 2 deliberate violations `$error` correctly.
- `rnmgen2.py` extended ADDITIVELY (does not touch the emitted netlist — verified
  `netlist_ee.sv` byte-identical via diff): classifies each EEnet net by name regex and writes
  `<out>.roles.csv` (module,net,role) + `<out>_roles_bind.sv` (width-aware `bind anatop chk_*`;
  scalar vs `chk_*_bus #(.N(w))` chosen from the net's declared `[a:b]` width).
- GOTCHA: many role nets are 222-wide EEnet buses (e.g. `col_vdd_end[0:221]`) — a scalar
  checker bind → `TYCMPAT`; must use the `_bus` wrapper. Verified: full-chip `anatop`
  elaborates WITH the 16 generated binds (3×222-wide buses + scalars), exit 0, 545,482 resolved
  nets, RNM mode, 0 TYCMPAT. Stamp counts: 146 EEnet nets = 30 VDD/22 GND/20 BIAS_V/6 BIAS_I/8 DIAG/60 signal.
- PER-DOMAIN windows: rnmgen2 stamps VMIN/VMAX into each bind by name (VDD_DOMAINS/BIAS_DOMAINS
  tables, specific-before-generic substring match): vdd/vddl→[0.8,1.0], vddc/vddr/col_vdd→[2.3,2.7],
  vddh→[3.0,3.6], vts*/vcm→[0.4,1.4]; GND uses default TOL. (windows are SPEC-TODO/tunable.)
- WIRED INTO MAKEFILE: ee_roles.sv + netlist_ee_roles_bind.sv added to SRCS (order: EE_pkg→roles→
  leaves→col_driver→netlist_ee→binds→tb); netlist_ee.sv+bind are a real file rule so elab/sim/
  waves/cov auto-regenerate. `make sim` = full RNM with LIVE role assertions, ALL 11 checks PASS, exit 0.

See [[anatop-rnm-project]], [[anatop-rnm-build-run]].
