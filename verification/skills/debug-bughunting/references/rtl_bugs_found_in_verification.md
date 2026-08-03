# RTL Bugs Found During UVM Verification (branch `rnm-reference-flow`)

Consolidated register of RTL defects and dead/incomplete logic surfaced while
building coverage for the MSIC digital top.  Each entry links to its detailed
write-up.  "Functional" = would misbehave in silicon; "Dead/incomplete" = cannot
function / unreachable, no silicon-behavior bug but not wired as intended.

| # | Area | Issue | Severity | Status | Fix commit |
|---|---|---|---|---|---|
| 1 | `dac_ctrl` | Command trigger CDC (hclk→dac_clk) unsynchronised | Functional | **FIXED** | `0b4c29c6` |
| 2 | `dac_ctrl` | `hw2reg.dac_cmd.cmd.de` / `image_sel.{d,de}` undriven (X) | Functional (X-hazard) | **FIXED** | `0b4c29c6` |
| 3 | `dac_ctrl` | SRAM read-enable never asserted during FSM programming | Functional | **FIXED** | `cabb305b` |
| 4 | `dac_ctrl` | DAC output regs capture X in DC_IDLE (hold semantics?) | Design question | **OPEN** | — |
| 5 | `spi_host` | `u_AHB_to_TL_Bridge` orphaned (TileLink side disconnected) | Dead/incomplete | Excluded | `94ea3a1d` |
| 6 | TB (`fabio_cmd_handler` + `tb_ctrl_slave`) | Concurrent-write stress cmd (`0xA5A10000`) never dispatched — busmatrix arbiters unverified | Verification gap | **FIXED** | _(this branch)_ |
| 7 | `digital_top` pad config (`msic_pin_list.ods`) | UART RX pad input-enable tied low on all 3 UARTs — UART receive non-functional | Functional | **FIXED** | _(this branch)_ |
| 8 | `fabio_tgt` | 5 of 10 interrupt sources hardwired to 0 (`write_op`/`read_op`/`protocol_err`/`fabio_if_hang`/`ahb_bus_hang`) — FIXME "error handling to be installed" | Dead/incomplete | **OPEN** | — |

---

## 1. DAC command trigger CDC — FIXED

`run_command_wr = reg2hw.dac_cmd.cmd.qe` crossed the hclk→dac_clk boundary with no
synchroniser.  `cmd.qe` is a single ~20 ns hclk pulse; the ~10 kHz-class dac_clk FSM
never sampled it, so the programming FSM was stuck in `DC_IDLE` — a DAC program command
did nothing (and a metastability hazard in silicon).
**Fix:** `ni_toggle_pulse_sync2d` pulse synchroniser (one dac_clk pulse per SW write).
FSM state coverage 9% → 91%.
**Detail:** `design/dac_ctrl/doc/dac_cmd_cdc_fix.md`.

## 2. DAC `hw2reg.dac_cmd` write-back undriven — FIXED

`hw2reg.dac_cmd.cmd.de` and `image_sel.{d,de}` were never assigned, driving the
`prim_subreg` hardware-write enable to X.  These are software-written command fields
with no hardware write-back.
**Fix:** tie the hw2reg write inputs off (`.de = 1'b0`), removing the X.  Landed with #1.
**Detail:** `design/dac_ctrl/doc/dac_cmd_cdc_fix.md`.

## 3. DAC SRAM read-enable gap — FIXED

The programming FSM drove the SRAM read *address* (`dac_ctrl_qw_raddr`) but the read
*enable* (`sram_qw_re_n ← tdc_sram_re_n`, `dac_ctrl.sv`) was wired only to the AHB
debug-read path — no `dac_ctrl_st`/programming term.  So the RAM macros never read
during programming: every DAC output register stayed at its reset value.  In silicon a
DAC program command would sweep the FSM and drive garbage/zeros to the metasurface,
not the SRAM image.  (AHB read-back worked, which is why it hid.)
**Fix:** mux the read enable to match the read-address mux —
`sram_qw_re_n_prog = (dac_ctrl_st == DC_IDLE) ? sram_re_n : 1'b0`.
Waveform-verified: SRAM data now flows to all 222 DAC registers (both halves).
`u_dac_ctrl` toggle 1.82% → 91.10%.
**Detail:** `design/dac_ctrl/doc/dac_sram_read_enable_gap.md`.

