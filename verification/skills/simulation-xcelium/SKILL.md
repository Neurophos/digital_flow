---
name: simulation-xcelium
description: Compile and run the Neurophos UVM testbench with Cadence Xcelium (xrun) — filelists, firmware SRAM preload, elaboration snapshot reuse, coverage, and timeout control. Use to run a single test or bring up the sim flow.
---

# simulation-xcelium

> **STATUS: stub** — frontmatter is complete (discoverable); body to be filled
> from the Sources below. Follow the format of the FULL skills
> (verification/skills/coverage-closure, uvm-methodology; analog_digital_integration/skills/rnm-mixed-signal).

## When to use
_TODO_

## Flow (commands)
_TODO — distill the invocation from the Makefile targets / scripts in Sources._

## Gotchas
_TODO — capture the non-obvious failure modes._

## Sources (MSIC)
`verif/uvm/Makefile` (sim/compile/filelist targets), `utils/verif_utils/config/Makefile.{verif,sim.firmware}`, `verif/uvm/scratch/msic_top.f`. Key knobs: `TESTNAME`, `FIRMWARE_TESTNAME`, `COV=1`, `FABIO_NOCLK=1`, `TIMEOUT_NS`, `GUI=1 PROBE=1`. UVM timestamps are ps; the `$finish at time N NS` line is real ns.
