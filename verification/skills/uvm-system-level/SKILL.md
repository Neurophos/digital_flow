---
name: uvm-system-level
description: Structure and extend the Neurophos SoC TOP-LEVEL (system) verification — the MSIC digital-top UVM testbench (verif/uvm) plus the full-chip RNM/mixed-signal environment (verif/model). Covers env/agents/scoreboard, the tb_ctrl firmware↔TB command-handler pattern, NOFW vs firmware tests, the pass-criterion, and how the analog RNM model relates to the digital TB. For a single block's unit TB use uvm-block-level; for block formal use formal-verification.
---

# UVM — System / Top Level

Top-level verification has two environments:
- **`verif/uvm`** — the MSIC **digital-top** UVM testbench (DUT `u_msic_top`; the
  analog is the AnaTop *behavioral* model, CCF-excluded from coverage).
- **`verif/model`** — the **full-chip RNM** environment (AnaTop verified as a
  real-number model, event-driven, with role assertions).

## When to use
Adding a system UVM test/sequence/agent-handler; wiring firmware-driven stimulus;
running or refreshing the full-chip RNM sim; understanding why a test "passes".

---

## A. Digital top TB (`verif/uvm`)

### Shape
- HDL top `msic_top_v_tb` / `msic_tb_top_hdl.sv`: DUT `u_msic_top`, clocks, pad
  wiring, `cmsdk_uart_capture` (watches **UART1 TX**, `$finish` on EOT `0x04`).
- HVL `msic_tb_top_hvl.sv`: global watchdog (`+TIMEOUT_NS`, default 100 ms).
- `msic_env`: agents (`fabio`, `qspi`, `gpio`, `uart`, `tb_ctrl`, `jtag`),
  `msic_scoreboard`, command handlers. Package `verif/uvm/tb/msic_tb_pkg.sv`
  (`` `include `` order matters — handlers/seqs before `msic_env`).

### Test kinds
- **Firmware (CPU)** → extend `msic_cpu_base_test`, set `firmware_testname`; SRAM
  preloaded; vseq holds objection until firmware `$finish`.
- **NOFW** → extend `msic_base_test`, override `_run_test`, drive an agent
  sequencer directly (e.g. FabIO C2T register walk).

### The tb_ctrl command-handler pattern (reusable primitive)
Firmware and TB rendezvous through the `tb_ctrl` APB slave (`0x4000_7000`).
Firmware writes ADDR/DATA/DEBUG0 then a magic `CTRL`; `tb_ctrl_slave.apb_write`
dispatches a `tb_ctrl_cmd` on `command_ap`; **every** subscribed handler sees it
and acts on its own opcode.
- `fabio_cmd_handler` (opcode in `ctrl`), `gpio_bfm_handler` (`ctrl[7:0]=0x10`),
  `uart_cmd_handler` (`ctrl[7:0]=0x20`, injects on `uart_if.rx[ch]`).
- **Add a new injection:** create a handler component (mirror `gpio_bfm_handler`),
  subscribe it to `tb_ctrl_agnt.command_ap` in `msic_env.connect_phase`, give it
  its sequencer, pick an unused opcode byte.
- **Opcode-decode gotcha (a real dead-feature bug):** decode from the *correct*
  byte. The `0xA5A10000` concurrent-write magic encodes its opcode in
  `ctrl[31:24]` while others use `ctrl[23:16]`; a wrong-byte decode silently drops
  the command ("Ignoring unrecognised cmd"). Verify `_dispatch` **and**
  `is_blocking_cmd` decode the same byte firmware writes.

### Scoreboard
`msic_scoreboard` checks FabIO resp_code + a write-tracking `mem_model`.
`0x8xxx_xxxx` unmapped → AHB ERROR tolerated. **A posted FabIO write returns OKAY
even to an inert/unmapped target — OKAY does not prove the register updated;**
confirm via read-back/coverage.

### Pass criterion — READ THIS
`evaluate_log` scores PASS on `grep "TEST PASSED"` (UVM banner) + `UVM_ERROR: 0`.
It does **not** require the firmware's own `** TEST PASSED **` banner — a firmware
test can print `TEST FAILED` and still be scored PASS. Check the UART
`err_cnt`/banner.

### Timing gotchas
- UVM timestamps are **ps**; the `$finish ... at time N NS` line is real ns.
- DUT UART BAUDDIV must match the TB `uart_driver` (868 cyc/bit); interface inits
  `rx='1`. `dac_clk` is forced 10 kHz — DAC-SRAM reads are ~0.4 ms each (bump
  `+TIMEOUT_NS`).

---

## B. Full-chip RNM / mixed-signal (`verif/model`)

Verifies the **analog (AnaTop) as a real-number model** — event-driven, at digital
speed, with live electrical-role assertions. Self-contained via a committed
netlist snapshot (no OA workspace needed to run).

Flow: `runams` (structural OA netlist) → `rnmgen2.py` (per-net EEnet/logic type
inference, retype `wire`→`EEnet`, de-electrify foundry R→short, substitute
behavioral leaves, **stamp net roles**) → `xrun` (pure RNM).

```bash
module load cadence/xcelium/25.09.001
make rnm      # rnmgen2 on the committed netlist snapshot -> build/netlist_ee.sv + role binds
make sim      # full-chip RNM sim with role assertions -> ALL PASS
make cov      # coverage
make netlist  # ONLY to refresh the snapshot from live OA (needs startPrj)
```
- **Discipline:** Cadence native `EE_pkg::EEnet` (not `wreal`/user nettypes).
- **Role checkers** (`src/roles/ee_roles.sv`): bound assertions on stamped net
  roles (`chk_vdd/gnd/bias/diff`) — catch mis-wired power/bias.
- Behavioral leaf models (`src/leaves/*.sv`) are the source of truth; author/edit
  them from Virtuoso via the F9/F10 bindkey.
- The **derivation** of these models (6-phase transistor→RNM) is a separate skill:
  see `analog_digital_integration/skills/rnm-mixed-signal`.

### Relationship
`verif/uvm` runs the AnaTop *behavioral* model (fast, coverage-excluded);
`verif/model` proves the *RNM* against the transistor-level reference. The digital
top TB is where firmware/protocol coverage is closed; the RNM env is where the
analog model's electrical correctness is signed off.

## Sources (MSIC)
`verif/uvm/tb/msic_tb_pkg.sv`, `env/msic_env.sv`,
`env/{fabio_cmd_handler,gpio_bfm_handler,uart_cmd_handler}.sv`,
`agents/tb_ctrl/tb_ctrl_slave.sv`, `scoreboards/msic_scoreboard.sv`,
`tests/msic_{base,cpu_base}_test.sv`, `run_regression.sh` (`evaluate_log`);
`verif/model/{Makefile,README.md}`, `verif/model/tools/rnmgen2.py`,
`verif/model/src/{leaves,roles}/`, `verif/model/tb/tb_anatop.sv`,
`verif/model/doc/EEnet_README.md`.
