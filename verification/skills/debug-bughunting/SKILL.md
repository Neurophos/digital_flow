---
name: debug-bughunting
description: Root-cause coverage holes and verification failures on Neurophos SoCs — the pattern where a 'coverage hole' is a real RTL bug or dead RTL, plus waveform probes and the traps that mask failures. Use when a block won't cover, a test 'passes' suspiciously, or triaging a finding.
---

# debug-bughunting

## When to use
A block won't reach coverage no matter the stimulus; a test "passes" but you doubt
it exercised anything; a signal reads X or a constant; triaging whether something
is a bug, dead RTL, or a test-gap.

## Core lesson
**A big coverage hole is more often a real bug or dead RTL than a missing test.**
Across the MSIC campaign, 4 of the largest "holes" were: a dead command dispatch,
disabled UART-RX pads, incomplete interrupt RTL, and an unvalidated DAC read path.
**Trace the RTL before writing either a test or an exclusion.** Classify:
- **Dead** (exclude): constant driver, disconnected IP, FIXME tie-off.
- **Test-gap** (write a test): reachable via registers/sequences.
- **Bug** (fix + document in `rtl_bugs_found_in_verification.md`): should work,
  stimulus proves it doesn't.

## Failure-masking traps (these hide real problems)
- **`evaluate_log`** scores PASS on the UVM banner + `UVM_ERROR:0` — a firmware
  `TEST FAILED` (nonzero `err_cnt`) is masked. Check the UART log.
- **Posted writes return OKAY without landing.** A FabIO write to an inert/unmapped
  target passes the scoreboard's resp check but never updated a register. Confirm
  via read-back or coverage, not the OKAY.
- **`report -detail -metrics toggle` lists UNCOVERED nodes only.** A signal's
  *absence* means covered, not missing (this once looked like a broken write-path).
- **A test can silently no-op.** A command decoded on the wrong ctrl byte
  ("Ignoring unrecognised cmd") makes the whole feature dead while the test still
  "passes". Grep the log for the handler actually firing.

## Getting a defined, coverable signal
- **X on an enabled input:** an undriven pad with input-enable set reads X. Pair
  input-enable with a **pull (pd/pu)** + output-off so it resolves defined.
- **Reset-1 fields:** active-low `oe_n`, alt-function `alt_en` reset to 1 → a
  1-then-0 write yields only one edge. **Write 0 first**, then the all-ones pattern.
- **X in an idle FSM state:** a datapath reg captured in a disabled state goes X;
  drive *defined* values (e.g. sweep 0xFF→0x00→0xFF) so toggles count cleanly.

## Waveform probing
- Reusable VCD probe hooks exist behind Makefile knobs (e.g. `DAC_VCD=1`) to dump a
  datapath (SRAM→ram_rdata→DAC) for root-causing; add one rather than eyeballing.
- Run `make sim ... GUI=1 PROBE=1` for interactive Xcelium waves.
- Cross-check timestamps: UVM prints **ps**, the `$finish at time N NS` is real ns.

## Record it
Every confirmed finding → the project's `rtl_bugs_found_in_verification.md`
(area, issue, severity, status, fix commit) and the campaign log
`verif/uvm/verisium_migration.md`. Fix bugs in the `.pysv` source when the `.sv`
is generated.

## Sources (MSIC)
`doc/rtl_bugs_found_in_verification.md`, `verif/uvm/verisium_migration.md`,
`verif/uvm/run_regression.sh` (`evaluate_log`), Makefile VCD probes.
