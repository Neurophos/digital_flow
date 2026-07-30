---
name: firmware-tbctrl
description: Build Cortex-M4F firmware tests (msic_tests) and drive TB stimulus from firmware via the tb_ctrl command protocol. Use when writing a firmware test or injecting agent stimulus (FabIO/GPIO/UART) on a firmware request.
---

# firmware-tbctrl

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
`firmware/msic_tests/<test>/` (`make all` -> gcc/ + verilog/ hex), `firmware/msic_tests/common/` (retarget, uart_stdout, tb_ctrl, msic_functions), `firmware/msic_tests/common/include/tb_ctrl.h` (TB_REGS 0x40007000, offsets), CMSDK headers. tb_ctrl: write ADDR/DATA_OUT/DEBUG0 then a magic CTRL to dispatch; poll STATUS for blocking cmds. stdout=UART1 in HSTM (CTRL=0x41); EOT 0x04 ends sim.
