---
name: regression-parallel
description: Run the Neurophos UVM regression — serial (run_regression.sh) and license-aware parallel (run_regression_parallel.sh) with sharded scratch dirs. Use to run the full suite, a subset, or with coverage.
---

# regression-parallel

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
`verif/uvm/run_regression.sh`, `verif/uvm/run_regression_parallel.sh` (MAX_LIC cap, per-shard scratch_parN, add_job), `utils/verif_utils/scripts/regress.pl`, `verif/msic_top_v_tb/run_regression.py`. License reality: 7 Xcelium_Single_Core, NO Multi_Core (cap parallelism at ~5). `evaluate_log` scores PASS on the UVM banner + UVM_ERROR:0 (can mask firmware TEST FAILED).
