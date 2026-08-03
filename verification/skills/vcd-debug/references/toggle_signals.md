# msic_top Toggle Coverage — Signal Classification

> Report: merged 63-test regression, 2026-06-29  
> IMC source: `verif/uvm/scratch/cov_report/full/`  
> Exclusions file: `verif/uvm/cov_exclusions.tcl`  
> Stats: 1,990 zero-coverage bins · 53,300 total non-n/a bins

---

## Summary

| Category | Verdict | Key modules | Avg coverage |
|---|---|---|---|
| ARM Cortex-M4 Core Internals | **EXCLUDE** | CORTEXM4, CM4ETM, DAP* | ~12% |
| AnaTop / Analog Domain | **EXCLUDE** | AnaTop, AnaTop_beh | ~0–1% |
| PLL (PLLTS22ULPHVFRACB) | **EXCLUDE** | PLLTS22ULPHVFRACB and subcells | ~13% |
| DAC Controller | **EXCLUDE data path / COVER APB** | dac_ctrl, dac_ctrl_half, dac_rams | ~1% |
| SPI Host | **COVER** | spi_host, spi_host_fsm, AHB_TL_bridge | ~17% |
| Clock / Reset / Chip Control | **COVER** | clock_ctrl, reset_ctrl, chip_ctrl | ~25% avg |
| FabIO Target | **WELL COVERED** | fabio_tgt, fabio_tgt_reg_top | ~53% |
| UART | **COVER** | cmsdk_apb_uart | 61.8% |
| Pad-Ring Standard-Cell Primitives | **EXCLUDE** | Xinvrst_*, Xndrst_*, Xinv*, Xnand* | ~0% |
| DFT / Analog Pads / Error Stubs | **DONE** | see cov_exclusions.tcl | — |

---

## EXCLUDE — ARM Cortex-M4 Core Internals

### Affected modules

| Module | Coverage |
|---|---|
| CORTEXM4 | 20.1% |
| CORTEXM4INTEGRATION | 12.1% |
| CM4ETM | 8.4% |
| DAPJtagDpProtocol | 37.8% |
| DAPSWJDP | 2.0% |
| DAPSwDpProtocol | ~20% |
| DAPSwjWatcher | ~17% |
| cm4_fpu_* subcells | <5% |
| cm4_dpu_alu_srtdiv | <5% |
| cm4_mpu_maskgen | <5% |

### Why signals are stuck

ARM ships CORTEXM4 as a proprietary undisclosed (UD) model. Internal micro-architectural state is opaque in RTL simulation. The UD model exposes only AHB master ports and a subset of debug connections; pipeline, FPU, MPU, and ETM signals are either tied off or driven by opaque logic.

- **CORTEXM4 / INTEGRATION**: The 20% covered comes from AHB bus transactions crossing the boundary. Internal pipeline never toggles in RTL sim.
- **CM4ETM**: Embedded Trace Macrocell requires ETM triggers (TPIU, trace sink enable, CoreSight configuration). Never activated in digital sim.
- **DAPJtagDpProtocol**: 37.8% comes from IDCODE and BYPASS scans exercised by JTAG tests. DPACC returns ACK≠OK on ARM_UD_MODEL, so APACC path is never reached.
- **DAPSWJDP / DAPSwDpProtocol / DAPSwjWatcher**: Serial Wire Debug protocol. UVM testbench implements JTAG only; SWD is not connected.
- **cm4_fpu_* / cm4_dpu_alu_srtdiv / cm4_mpu_maskgen**: ARM UD model internal subcells. Not exercisable via any RTL simulation stimulus.

### Action — add to cov_exclusions.tcl

```tcl
# ARM Cortex-M4 proprietary UD model — internal micro-arch not observable in RTL sim
exclude -toggle -du CORTEXM4             -comment "ARM proprietary UD model: internal state opaque"
exclude -toggle -du CORTEXM4INTEGRATION  -comment "ARM proprietary UD model: wraps CORTEXM4, same constraint"
exclude -toggle -du CM4ETM               -comment "Embedded Trace Macrocell: no ETM triggers in digital sim"
exclude -toggle -du DAPJtagDpProtocol    -comment "ARM DAP JTAG-DP: DPACC degrades on UD model; APACC unreachable"
exclude -toggle -du DAPSWJDP             -comment "ARM SWD Debug Port: SWD not wired in UVM JTAG agent"
exclude -toggle -du DAPSwDpProtocol      -comment "ARM SWD protocol block: SWD path not exercised"
exclude -toggle -du DAPSwjWatcher        -comment "SWJ mode-select watcher: SWD not used"
```

For ARM FPU / MPU / divide subcells (verify exact hierarchy in IMC before committing):

