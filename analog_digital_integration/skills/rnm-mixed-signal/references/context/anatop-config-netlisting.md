---
name: anatop-config-netlisting
description: How to netlist msic_a0/anatop config with runams and where outputs land
metadata:
  node_type: memory
  type: reference
  originSessionId: 21802111-3f4e-4f5a-acf6-bebb892d3a7f
---

Netlisting `msic_a0 anatop config` uses `runams` (AMS UNL flow drives Xcelium). Run from
`cds/` in a project shell (`startPrj msic msic_a0` provides runams + libs; `make netlist` wraps this):

```
runams -lib msic_a0 -cell anatop -view config -netlist all -rundir ./anatop_nl -cdslib ./cds.lib
```

- Generated top structural netlist = `anatop_nl/netlist/netlist.vams` (`module anatop` + expanded
  sub-blocks array_vh/column/pixel/col_driver), plus `cds_globals.vams`, `userDisciplines.vams`.
- `runams` emits all real nets as plain `wire` — it does NOT retype to EEnet/wreal. The EEnet
  flow therefore post-processes netlist.vams with `rnmgen2.py` (see [[rnmgen2-transformer]]).
- No `verilog.inpfiles` (that's legacy Verilog-XL). AMS UNL filelist =
  `anatop_nl/netlist/.mapi/xcelium.d/run.*/xmvlog.files`; clean lib/cell/view list = `textInputs`.
- Which cells stop at `functional` vs expand to `schematic` is set in the config view and
  changes between regenerations.
- ENV: `cds.lib` INCLUDEs `$STPRJ_PRJ_HOME/setup/prj_cds.lib` (defines msic_a0). The STPRJ_*
  env is set by `startPrj msic msic_a0` (`/tools/bin/prod/latest/startPrj`); it opens a project
  subshell and does NOT persist into a non-interactive tool shell, so runams must run in that shell.

See [[anatop-rnm-project]], [[anatop-rnm-build-run]].
