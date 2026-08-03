---
name: coverage-closure
description: Close UVM code (toggle/block/expr/FSM) coverage on a Neurophos SoC with Cadence IMC/Verisium — merge runs, analyze holes, apply CCF whole-instance and vRefine signal-level exclusions with discipline, and report refined numbers. Use when driving coverage up, deciding what is dead vs a test-gap, or auditing exclusions.
---

# Coverage Closure (Cadence IMC / Verisium)

## When to use
Driving UVM coverage toward closure; deciding whether an uncovered block is a
real test-gap, dead RTL, or a bug; adding/auditing exclusions; producing a
refined coverage number for sign-off.

## Golden rule
**Exclude only *provably-dead* nodes; never mask coverable logic.** A big
"coverage hole" is, more often than not, a real bug or genuinely-dead RTL — not a
missing test. Investigate the RTL before writing a test *or* an exclusion.

## Tool bring-up (do this first in any fresh shell)
IMC needs the Xcelium coverage engine on `MDV_XLM_HOME`. The `make cov_*` targets
handle it via `IMC_LOAD`; for ad-hoc `imc` calls:
```bash
source /usr/share/Modules/init/bash && module load cadence/vmanager/25.09.003
export MDV_XLM_HOME=/tools/cadence/xcelium/25.09.001   # else: *E,coverage_engine_lib.not_found_env
```
IMC merge also consumes an `Xcelium_Single_Core` license — during a busy
regression it can transiently `*E,LICERR`; re-run `make cov_merge` once sims free.

## Flow
1. **Collect** — run sims with `COV=1` (adds `-coverage all -covfile coverage.ccf`).
   Per-test UCD lands in `verif/uvm/scratch/cov_work/scope/<test>/`.
2. **Merge** — `make cov_merge` (or `imc ... merge -out scope/merged <runs>`),
   producing `scope/merged`.
3. **Report** — `make cov_report REPORT_TEST=merged` → HTML at
   `scratch/cov_report/{full,uncovered}/`. This sources `cov_exclusions.tcl`
   which does `load -refinement coverage.vRefine`, so refined numbers are automatic.
4. **Analyze holes** (ad-hoc):
   ```
   imc -execcmd "load -run scratch/cov_work/scope/merged; \
     report -summary -metrics toggle -inst <path>; \
     report -detail  -metrics toggle <path>; exit"
   ```
   Rank blocks by **absolute uncovered nodes**, not %. Group uncovered signals to
   see the shape (register bits vs datapath width vs dead tie-offs).

## Two exclusion mechanisms — pick correctly
- **CCF** (`coverage.ccf`, elaboration-time, whole-instance): for dead/vendor
  *instances*. `deselect_coverage -all -instance /msic_top_v_tb/u_msic_top/.../u_X...`
  (`...` = include descendants). Used for AnaTop, ARM Cortex-M4 IP, PLL model,
  orphaned bridges.
- **vRefine** (`coverage.vRefine`, report-time, signal-level toggle): for dead
  *signals/ports*. `load -refinement` applies it. `<rule ccType="inst"
  entityName="msic_top/<inst>/<signal>" entityType="toggle" name="exclude" .../>`.
  Naming a **vector root** (no `[N]`) excludes all bits.

## vRefine gotchas (Cadence IMC 25.09)
- `exclude -toggle` on the command line **always fails MSGPTH** — use the
  `load -refinement coverage.vRefine` file instead.
- entityName root is `msic_top/<inst>/<signal>` (UCIS path; `-covdut msic_top`).
- Xcelium **flattens prim_subreg** — register bits live as flat `_qs` nets at the
  `u_reg` level (`chip_ioN_ctrl_gpio_ie_qs`), *not* `reg2hw.<field>.q` dotted paths
  (those NOMATCH). Use the `_qs` flat name.
- IMC flags a stale exclusion loudly: `*E,EREXCE: Excluding covered entity` — if
  you see this, a signal you excluded is now *covered*; **remove the exclusion**
  (it hides real coverage and even depresses the ratio).

## Reading reports (traps)
- `report -detail -metrics toggle` lists **UNCOVERED nodes only** — a signal's
  *absence* from the list means it is covered, not missing. (This misread once
  looked like a broken write-path; it wasn't.)
- Toggle triple in a refined summary is `covered / meaningful-denominator / excluded`.
- Toggle is scored **per-scope, not recursive** — excluding a signal at
  `u_digital_top` does not exclude the same signal inside `u_gpio`.

## Firmware/agent stimulus lessons that unlock coverage
- **Clear-first ordering:** pins/fields that *reset to 1* (e.g. alt-function pad
  `alt_en=1`, active-low `oe_n=1`) only see one edge if you write 1-then-0. Write
  **0 first, then the all-ones pattern** so every field sees both 0→1 and 1→0.
- **Safe input-enable:** enabling a pad input on an undriven pad gives X. Pair
  input-enable with a **pull (pd/pu)** and output-off so the pad resolves to a
  defined level (no X, no toggle-count corruption).
- A big register block is usually a **register walk**, not a BFM problem — writing
  every field of every instance (CPU or FabIO APB writes) closes far more than
  driving pads. Confirm the mux selects are runtime registers before assuming dead.

## Verdict discipline
- **Dead** (exclude): constant driver (`1'b0/1'b1` assign), disconnected IP,
  un-instantiated path, FIXME-tied-off source.
- **Test-gap** (write a test): reachable via registers/sequences.
- **Bug** (fix + document): logic that *should* work but the stimulus proves it
  doesn't (record in the project's `rtl_bugs_found_in_verification.md`).

## Bundled here (self-contained — no external workspace paths)

  - `references/examples/coverage.ccf`
  - `references/examples/coverage.vRefine`
  - `scripts/cov_exclusions.tcl`

## Provenance
Distilled from the Neurophos MSIC digital flow; the bundled `references/`
and `scripts/` are snapshots — regenerate against the live source if the
flow evolves. Command paths in the body (e.g. `verif/uvm/`, `design/<blk>/`)
are the *consuming project's* conventional layout, not this repo.
