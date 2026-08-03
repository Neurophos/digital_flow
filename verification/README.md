Digital verification and emulation flow data and documentation 

## Skills

UVM is split by scope — **system** (top) vs **block** (unit) — plus **formal**:
- `skills/uvm-system-level` — top/system verification: the MSIC digital-top TB
  (`verif/uvm`, tb_ctrl command-handler pattern, scoreboard, pass-criterion) **and**
  the full-chip RNM/mixed-signal env (`verif/model` — AnaTop as a real-number model)
- `skills/uvm-block-level` — block/unit UVM TB pattern (self-contained env, agents,
  scoreboard, coverage; template `design/pf_ed/uvm`)
- `skills/formal-verification` — JasperGold block formal (jg.tcl, SVA property
  taxonomy, CEX-depth reading, the n_-vs-registered pitfall; template `design/pf_ed/formal`)

Supporting:
- `skills/simulation-xcelium` — xrun compile/sim, firmware preload, timeouts
- `skills/regression-parallel` — serial + license-aware parallel runners
- `skills/coverage-closure` — IMC/Verisium merge, ccf + vRefine exclusion discipline, hole analysis
- `skills/firmware-tbctrl` — msic_tests build, CMSDK, tb_ctrl stimulus injection
- `skills/debug-bughunting` — coverage-holes→bugs, waveform probes, failure-masking traps

## Generic assets
- `scripts/cov_exclusions.tcl` — chip-agnostic vRefine loader
- `templates/coverage.vRefine.template` — signal-exclusion file skeleton