## 4. DAC output registers capture X in DC_IDLE — OPEN (design question)

With the read disabled in idle, `ramXX_rdata` is X, so the DAC output registers capture
X between programming sweeps.  The module header says mode 0 = "load image, hold until
next command", suggesting the outputs should *hold*.  In practice the analog latches
each row via `row_en` *during* the sweep, so the idle DAC value may be don't-care.  If a
true hold is intended, gate the DAC-register update to capture only during programming.
Needs a design-owner decision on the intended hold semantics — not fixed unilaterally.
**Detail:** `design/dac_ctrl/doc/dac_sram_read_enable_gap.md` (Follow-up).

## 5. SPI host AHB-to-TileLink bridge — orphaned / dead RTL

`u_AHB_to_TL_Bridge` is a leftover from the OpenTitan TileLink→APB port.  Its TileLink
side is physically disconnected: `tl_i` is never assigned, `tl_o` is unused, and the
FIFO windows are tied to `TL_H2D_DEFAULT` (`spi_host.sv`).  Register/FIFO access flows
through the APB path (`u_reg`), so the bridge can never toggle (was 2/382).  Not a
silicon-behavior bug (the block is simply unused), but dead/incomplete RTL that should
either be removed or wired.  Excluded from coverage via `coverage.ccf`.
**Detail:** `verif/uvm/verisium_migration.md` (Step 6).

---

## 6. Concurrent-write bus-contention command never dispatched — FIXED

The B4 bus-contention feature (CPU + FabIO simultaneously targeting one busmatrix
output slave) was **silently non-functional**.  Firmware kicks it with the magic
`0xA5A10000` written to `TB_CTRL.CTRL`, but the opcode is encoded in `ctrl[31:24]`
(`0xA5`) — every *other* command encodes it in `ctrl[23:16]`.  Both decode sites
keyed on `ctrl[23:16]` (= `0xA1` for this value):

- `fabio_cmd_handler._dispatch` → fell through to `default` → "Ignoring unrecognised
  cmd=0xa5a10000"; the 1000 concurrent FabIO writes never ran.
- `tb_ctrl_slave.is_blocking_cmd` → returned 0 → `STATUS` never raised → the
  firmware's completion poll returned immediately, so the CPU never overlapped FabIO.

Net effect: **no test ever generated simultaneous multi-master traffic**, so the
busmatrix output arbiters (`arbM*` / `outputM*`) were never exercised — the
contention-only nodes (`req_port1 & req_port2`, `addr_in_port[1:0]` winner-select,
`active_op1/op2`) sat untoggled.  The existing `fabio_bus_contention_test` masked this:
its firmware printed `TEST FAILED (Error Count = 1)` (because `fabio_location != 999`),
but the regression pass criterion keys on the UVM-level `TEST PASSED` + `UVM_ERROR:0`,
so it was scored PASS.

**Fix:** decode the `0xA5` command from `ctrl[31:24]` (before the `[23:16]` case) in
both `_dispatch` and `is_blocking_cmd`.  After the fix both contention tests dispatch
the 1000 concurrent writes, `STATUS` gates the CPU loop correctly (SRAM test:
`cpu_location==fabio_location==999`; APB test: 667 CPU reads overlap the FabIO stream),
and the arbiter contention signals on both `arbMSRAM` and `arbMAPB` toggle fully.

Not a silicon RTL bug (testbench only), but it left the AHB busmatrix arbiters
unverified.  New `busmatrix_apb_contention_test` adds contention on the APB output
port to complement the (now-working) SRAM-port `fabio_bus_contention_test`.

## 7. UART RX pad input-enable tied low — FIXED