```tcl
exclude -toggle -scope {*u_cortexm4*/u_cm4_fpu*}          -comment "ARM FPU internals: UD model opaque"
exclude -toggle -scope {*u_cortexm4*/u_cm4_dpu_alu_srtdiv} -comment "ARM divide/sqrt: UD model opaque"
exclude -toggle -scope {*u_cortexm4*/u_cm4_mpu_maskgen}    -comment "ARM MPU mask generator: UD model opaque"
```

---

## EXCLUDE — AnaTop / Analog Domain

### Affected modules

| Module | Coverage | Bins |
|---|---|---|
| AnaTop | 0.0% | 7,630 |
| AnaTop_beh | 0.8% | — |
| AnaTop_DV_interface | ~0% | — |

### Why signals are stuck

`AnaTop` contains all analog circuitry: PLL, DAC sigma-delta, ADC, pad drivers, and mixed-signal interface cells. In the digital UVM testbench, `AnaTop` is **not instantiated** — it is replaced by `AnaTop_beh`, a behavioral stub that only provides the minimal signals needed to keep digital logic out of X-state.

`AnaTop_beh` covers only 0.8% because the analog model drives signals statically (clock + reset connections only). No analog input stimulus is applied in digital simulation.

### Action — add to cov_exclusions.tcl

```tcl
# AnaTop: analog domain not instantiated in digital UVM sim
exclude -toggle -du AnaTop              -comment "Analog top: not instantiated, replaced by AnaTop_beh stub"
exclude -toggle -du AnaTop_beh          -comment "Analog behavioral stub: only static clock/reset connections"
exclude -toggle -du AnaTop_DV_interface -comment "Analog DV interface: no analog stimulation in digital sim"
```

---

## EXCLUDE — PLL (PLLTS22ULPHVFRACB)

### Affected modules

| Module | Coverage |
|---|---|
| PLLTS22ULPHVFRACB | 13.0% |
| pllts22ulphvfracb_dsp | ~0% |
| pllts22ulphvfracb_sddiv | ~0% |
| pllts22ulphvfracb_sdmod | ~0% |

### Why signals are stuck

`PLLTS22ULPHVFRACB` is a TSMC hard IP macro. In RTL digital simulation it is replaced by a behavioral clock generator — the sigma-delta modulator, DSP core, and fractional divider logic never receive meaningful stimulus. The 13% top-level coverage comes from clock enable and reset connections exercised during simulation startup.

PLL characterization is performed in analog/mixed-signal simulation (Spectre/ADE), not RTL digital sim.

### Action — add to cov_exclusions.tcl

```tcl
# TSMC PLL hard macro: characterized in analog sim, not RTL digital sim
exclude -toggle -du PLLTS22ULPHVFRACB  -comment "TSMC PLL hard macro: analog sim target, not RTL sim"
```

---

## EXCLUDE data path / COVER APB regs — DAC Controller

### Affected modules

| Module | Coverage | Clock domain |
|---|---|---|
| dac_ctrl | 0.4% | APB (pclk) + dac_clk |
| dac_ctrl_half | 1.2% | dac_clk |
| dac_rams | 2.3% | dac_clk |

### Why signals are stuck

The DAC controller has two clock domains:

- **APB domain (`pclk`)**: configuration registers — fully reachable in digital sim
- **dac_clk domain**: sigma-delta output, DAC SRAM read path — requires `dac_clk` from PLL

Since the PLL does not lock in digital simulation, `dac_clk` is never active. All `dac_clk`-synchronous logic in `dac_ctrl_half` and `dac_rams` is permanently stuck. Note: `fabio_burst_read_dac_sram_test` and `fabio_write_dac_sram_test` write to DAC SRAM via FabIO (bypassing `dac_clk` for writes), but the DAC read path is still gated by `dac_clk` synchronizers.

### Action — COVER: add dac_reg_access_test

Create `firmware/msic_tests/dac_reg_access_test/`. Key behavior:

```c
// Walk all DAC APB registers (base: 0x40030000).
// Exercises: register decode, write-enable paths, read-back — all on pclk domain.
// Do NOT enable dac_clk or depend on the sigma-delta output.
#define DAC_CTRL_BASE  0x40030000u

// Write non-default values to each writable register, read back, verify.
// The dac_ctrl APB interface runs independently of dac_clk.
```

Add to regression: `NOFW=0 FIRMWARE_TESTNAME=dac_reg_access_test` in `run_regression.sh`.

### Action — EXCLUDE: dac_clk domain

```tcl
# dac_clk domain: PLL output not active in digital sim
# APB-domain signals in dac_ctrl are left UN-excluded — covered by dac_reg_access_test
exclude -toggle -du dac_ctrl_half  -comment "dac_clk domain: PLL not active in digital sim"
exclude -toggle -du dac_rams       -comment "dac_clk SRAM: PLL not active in digital sim"
```

For `dac_clk`-domain flops inside `dac_ctrl` itself (verify exact scope in IMC):

