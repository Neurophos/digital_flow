---
name: firmware-tbctrl
description: Build Cortex-M4F firmware tests (msic_tests) and drive TB stimulus from firmware via the tb_ctrl command protocol. Use when writing a firmware test or injecting agent stimulus (FabIO/GPIO/UART) on a firmware request.
---

# firmware-tbctrl

## When to use
Writing a CPU firmware test; needing the TB to inject stimulus (FabIO C2T, GPIO
readback, UART RX) at a firmware-controlled moment; understanding how a firmware
test starts, prints, and ends the sim.

## Build
Each test is a self-contained project under `firmware/msic_tests/<test>/`:
```bash
cd firmware/msic_tests/<test> && make all
#  -> gcc/<test>.bin        (ELF/binary + .lst/.map)
#  -> verilog/<test>.hex    (SRAM preload, reverse-bytes, VMA adjusted to 0)
#  -> verilog/<test>.arm.bin (32b-per-line, what the TB preloads)
```
Boilerplate: copy the `Makefile` + `.gitignore` (`verilog/`, `gcc/`) from a similar
test; `TESTNAME` auto = dir name; add needed common srcs to `TEST_SRC_CODE`
(`retarget.c`, `uart_stdout.c`, `tb_ctrl.c`, `msic_functions.c`). Register the test:
add a UVM wrapper `verif/uvm/tests/<test>.sv` (extend `msic_cpu_base_test`, set
`firmware_testname`), `` `include `` it in `msic_tb_pkg.sv`, and add it to the
regression runners.

## stdout / completion
`UartStdOutInit()` puts **UART1** in high-speed test mode (`CTRL=0x41`,
`BAUDDIV=16`) for fast `printf`; the TB `cmsdk_uart_capture` watches UART1 TX and
`$finish`es on EOT `0x04` (`UartEndSimulation()`). Register/field access uses the
generated `<peripheral>.h` masks; base addresses in `memio.h`.

## tb_ctrl command protocol (firmware → TB stimulus)
Rendezvous via the `tb_ctrl` APB slave at `TB_REGS_BASE_ADDR = 0x4000_7000`:
```c
MEMUI32(TB_REGS_BASE_ADDR + TB_CTRL_ADDR_OFFSET)     = <addr/channel>;  // 0x08
MEMUI32(TB_REGS_BASE_ADDR + TB_CTRL_DATA_OUT_OFFSET) = <data>;          // 0x0C
MEMUI32(TB_REGS_BASE_ADDR + TB_CTRL_DEBUG0_OFFSET)   = <count/len>;     // 0x18
MEMUI32(TB_REGS_BASE_ADDR + TB_CTRL_CTRL_OFFSET)     = <MAGIC>;         // 0x04 -> dispatch
while (MEMUI32(TB_REGS_BASE_ADDR + TB_CTRL_STATUS_OFFSET) == 0x1);      // 0x14 (blocking cmds)
```
Writing `CTRL` dispatches a `tb_ctrl_cmd` to every subscribed handler; each acts on
its opcode. Existing opcodes: FabIO (in `ctrl[23:16]`, plus `0xA5xxxxxx`), GPIO_BFM
`ctrl[7:0]=0x10`, UART_RX_DRIVE `ctrl[7:0]=0x20`. To add stimulus, add a handler
(see the `uvm-methodology` skill) and pick a free opcode.

## Gotchas
- **The completion check ≠ the firmware's own result.** `evaluate_log` scores PASS
  on the UVM banner + `UVM_ERROR:0`, not on your `** TEST PASSED **`. Print an
  `err_cnt` and check the UART log.
- Injecting on a peripheral UART1 uses (stdout) needs **time-multiplexing** (drop
  stdout, do RX at `BAUDDIV=868`, restore `UartStdOutInit()` to print + EOT).
- DUT UART BAUDDIV must match the TB driver (868 cyc/bit) for RX; write `0`-first
  when toggling reset-1 fields for full coverage (see `coverage-closure`).
- A FabIO posted write returns OKAY even to an inert/unmapped target — read back to
  confirm it landed.

## Bundled here (self-contained — no external workspace paths)

  - `references/examples/tb_ctrl.h`
  - `references/examples/tb_ctrl_slave.sv`
  - `references/examples/uart_cmd_handler.sv`
  - `references/examples/uart_rx_inject_seq.sv`
  - `scripts/Makefile.firmware`

## Provenance
Distilled from the Neurophos MSIC digital flow; the bundled `references/`
and `scripts/` are snapshots — regenerate against the live source if the
flow evolves. Command paths in the body (e.g. `verif/uvm/`, `design/<blk>/`)
are the *consuming project's* conventional layout, not this repo.
