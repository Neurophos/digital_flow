---
name: synthesis-impl
description: Run digital implementation for a Neurophos SoC — Genus synthesis (logical/physical/elab), constraints, and the LEC / physical-verification checks. Use when synthesizing a block or running back-end.
---

# synthesis-impl

## When to use
Synthesizing a block (`cpuss`, `digital_top`, `reset_ctrl`, `chip_top`); refreshing
constraints; running LEC equivalence or physical verification.

## Flow
Per-block dirs under `impl/<block>/` with a `Makefile` that includes
`impl/Makefile.impl` (`SYN ?= genus -wait 3600`). Typical sequence:
```bash
cd impl/<block>
make populate_syn_build     # stage genus tcl (from proj_utils/blocks/<top> or default) + defs
make run_syn_elab           # elaborate
make run_syn_logical        # logical synthesis
make run_syn_physical       # physical (placement-aware) synthesis
make launch_genus           # interactive Genus
make run_syn_reload         # reload a prior run's db
```
Constraints live in `impl/constraints/` — `<block>.sdc` (and `msic_top.pysdc`
preprocessed to `.sdc` via prepro). RTL comes from the synthesis manifest
(`alchemy ... -syn syn.f`); library/corner setup via `alchemy ... -mmmc mmmc.tcl`
and `-lef`.

## Checks
- **LEC** (Conformal) — RTL↔netlist logical equivalence after synthesis.
- **Physical verification** — DRC/LVS class checks.
- See `doc/msic_methodology.md` (Synthesis / Constraints / LEC / Physical
  Verification) for the sign-off definition of each.

## Gotchas
- Genus scripts are staged per-top from `proj_utils/blocks/<top>/scripts/genus/`
  (falling back to `default/`) + `common/scripts/genus/` — edit the staged copy or
  the source, not the build copy that `populate_syn_build` overwrites.
- Constraints for a generated top (`msic_top`) come from a `.pysdc` — regenerate
  via prepro, don't hand-edit the `.sdc`.
- Synthesis consumes the *synthesis* filelist (`*_syn_only` in, `*_sim_only` out) —
  distinct from the sim filelist; regenerate with `alchemy -syn`.

## Bundled here (self-contained — no external workspace paths)

  - `references/examples/digital_top.sdc`
  - `references/examples/msic_top.pysdc`
  - `references/msic_methodology.md`
  - `scripts/Makefile.example`
  - `scripts/Makefile.impl`

## Provenance
Distilled from the Neurophos MSIC digital flow; the bundled `references/`
and `scripts/` are snapshots — regenerate against the live source if the
flow evolves. Command paths in the body (e.g. `verif/uvm/`, `design/<blk>/`)
are the *consuming project's* conventional layout, not this repo.