```tcl
exclude -toggle -scope {msic_top.u_digital_top.u_dac_ctrl.*_q_dac} \
    -comment "dac_clk register in dac_ctrl: PLL not active"
```

---

## COVER — SPI Host

### Affected modules

| Module | Coverage |
|---|---|
| spi_host | 20.4% |
| spi_host_fsm | 13.7% |
| spi_host_core | 17.7% |
| AHB_TileLinkUL_Same_Size_Bridge | 9.2% |

### Why coverage is low

Only one SPI test exists (`spi_error_interrupt_test`), which exercises only the error path. The main command FSM (IDLE → CMD → ADDR → DUMMY → DATA → DONE), FIFO management, QSPI mode, and DMA are uncovered. `AHB_TileLinkUL_Same_Size_Bridge` is the bus bridge between the OpenTitan SPI host TileLink interface and the chip AHB bus — it improves proportionally with SPI host transaction volume.

### Tests to add

**spi_flash_read_test** (firmware)  
Issue a standard SPI read (`0x03`). Covers: IDLE→CMD→ADDR→DATA FSM states, RX FIFO fill, completion interrupt.

**spi_flash_quad_read_test** (firmware)  
Enable QSPI mode (`0xEB`), read data over 4 lines. Covers: quad-mode state machine, QSPI control register writes, data-phase QPI branches.

**spi_flash_write_test** (firmware)  
Sequence: Write Enable Latch (WEL) → Page Program → BUSY poll. Covers: TX FIFO drain, write-command FSM states in `spi_host_core`.

**spi_dma_test** (firmware)  
Configure SPI host DMA to burst-read flash → SRAM. Covers: AHB master burst path through `AHB_TileLinkUL_Same_Size_Bridge`, DMA control registers.

---

## COVER — Clock / Reset / Chip Control

### Affected modules

| Module | Coverage | Bins |
|---|---|---|
| clock_ctrl | 7.9% | 22 / 278 |
| reset_ctrl | 54.2% | 13 / 24 |
| chip_ctrl | 12.1% | 35 / 289 |

### Why coverage is low

These modules are configuration-register-heavy. Most uncovered bins are control register bits sitting at reset default throughout simulation — peripheral clock enables, clock gating controls, clock mux selects, pad drive strength, chip ID, IO configuration. `reset_ctrl` is already at 54% because the reset sequence is exercised; the missing 46% is the soft-reset path and reset-cause register readback.

### Tests to add

**clock_ctrl_reg_test** (firmware)  
Enumerate `clock_ctrl` registers (check design base address). Enable/disable peripheral clocks, exercise gating controls, verify clock mux select bits. Key registers: `clkgaten` (per-peripheral gate), `clkdiven` (divider enable), `clkmuxsel`.

**chip_ctrl_reg_test** (firmware)  
Walk all `chip_ctrl` writable registers. Write non-default values, read back ID/version registers. Expected to lift `chip_ctrl` from 12% to ~40–50%.

**soft_reset_test** (firmware)  
Trigger a system soft reset via `reset_ctrl`. Read and verify reset-cause register after restart. Covers the soft-reset path currently missing from `reset_ctrl`.

---

## WELL COVERED — FabIO Target

### Affected modules

| Module | Coverage |
|---|---|
| fabio_tgt | 59.8% |
| fabio_tgt_reg_top | 46.8% |
| fabio_pkg (functional) | **27/27 = 100%** |

### Status

FabIO is the best-covered digital peripheral. The UVM test suite (35+ tests including random traffic, VIO injection, burst sequences) exercises all transaction types, burst modes, VIO signaling, and error injection. Functional coverage is at 100% as of the `_classify_target` fix (commit `2cd42f07`).

The remaining 40% toggle gap in `fabio_tgt_reg_top` is primarily:
- Read-only status register bits hardwired to 0/1 by design
- Interrupt-clear-on-write bits with narrow toggle windows
- Reserved fields

### Optional improvement

After verifying which `fabio_tgt_reg_top` bits are structurally constant, add targeted exclusions:

```tcl
# FabIO reserved/read-only bits — verify field names in IMC before committing
# exclude -toggle -scope {msic_top.u_digital_top.u_fabio_tgt.u_reg_top.*_reserved*}
#     -comment "Reserved register fields: hardwired 0"
```

---

## COVER — UART

### Affected modules

| Module | Coverage | Bins |
|---|---|---|
| cmsdk_apb_uart | 61.8% | 323 / 523 |

### Why coverage is not higher

`uart_rx_toggle_test` covers basic TX/RX data paths and reaches 62%. Missing paths: RX loopback mode (no external GPIO driver needed), framing error detection (stop-bit mismatch), RX FIFO overflow, baud rate divisor change at runtime.

### Tests to add

