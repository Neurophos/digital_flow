---
name: xilinx-fpga
description: Xilinx/AMD 7-series FPGA implementation flow (Vivado) — deterministic ball-map → pin CSV → XDC, filelist elaboration, synth/place/route/bitstream, and the shared board↔FPGA pinout contract that feeds the PCB generator. Use to pin, build, or bring up an FPGA on this board family (Spartan-7 XC7S100-2FGGA676I).
---

# xilinx-fpga

## When to use
Assigning FPGA I/O to physical balls, generating the XDC, building a bitstream with Vivado, or
keeping the FPGA pinout in sync with the PCB. The board family uses **AMD Spartan-7
`XC7S100-2FGGA676I`** (FGGA676, 27×27 BGA) for both the dispatcher and DAC FPGAs.

## The ball-map is the single source of truth
FPGA pinout and PCB net names are one contract, generated deterministically so the FPGA XDC and the
board schematic never drift. A `make_<board>_ballmap.py` script:
1. Reads the vendor package pins CSV (`ball, pin_func, is_gp, bank, cfg_spi`).
2. Assigns `clk` → a clock-capable **MRCC** ball; all other user I/O → GP balls in a **fixed signal
   order**, GP balls sorted `(row-letter, column)`. Config-SPI (QSPI boot) balls and dedicated
   JTAG/CCLK/PROG_B/DONE/INIT_B/M[2:0]/CFGBVS balls are **reserved** (not assigned here).
3. Emits `<board>_ballmap.csv` = `ball, port, net` where **`port`** = the RTL/board-top port (→ XDC)
   and **`net`** = the schematic net (→ the PCB generator, see `kicad-pcb-flow`).

Rules that keep it stable:
- **Append new ports last** in the signal order, so existing ball assignments don't shift (additive).
- Cluster timing-critical source-synchronous groups (e.g. an FT601 datapath) into the clock's bank
  so the logic floorplans next to it (short FF↔pad routes).
- The same CSV drives the XDC (`set_property PACKAGE_PIN <ball> [get_ports <port>]` +
  `IOSTANDARD`) and the board's FPGA symbol/nets — change I/O in **one** place.

## Flow (Vivado)
```bash
module load xilinx/vivado/2025.1
# elaborate/synthesize from a filelist (RTL + pkgs), then implement + bitstream:
vivado -mode batch -source build.tcl -tclargs <top> <part>
```
`build.tcl` typically: `read_verilog -sv` the filelist, `read_xdc <board>.xdc`, `synth_design
-top <top> -part xc7s100-2fgga676-2I`, `opt/place/route_design`, `write_bitstream`. For a
functional emulation build (e.g. a `nexys_video` carrier), swap the part/XDC and scale parameters
(e.g. `NCARD`) — keep the RTL identical.

## Gotchas
- **PROVISIONAL ball-map until a real Vivado place run** — the deterministic assignment is a
  starting pinout; a `place_design` on the true top is authoritative (banking/clock/IO-type legality
  may force moves). Re-emit the CSV from the placed result and re-run the PCB generator.
- **Bank/IOSTANDARD legality** — GP balls carry a bank; clock inputs need MRCC/SRCC; differential and
  VREF-referenced standards constrain which balls are usable. The naive row/col sort ignores this —
  Vivado DRC/`place_design` will reject an illegal assignment.
- **Additive edits only** — inserting a port mid-order re-shifts every later ball, churning the XDC
  and the PCB. Append to the end (and note it), then let a place run re-optimize.
- **Config/JTAG/QSPI balls are off-limits** to user I/O — the ball-map must exclude `cfg_spi` and the
  dedicated config balls, or the bitstream/boot breaks.
- Xcelium (not Vivado) is used for RTL simulation here — see the `verification` skills; Vivado is for
  synth/impl/bitstream only.

## Sources
Spartan-7 `XC7S100-2FGGA676I` dispatcher + DAC FPGAs; `make_dispatcher_ballmap.py`-style deterministic
ball assignment feeding both the XDC and the KiCad board generator; Vivado 2025.1 build; nexys_video
emulation carrier.
