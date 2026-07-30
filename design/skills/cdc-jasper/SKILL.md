---
name: cdc-jasper
description: Run Jasper CDC/RDC analysis (make jcdc) on Neurophos RTL and interpret crossings. Use when verifying clock/reset-domain crossings (e.g. hclk<->dac_clk, FabIO C2T).
---

# cdc-jasper

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
`make jcdc` / `jcdc_gui` targets, `doc/msic_methodology.md` (Jasper CDC/RDC section). NOTE: jcdc may fail to elaborate blocks with missing macro black-boxes (SRAM/AnaTop) — restore black-boxes so real crossings (e.g. the dac command CDC) are tool-checked.
