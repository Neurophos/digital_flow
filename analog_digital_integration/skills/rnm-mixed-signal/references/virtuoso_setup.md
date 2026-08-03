# Virtuoso / library setup for the RNM flow

Two workspace files make the RNM flow work inside Virtuoso: `cds_user.lib` (exposes the
precompiled RNM packages) and `.cdsinit_user` (loads the authoring bindkeys at startup).
Both live in the cds workspace (e.g. `/projects/msic/msic_a0/users/robson/wksp1/cds/`) and
are picked up automatically — `prj_cds.lib` does `SOFTINCLUDE $STPRJ_W_PRJ_CDS/cds_user.lib`,
and the project `.cdsinit` chain loads `.cdsinit_user`. See `setup/` for copy-paste fragments.

## 1. RNM packages — `cds_user.lib`

```tcl
# Cadence native RNM packages (EE_pkg / cds_rnm_pkg), precompiled
DEFINE dmsLib /tools/cadence/xcelium/25.09.001/tools/affirma_ams/etc/dms/dmsLib
```

`dmsLib` is the **precompiled** Cadence DMS library. Defining it in `cds_user.lib` gives the
AMS netlister/elaborator a **single, shared type identity** for the RNM nettypes, which is
exactly what lets `EEnet` leaf views connect across the hierarchy (a home-grown nettype hits
`NOPBIND`/`DUPIDN`/`TYCMPAT` because each per-view compile makes a distinct type). It provides:

| package | what it gives | use |
|---------|---------------|-----|
| **`EE_pkg`** | `EEnet` = `nettype struct {real V, I, R}` with `res_EE()` Thevenin/Norton KCL resolution (R=0 ⇒ ideal V source; >1 ideal V ⇒ X conflict; current sum; Z when undriven) | **the discipline this flow uses** — analog nets; drive `'{V:v,I:0,R:r}` (R=0 ideal), `'{V:`wrealZState,I:i,R:`wrealZState}` (current), all-Z = hi-Z; read `net.V` |
| `cds_rnm_pkg` | scalar `wreal` nettypes: `wreal1driver`, `wrealsum` (current/Kirchhoff), `wrealavg`, `wrealmin`, `wrealmax` | legacy / alternative scalar real nets (voltage-only). Not used by this flow. |

Leaf functional views simply `import EE_pkg::*;` and use `EEnet` ports. The package is **not**
auto-included by the AMS flow — the `dmsLib` define (here) is what makes it resolvable.

## 2. Loading the bindkey — `.cdsinit_user`

```skill
load("/projects/msic/msic_a0/users/robson/wksp1/cds/bindkeys/RMgenRnm.il")  ; F9 edit/gen, F10 dry-run
; load(".../bindkeys/wiretracking.il")   ; optional, unrelated F4/F5 wire tracker
```

`RMgenRnm.il` binds **F9** (open the GUI to create/edit a cell's `functional` `verilog.sv`) and
**F10** (dry-run to CIW). Point its globals at your deployment before loading (top of the file):

```skill
RMrnmPython   = "/usr/bin/python3.12"     ; needs tkinter; system py3.6 won't work
RMrnmPyScript = ".../bindkeys/rnm_editor.py"   ; path to the GUI script
```

> Canonical copies of `RMgenRnm.il` / `rnm_editor.py` live in this repo under
> `tools/bindkeys/`. Deploy by either loading them from there in `.cdsinit_user`, or copying
> them into your workspace `bindkeys/` and loading that path. Restart Virtuoso (or
> `load()` the file in the CIW) to pick up changes.

## Deploy checklist
1. `cds_user.lib`: add the `DEFINE dmsLib …` line (section 1).
2. `.cdsinit_user`: add the `load(".../RMgenRnm.il")` line; set `RMrnmPython` / `RMrnmPyScript`.
3. Restart Virtuoso → F9 in a schematic opens the RNM editor (see `virtuoso_bindkeys.md`).
