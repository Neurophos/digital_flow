---
name: debug-bughunting
description: Root-cause coverage holes and verification failures on Neurophos SoCs — the pattern where a 'coverage hole' is a real RTL bug or dead RTL, plus waveform probes and the traps that mask failures. Use when a block won't cover, a test 'passes' suspiciously, or triaging a finding.
---

# debug-bughunting

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
`doc/rtl_bugs_found_in_verification.md` (findings register), `verif/uvm/verisium_migration.md` (campaign log). Patterns: coverage-holes-are-often-bugs; evaluate_log masks firmware TEST FAILED; posted FabIO writes OKAY without landing; `report -detail` lists uncovered-only; DAC_VCD/waveform probes for datapath; reset-1 fields need clear-first; safe input-enable via pull.
