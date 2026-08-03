---
name: uvm-block-level
description: Build and run a block/unit UVM testbench for a Neurophos RTL block, using the pf_ed unit TB as the template — self-contained env (agents/env/scoreboard/sequences/tests), alchemy filelist from the block config, and the same Makefile interface as the top TB. Use when standing up or extending a block-level UVM env. For system/top verification use uvm-system-level; for block formal use formal-verification.
---

# UVM — Block / Unit Level

## When to use
Standing up a UVM unit testbench for a single RTL block; adding an agent,
sequence, or test to an existing block env; closing block-level coverage before
integrating into the top TB. Template: `design/pf_ed/uvm` (Pixel Frame – Embedded
Digital).

## Layout (self-contained, mirrors the top TB at block scope)
```
design/<block>/uvm/
├── Makefile                same interface as the top MSIC UVM TB (make help)
├── common/    <blk>_pkg.sv     geometry / command encodings / params
├── interfaces/ <blk>_clk_rst_if, per-port ifs (e.g. pf_stream_if, pf_dac_if)
├── agents/
│   ├── <active>/   drives the block's primary bus, monitors it
│   └── <passive>/  captures block outputs (no driving)
├── env/        <blk>_env_cfg, <blk>_env
├── scoreboards/ <blk>_scoreboard   reference model: passthrough + functional check
├── sequences/  <blk>_base_vseq + directed/coverage vseqs
├── tests/      <blk>_base_test + directed tests
└── tb/         <blk>_tb_pkg + <blk>_tb_top_{hdl,hvl}.sv  (HDL/HVL split)
```
DUT is the **friendly-pin-name wrapper** (`<block>_wrapper` in the block `rtl/`),
not the raw block — the wrapper gives readable port names to bind interfaces to.

## Run
```bash
cd design/<block>/uvm
make                     # prints help (default)
make sim                 # build + run default test
make sim TESTNAME=<t>    # a specific test
make sim WAVE=1          # + waveforms
make sim COV=1           # + coverage -> make cov_gui / cov_report / cov_excl_report
make filelist            # (re)generate the block filelist
```
The first `sim`/`filelist` runs **Alchemy** on `design/<block>/config/<block>.yaml`
to build the filelist (preprocessing `<block>.pysv` → `.sv`, pulling in shared
`ni_parts`), then adds the wrapper explicitly. Same knobs as the top TB:
`TESTNAME`, `SEED`, `WAVE=1`, `GUI=1`, `PROBE=1`, `COV=1`, `TIMEOUT_NS`.

## Env pattern (from pf_ed)
- **Active agent** drives the block's source-synchronous / bus protocol and
  monitors the passthrough/echo; **passive agent** captures the functional outputs
  (e.g. DAC row values on each `En` strobe).
- **Scoreboard** holds a reference model: it checks both the *transport* invariant
  (stream passes through unchanged) and the *functional* result (a `PGM_START` +
  data beats + `UPDATE` produces the right per-row DAC values).
- **Sequences** layer from a `<blk>_base_vseq`: directed program/readback,
  full-range sweeps, multi-ID, reset-toggle, and a dedicated `<blk>_coverage_vseq`.

## Coverage
Block env has its **own** exclusion files (`<block>_excl.ccf`,
`<block>_excl.tcl`) and `make cov_report` / `cov_excl_report` targets — apply the
same exclusion discipline as the top level (see `coverage-closure`): exclude only
provably-dead nodes.

## Why block-level first
Unit TBs close coverage and catch bugs at short trace depths before the block is
buried in the system TB (where the same bug needs the full protocol to reach).
Pair with **formal** (`formal-verification`) for the same block — the two are
complementary: UVM for datapath/coverage breadth, formal for exhaustive protocol
invariants.

## Bundled here (self-contained — no external workspace paths)

  - `references/examples/Makefile`
  - `references/examples/pf_env.sv`
  - `references/examples/pf_scoreboard.sv`
  - `references/examples/pf_tb_pkg.sv`
  - `references/README.md`

## Provenance
Distilled from the Neurophos MSIC digital flow; the bundled `references/`
and `scripts/` are snapshots — regenerate against the live source if the
flow evolves. Command paths in the body (e.g. `verif/uvm/`, `design/<blk>/`)
are the *consuming project's* conventional layout, not this repo.
