---
name: simulation-xcelium
description: Compile and run the Neurophos UVM testbench with Cadence Xcelium (xrun) — filelists, firmware SRAM preload, elaboration snapshot reuse, coverage, and timeout control. Use to run a single test or bring up the sim flow.
---

# simulation-xcelium

## When to use
Running one UVM test; bringing up the sim flow; enabling coverage/waves; debugging
a hang or timeout.

## Flow
From `verif/uvm/` (`verif/uvm/Makefile`):
```bash
make sim TESTNAME=<test> FIRMWARE_TESTNAME=<test>      # firmware test
make sim TESTNAME=<test>                                # NOFW test
make compile          # elaborate only
make filelist         # regenerate msic_top.f (via alchemy)
```
Useful knobs (`+plusargs` / defines forwarded by the Makefile):
| Knob | Effect |
|---|---|
| `COV=1` | `-coverage all -covfile coverage.ccf`; UCD → `scratch/cov_work/scope/<test>` |
| `TIMEOUT_NS=<ns>` | watchdog (default 100 ms); bump for slow CDC tests (DAC-SRAM reads ~0.4 ms each) |
| `FABIO_NOCLK=1` | disable the free-running 83 MHz FabIO C2T clock (avoids pad-contention slowdown) |
| `GUI=1 PROBE=1` | Xcelium GUI + waves (then type `run`) |
| `FABIO_ASSERT=1` | enable FabIO SVA |

Outputs: `scratch/simland/<test>/{sim.log,uart.log}`. Firmware is preloaded into
ARM SRAM from `<test>.arm.bin` at elaboration. `xrun` **reuses the elaboration
snapshot** across runs — a rerun that only changes firmware/plusargs is seconds,
not minutes (a TB `.sv` change re-elaborates).

## Gotchas
- **UVM timestamps are ps**; the `Simulation complete ... at time N NS` line is
  the real ns. (A "112 ms" UVM stamp was actually 112 µs.) Don't size timeouts off
  the ps value.
- Run background sims with an explicit `cd verif/uvm && make sim ...` — the sim
  target only exists there; a stray `make sim` from a firmware dir errors
  "No rule to make target 'sim'".
- A transient `*E,LICERR` during a busy window = out of `Xcelium_Single_Core`
  licenses; retry when sims free.
- Coverage merge/report: see the `coverage-closure` skill.

## Sources (MSIC)
`verif/uvm/Makefile`, `utils/verif_utils/config/Makefile.{verif,sim.firmware}`,
`verif/uvm/scratch/msic_top.f`, `verif/uvm/tb/msic_tb_top_{hdl,hvl}.sv`
(`+TIMEOUT_NS`).
