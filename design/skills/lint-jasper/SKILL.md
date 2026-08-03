---
name: lint-jasper
description: Run Jasper SuperLint (make slint) on Neurophos RTL and triage results. Use before merging RTL or when chasing structural/lint issues.
---

# lint-jasper

## When to use
Before merging an RTL change; after an RTL fix (confirm `Errors = 0`); chasing a
structural issue (undriven/multi-driven nets, width mismatch, inferred latch).

## Flow
Run in the module `rtl/` dir. `make slint` builds the Jasper filelist (via
`alchemy`), then runs JasperGold SuperLint from `Makefile.rtl`:
```bash
make slint          # batch: cd $JASPER_RUN_DIR; jg $SL_RUN_CMD_OPTS
make slint_gui      # interactive / reload the existing database
```
The lint policy/setup is `utils/chip_utils/scripts/lint/base_lint_run.tcl`
(reload via `sl_reload.tcl`). Logs land under the Jasper run dir.

## Gotchas
- Fix to **`Errors = 0`** before merge; treat waivable warnings deliberately (a
  real RTL bug — e.g. an undriven `hw2reg.*.de` driving a subreg enable to X — can
  hide as a lint warning).
- SuperLint needs the same generated `.sv` + regs the sim uses — run `make prepro`
  / `build_regs` first so it lints the real elaborated design, not stale sources.

## Bundled here (self-contained — no external workspace paths)

  - `references/Makefile.rtl`
  - `references/msic_methodology.md`
  - `scripts/base_lint_run.tcl`
  - `scripts/sl_reload.tcl`

## Provenance
Distilled from the Neurophos MSIC digital flow; the bundled `references/`
and `scripts/` are snapshots — regenerate against the live source if the
flow evolves. Command paths in the body (e.g. `verif/uvm/`, `design/<blk>/`)
are the *consuming project's* conventional layout, not this repo.
