---
name: registers-regtool
description: Generate register blocks (reg_top, reg_pkg, C headers, docs) from hjson/IPXACT with regtool/reggen for a Neurophos SoC. Use when adding or changing peripheral registers.
---

# registers-regtool

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
`utils/chip_utils/scripts/regtools/regtool.py` (+ reggen/topgen), `utils/chip_utils/scripts/ipxact2hjson/`, `utils/chip_utils/scripts/build_manifest/build_regs.pl`, `utils/chip_utils/config/Makefile.regtool`, `doc/register_flow.md`, `doc/regtool_README.md`, module `regs/` dirs.
