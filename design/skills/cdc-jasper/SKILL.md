---
name: cdc-jasper
description: Run Jasper CDC/RDC analysis (make jcdc) on Neurophos RTL and interpret crossings. Use when verifying clock/reset-domain crossings (e.g. hclk<->dac_clk, FabIO C2T).
---

# cdc-jasper

## When to use
Verifying clock/reset-domain crossings after adding or touching a CDC — e.g. the
`hclk`↔`dac_clk` command/data crossings, the FabIO C2T interface, any
`ni_*_sync*` synchroniser.

## Flow
Run in the module `rtl/` dir; `Makefile.rtl` builds the Jasper filelist (via
`alchemy`) then runs Jasper CDC:
```bash
make jcdc          # batch: cd $JASPER_RUN_DIR; jg -batch $JCDC_RUN_CMD_OPTS
make jcdc_gui      # interactive
```
Reports/violations under the Jasper run dir. Triage each crossing to a real
synchroniser or a waiver.

## Gotchas
- **Missing macro black-boxes block elaboration.** `jcdc` (and lint) can't
  elaborate blocks that instantiate SRAM/ROM macros or AnaTop without their
  black-boxes — restore the black-boxes so real crossings are actually analyzed.
  A known example: the `dac_ctrl` command CDC (`hclk`→`dac_clk`) was a real bug
  (single-pulse `cmd.qe` crossed unsynchronised) that CDC *should* have flagged,
  but the block wouldn't elaborate for `jcdc` due to missing black-boxes — worth
  restoring so that class of bug is tool-caught, not found only in sim.
- CDC needs the generated `.sv` + regs — run `make prepro`/`build_regs` first.

## Bundled here (self-contained — no external workspace paths)

  - `references/Makefile.rtl`
  - `references/msic_methodology.md`

## Provenance
Distilled from the Neurophos MSIC digital flow; the bundled `references/`
and `scripts/` are snapshots — regenerate against the live source if the
flow evolves. Command paths in the body (e.g. `verif/uvm/`, `design/<blk>/`)
are the *consuming project's* conventional layout, not this repo.
