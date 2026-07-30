---
name: rtl-build-prepro
description: Generate RTL filelists with alchemy and preprocess .pysv->.sv (Python-templated Verilog) for a Neurophos SoC. Use when compiling RTL, adding a module, or regenerating generated .sv (e.g. digital_top pin config, dac_ctrl).
---

# rtl-build-prepro

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
`utils/chip_utils/scripts/alchemy` (filelist/manifest), `prepro` (pysv->sv), `scripts/compile_rtl.pl`, `utils/chip_utils/config/Makefile.rtl`, `doc/python_prepro.md`, `doc/digital_design_flow.md`, module `config/*.yaml`, `common_data/soc_sysinfo/msic_sysinfo.yaml`. NOTE: some generated .sv carry manual edits not in the .pysv (e.g. digital_top CoreSight block) — regenerating drops them; fold manual edits into the .pysv source.