All three UART RX pads have their alternate-function input-enable tied low in the
generated pin config: `assign altfunc_pad_ie[117|119|121] = 1'b0;`
(`digital_top.sv`, for uart0/1/2_rx).  With the pad input buffer disabled, the
core signal `uart*_rx = altfunc_pad2core[n]` is stuck at 0 — a permanent UART
start-bit — so **UART receive is non-functional on every UART**: the RX shift
register only ever loads 0x00, RXBF/RXOR still assert (framing on the stuck-0
line), but no real data is ever received.  Surfaced while building the UART RX
operational tests (uart0/uart2): the DUT received 0x00 for every injected
character while RXOR set as expected.

The value comes from the `alt_ie_val` column of the chip pinout spreadsheet
`common_data/soc_sysinfo/msic_pin_list.ods`, which is 0 for the UART RX pins
(inconsistent with the FabIO input pins, which correctly use ie=1).  An
input-direction pad must enable its input buffer.
**Fix:** force `alt_ie_val = 1'b1` for the UART RX pins in the `dir=="I"` branch
of `design/digital_top/rtl/digital_top.pysv` (regenerated to `.sv`).  The pinout
spreadsheet should also be corrected at source.  After the fix all three RX
phases pass (polled receive, interrupt receive, RX overrun) on uart0 and uart2.
**Verification:** `uart0_rx_test1` / `uart2_rx_test1` (firmware) with the new
`uart_cmd_handler` + `uart_rx_inject_seq`, which inject serial characters on
`uart_if.rx[n]` on a firmware TB_CTRL request (no TB loopback needed).

---

## 8. FabIO tgt interrupt sources hardwired to 0 — OPEN (incomplete RTL)

`fabio_tgt.sv` (lines 279-288) ties 5 of the 10 interrupt sources permanently low
with a `// FIXME - Error handling to be installed` comment:

```
assign fabio_if_hang  = 1'b0;
assign ahb_bus_hang   = 1'b0;
assign protocol_err   = 1'b0;
assign write_op       = 1'b0;
assign read_op        = 1'b0;
```

So `intr.write_op`, `intr.read_op`, `intr.protocol_err`, `intr.fabio_if_hang` and
`intr.ahb_bus_hang` can never fire — no FabIO write/read-started interrupt, no
protocol-error interrupt (the FSM computes `err_code` = 1/2 on a bad opcode but it
is never OR'd into `protocol_err`), and no interface/bus hang detection (there is no
timeout counter in the RTL).  The corresponding `irpt_event_vec`/`irpt_error_vec`
bits are dead toggle nodes — not a test gap.  The remaining 5 sources are live and
driven by real hardware: `cmdfifo_full`, `respfifo_full`, `rdfifo_full` (FIFO
occupancy) and `t2c_virtio`, `c2t_virtio` (VIO change-detect, gated by the
`*_VIRTIO_EN` registers).

Not a functional-misbehavior bug (the block works; those interrupts simply never
assert), but the interrupt feature set is incomplete and should be finished or the
dead sources removed/CCF-excluded.  The live sources are covered by
`fabio_intr_event_test` (real-event virtio + FIFO-full interrupts, with INTR_EN
enabled — distinct from the existing `fabio_tgt_reg_coverage_vseq` which only
force-sets INTR_RAW via INTR_SET).

---

## Notes

- All fixes are on branch `rnm-reference-flow`; RTL edits are made in the `.pysv`
  sources (regenerated to `.sv`) where applicable (`dac_ctrl_half.pysv`).
- Verification hooks: `dac_fsm_test` (FSM), `dac_datapath_test` (SRAM→DAC datapath,
  both halves), `spi_*` firmware tests (SPI core), plus the reusable `DAC_VCD=1`
  Makefile waveform probe used to root-cause #3.
- `make slint` reports Errors = 0 for the DAC RTL after fixes #1–#3.
- `make jcdc` could not elaborate `dac_ctrl` due to pre-existing missing macro
  black-boxes (SRAM, AnaTop) — unrelated to these fixes; worth restoring so the CDC
  crossing (#1) is tool-checked.
