---
name: uvm-methodology
description: Structure and extend the Neurophos SoC UVM testbench — env/agents/scoreboard, the tb_ctrl firmware↔TB command-handler pattern (FabIO/GPIO/UART injection), NOFW vs firmware tests, and the pass-criterion. Use when adding a UVM test/sequence/agent-handler or wiring firmware-driven stimulus.
---

# UVM Methodology (MSIC top testbench)

## When to use
Adding a UVM test, sequence, or agent command-handler; driving stimulus that
firmware alone can't reach; wiring a new peripheral into the env; understanding
why a test "passes".

## Testbench shape
- HDL top `msic_top_v_tb` / `msic_tb_top_hdl.sv` instantiates DUT `u_msic_top`,
  clocks, pad wiring, and `cmsdk_uart_capture` (watches **UART1 TX**, `$finish`
  on EOT `0x04`).
- HVL `msic_tb_top_hvl.sv` — global timeout watchdog (`+TIMEOUT_NS`, default
  100 ms), UVM run.
- `msic_env`: agents (`fabio`, `qspi`, `gpio`, `uart`, `tb_ctrl`, `jtag`),
  `msic_scoreboard`, and **command handlers** (`fabio_cmd_handler`,
  `gpio_bfm_handler`, `uart_cmd_handler`). Package: `verif/uvm/tb/msic_tb_pkg.sv`
  (`` `include `` order matters — handlers/seqs before `msic_env`).

## Test kinds
- **Firmware (CPU) test** → extend `msic_cpu_base_test`, set `firmware_testname`.
  SRAM is preloaded from the compiled hex; `msic_cpu_test_vseq` holds the
  objection until firmware `$finish` (UART EOT).
- **NOFW test** → extend `msic_base_test`, override `_run_test`, drive an agent
  sequencer directly (e.g. FabIO C2T register walk). No firmware.

## The tb_ctrl command-handler pattern (reusable primitive)
Firmware and the TB rendezvous through the `tb_ctrl` APB slave (`0x4000_7000`).
Firmware writes ADDR/DATA/DEBUG0 then a magic `CTRL`; `tb_ctrl_slave.apb_write`
dispatches a `tb_ctrl_cmd` on `command_ap`; **every** handler subscribed to
`command_ap` sees it and acts on its own opcode (others ignore).

- `fabio_cmd_handler` — opcode in `CTRL`; drives FabIO C2T sequences (single/burst
  wr/rd, VIO, concurrent-write stress). `is_blocking_cmd` raises `STATUS=1` so
  firmware can poll for completion.
- `gpio_bfm_handler` — `CTRL[7:0]==0x10`, samples `gpio_vif` → GPIO_BFM reg.
- `uart_cmd_handler` — `CTRL[7:0]==0x20`, injects serial chars on `uart_if.rx[ch]`
  via `uart_rx_inject_seq` (no TB UART loopback exists, so RX tests need this).

**To add a new firmware-driven injection:** create a handler component (mirror
`gpio_bfm_handler`), subscribe it to `tb_ctrl_agnt.command_ap` in
`msic_env.connect_phase`, give it its sequencer, and pick an unused opcode byte.

### Opcode-decode gotcha (real bug found this way)
Decode the opcode from the **correct byte**. The B4 concurrent-write magic
`0xA5A10000` encodes its opcode in `ctrl[31:24]` (=0xA5) while every other command
uses `ctrl[23:16]`. A decode on the wrong byte silently drops the command
("Ignoring unrecognised cmd") — the whole feature was dead for months. Always
verify the handler *and* `is_blocking_cmd` decode the same byte the firmware writes.

## Scoreboard
`msic_scoreboard` checks FabIO resp_code and a write-tracking `mem_model`.
Address-class helpers gate expectations (e.g. `0x8xxx_xxxx` unmapped → AHB ERROR
tolerated). Posted FabIO writes return OKAY even to unmapped/inert targets — a
write landing OKAY does **not** prove the DUT register updated; confirm via
read-back or coverage.

## Pass criterion — READ THIS
Regression `evaluate_log` scores **PASS** on `grep "TEST PASSED"` (the UVM
`msic_base_test` banner) **+ `UVM_ERROR: 0`**. It does **not** require the
firmware's own `** TEST PASSED **` UART banner. So a firmware test can print
`** TEST FAILED **` and still be scored PASS. When validating firmware, **check
the UART `err_cnt`/banner**, not just the run label.

## Timing gotchas
- UVM prints timestamps in **ps**; the `$finish ... at time N NS` line is the real
  ns. (A "112 ms" UVM stamp was actually 112 µs, etc.)
- DUT UART BAUDDIV must match the TB `uart_driver` bit period (868 cyc/bit @
  100 MHz). The interface inits `rx='1` (idle high) so no false start bit.
- `dac_clk` is forced slow (10 kHz) in the TB — DAC-SRAM reads cross that CDC and
  are ~0.4 ms each; long tests need `+TIMEOUT_NS` bumped (see simulation skill).

## Sources (MSIC)
`verif/uvm/tb/msic_tb_pkg.sv`, `env/msic_env.sv`,
`env/{fabio_cmd_handler,gpio_bfm_handler,uart_cmd_handler}.sv`,
`agents/tb_ctrl/tb_ctrl_slave.sv`, `scoreboards/msic_scoreboard.sv`,
`tests/msic_{base,cpu_base}_test.sv`, `sequences/uart_rx_inject_seq.sv`,
`run_regression.sh` (`evaluate_log`).