**uart_loopback_test** (firmware)  
Enable UART loopback mode (`UART_LCR` loopback bit). Transmit data, verify received data matches — no GPIO wiring to TB required. Target: RX data path signals currently untouched because the external GPIO pad has no persistent driver.

**uart_overflow_test** (firmware)  
Disable RX interrupt handling, send enough bytes to fill RX FIFO, send one more → verify overflow flag set and cleared. Target: overflow detection logic and RX FIFO status bits.

---

## EXCLUDE — Pad-Ring Standard-Cell Primitives

### Affected modules

| Module | Coverage |
|---|---|
| Xinvrst_* variants | 0% |
| Xndrst_* variants | 0% |
| Xinvx1cstm | 0% |
| Xnand2x1cstm | 0% |

### Why signals are stuck

These are gate-level structural cells from the pad ring netlist (`verif/model/netlist/anatop_nl/netlist/`). They implement inverters, buffers, and NAND gates at the standard-cell library level — they are implementation artifacts of `pad_top`, not RTL design intent signals.

`pad_top` mixes RTL and gate-level netlist (the pad ring from AnaTop). Toggle coverage on these cells has no verification value: what matters is toggle at the RTL-level pad ports above them. Excluding these also avoids coverage percentage dilution from thousands of structurally constant standard-cell internal nodes.

### Action — add to cov_exclusions.tcl

```tcl
# Pad-ring gate-level standard cells: structural implementation of pad_top
# Coverage intent is at RTL pad ports above these cells
exclude -toggle -du Xinvrst_*    -comment "Pad-ring gate-level inverter: structural, no RTL coverage value"
exclude -toggle -du Xndrst_*     -comment "Pad-ring gate-level N-driver: structural"
exclude -toggle -du Xinvx1cstm   -comment "Custom std-cell inverter from pad-ring netlist"
exclude -toggle -du Xnand2x1cstm -comment "Custom std-cell NAND2 from pad-ring netlist"
```

---

## DONE — Already in cov_exclusions.tcl

The following are already excluded in `verif/uvm/cov_exclusions.tcl` (commit `1c9c5e2e`). No action required.

| Pattern | Reason |
|---|---|
| `*/scan_en` | DFT scan enable — hardwired 0 in functional sim |
| `*/scan_mode` | DFT scan mode — hardwired 0 |
| `*/dft_rst_disable` | DFT reset override — hardwired 0 |
| `*/arm_cgbypass` | ARM clock-gate bypass — hardwired 0 |
| `*/arm_rstbypass` | ARM reset bypass — hardwired 0 |
| `*/boot_mode*` | Boot mode pad — tied low in TB |
| `*/jtrstn*` | JTAG TRST_N — never asserted; TAP reset via TMS sequence |
| `${DUT}/clk_out_pad` | Clock output pad — output-only, no TB receiver |
| `*/anatst_*` (×8) | Analog test pads — AnaTop not instantiated |
| `*/cm_drv_*` (×4) | Common-mode drive pads — AnaTop not instantiated |
| `*/vts_avg_*` (×2) | VTS average pads — AnaTop not instantiated |
| `*/vhctrl_*` (×2) | VH control pads — AnaTop not instantiated |
| FabIO error stubs | `cmd_err`, `protocol_err`, `ahb_bus_hang`, `fabio_if_hang`, `irpt_error_d`, `irpt_error_vec` — not wired in TB |

---

## Applying Exclusions

All new exclusions go in `verif/uvm/cov_exclusions.tcl`. After adding:

```bash
cd verif/uvm
make cov_merge                           # re-merge if database changed
make cov_report REPORT_TEST=merged       # regenerate report
```

In IMC, excluded bins show as `X` (excluded) rather than `0` (uncovered). Verify each new `-du` or `-scope` pattern resolves to at least one bin before committing — IMC will silently do nothing if the pattern matches nothing.

## New tests — implementation checklist

| Test | Type | Expected lift |
|---|---|---|
| `dac_reg_access_test` | firmware | dac_ctrl APB path: ~0.4% → ~15% |
| `spi_flash_read_test` | firmware | spi_host: ~20% → ~35% |
| `spi_flash_quad_read_test` | firmware | spi_host: +5–8% |
| `spi_flash_write_test` | firmware | spi_host_core TX path: +5–8% |
| `spi_dma_test` | firmware | AHB_TL_bridge: ~9% → ~30% |
| `clock_ctrl_reg_test` | firmware | clock_ctrl: ~8% → ~40% |
| `chip_ctrl_reg_test` | firmware | chip_ctrl: ~12% → ~45% |
| `soft_reset_test` | firmware | reset_ctrl: ~54% → ~75% |
| `uart_loopback_test` | firmware | cmsdk_apb_uart: ~62% → ~75% |
| `uart_overflow_test` | firmware | cmsdk_apb_uart: +3–5% |
