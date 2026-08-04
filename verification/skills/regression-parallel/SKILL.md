---
name: regression-parallel
description: Run the Neurophos UVM regression — serial (run_regression.sh) and license-aware parallel (run_regression_parallel.sh) with sharded scratch dirs. Use to run the full suite, a subset, or with coverage.
---

# regression-parallel

## When to use
Running the full suite (or a subset) before/after a change; producing a merged
coverage database; validating a shared TB/RTL change didn't regress.

## Prerequisite on a fresh workspace: generate the register RTL
`design/<blk>/regs/rtl/` is **gitignored**, so a new clone has no generated
register RTL and every test fails instantly at compile as `FAIL (no log)` with
`*SE,FILEMIS: ... <blk>_reg_pkg.sv`. Nothing generates it on demand. Do this once
first (details + why in `registers-regtool`):
```bash
for d in $(utils/chip_utils/scripts/alchemy -ws $(pwd) \
             -yaml design/msic_top/config/msic_top.yaml -quiet -regs -); do
    make -C "$d" all
done
```
If a whole run fails uniformly, check for `FILEMIS` in `regr_results/*.log`
**before** suspecting the RTL change under test — a uniform failure is almost
always the environment, not a regression.

## Flow
From `verif/uvm/`:
```bash
./run_regression.sh                       # serial, all tests
./run_regression_parallel.sh COV=1        # 7 workers + coverage (collect + merge)
./run_regression_parallel.sh JOBS=6 COV=1 SUBSET="msic_smoke_test fabio_cr_test"
./run_regression_parallel.sh MAX_LIC=5    # leave headroom when sharing the server
```
Parallel runner: each worker gets an isolated `scratch_parN/` (own worklib, own
elaboration snapshot — no worklib race), `MAX_LIC` caps concurrent licenses.
Register a test by adding it to the `NOFW_TESTS`/`FW_TESTS` arrays (parallel:
`add_job "<name>" "TESTNAME=... FIRMWARE_TESTNAME=..."`). Serial runner has helpers
for special cases:
- `run_test_slow <test> <TIMEOUT_NS>` — tests exceeding the 100 ms default (e.g.
  DAC-SRAM reads at the 10 kHz `dac_clk`).
- `run_test_nofabio <test>` — `FABIO_NOCLK=1` + relaxed criterion (GPIO pad tests).

Results: `regr_results/`, a `REGR_RESULT: N PASS M FAIL ...` line, and the merged
DB at `scratch/cov_work/scope/merged`. On completion:
`make cov_report REPORT_TEST=merged`.

## Gotchas
- **License reality:** 7 `Xcelium_Single_Core`, **no** `Xcelium_Multi_Core` — MCE
  / design-partitioning is unavailable. The runner now defaults to
  `JOBS=MAX_LIC=7`, i.e. the entire pool with **no headroom**; pass `MAX_LIC=5`
  when sharing the server. Check first with
  `lmstat -a -c $CDS_LIC_FILE | grep Xcelium_Single_Core`. A `gh-runner` CI box on
  `cs1` routinely holds a seat. IMC merge also needs a Single_Core license
  (transient `LICERR` during the busy window → re-run `make cov_merge`).
- **The worker cap is computed once, at launch** —
  `min(JOBS, MAX_LIC, currently_free)`. So `JOBS=7` with one seat taken prints
  `Capping workers: requested 7 -> using 6` and proceeds at 6; but a co-tenant who
  releases and re-requests mid-run then queues behind us. Max throughput and being
  a good neighbour are genuinely in tension here — choose deliberately.
- **`evaluate_log` pass criterion:** PASS = `grep "TEST PASSED"` (UVM banner) +
  `UVM_ERROR: 0`. It does **not** require the firmware's own `** TEST PASSED **`
  banner — a firmware test can print `TEST FAILED` and still be scored PASS. When
  validating firmware, check the UART `err_cnt`/banner too.
- A shared TB/RTL change → run the **full** regression (a change to the tb_ctrl
  handler or a generated top-level `.sv` touches every test).
- Wall-clock ≈ 70 min for the full suite (99 tests) at 5–6 workers; a single slow
  test (DAC-SRAM read) is the long pole, so more workers help less than linearly.

## Bundled here (self-contained — no external workspace paths)

  - `scripts/regress.pl`
  - `scripts/run_regression_parallel.sh`
  - `scripts/run_regression.py`
  - `scripts/run_regression.sh`

## Provenance
Distilled from the Neurophos MSIC digital flow; the bundled `references/`
and `scripts/` are snapshots — regenerate against the live source if the
flow evolves. Command paths in the body (e.g. `verif/uvm/`, `design/<blk>/`)
are the *consuming project's* conventional layout, not this repo.
