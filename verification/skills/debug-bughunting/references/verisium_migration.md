# Verisium Integration & Coverage Improvement Plan

Working directory: `verif/uvm/`  
Baseline: `cadence/vmanager/25.09.003` (IMC) + `cadence/xcelium/25.09.001` (xrun)  
Target: `cadence/verisium/25.09.001` for wave debug + coverage baseline cleanup

---

## Verisium Integration Phases

### Phase 1 — Post-sim wave debug (DONE: Makefile ready)

Adds a `debug_waves` Make target that opens an existing `waves.shm` in Verisium Debug
(formerly Indago) instead of SimVision. No simulation change required.

**What it unlocks:** UVM transaction timeline, cross-domain source trace, SmartLog.  
**When to use:** after any `make sim WAVE=1 TESTNAME=...` run.

Makefile additions:

```makefile
VERISIUM_MODULE := cadence/verisium/25.09.001
VERISIUM_LOAD   := source /usr/share/Modules/init/bash && module load $(VERISIUM_MODULE) &&

debug_waves:
    @test -f $(WAVE_DB) || { \
        echo "No wave database at $(WAVE_DB)."; \
        echo "Run 'make sim WAVE=1 TESTNAME=$(TESTNAME)' first."; exit 1; }
    $(VERISIUM_LOAD) verisium -debug -64bit \
        -wave_db $(WAVE_DB) \
        -design_db $(XCELIUM_D) &
```

Usage:
```bash
make sim TESTNAME=msic_smoke_test WAVE=1
make debug_waves TESTNAME=msic_smoke_test
```

**Status: TODO** — variables and target to be added to Makefile.

---

### Phase 2 — Live Indago session (full UVM-aware debug)

Records an Indago `.ida.db` during simulation for richer post-sim debug:
transaction traces, UVM phase timeline, coverage-correlated waveforms.

**Cost:** Larger on-disk database; longer sim runtime. Use only for targeted debug,
not for every regression run.

Makefile additions:

```makefile
IDA_DB := $(RUN_DIR)ida.db

ifeq ($(INDAGO),1)
XRUN_FLAGS += -input "@indago -enable -db $(IDA_DB)"
endif

debug_indago:
    @test -d $(IDA_DB) || { \
        echo "No Indago DB at $(IDA_DB)."; \
        echo "Run 'make sim INDAGO=1 TESTNAME=$(TESTNAME)' first."; exit 1; }
    $(VERISIUM_LOAD) verisium -debug -64bit -db $(IDA_DB) &
```

Usage:
```bash
make sim TESTNAME=msic_smoke_test INDAGO=1
make debug_indago TESTNAME=msic_smoke_test
```

**Status: TODO** — pending Phase 1 validation.

---

### Phase 3 — Verisium Manager (regression orchestration)

`verisium -manager` provides VSIF-based test scheduling, distributed grid runs,
per-test coverage merge, and plan-driven coverage goals.

**Not recommended until:**
- Regression grows past ~200 tests, OR
- Grid-distributed runs are needed, OR
- Plan-driven coverage tracking is required by tapeout checklist.

The current `run_regression.py` + make flow handles MSIC's scale adequately.

**Key notes for future migration:**
- `imc` is NOT shipped with `cadence/verisium/25.09.001` — keep `cadence/vmanager/25.09.003`
  loaded for all IMC (`cov_gui`, `cov_report`, `cov_merge`) targets.
- Both modules load without conflict: load vmanager first, then verisium.
- Verisium Manager uses VSIF files (`.vsif`) — separate from the Makefile/python flow.

**Status: DEFERRED**

---

## Coverage Improvement Steps

Coverage baseline (merged, 55 tests, 2026-07-01): **179,869 total uncovered items**

| Module | Items | % | Category |
|---|---|---|---|
| `u_dac_ctrl/u_AnaTop` (pixel array) | ~98,700 | 54.9% | Analog IP — exclude |
| `u_cpuss/u_CortexM4_Int` (ARM IP) | 26,874 | 14.9% | ARM IP — exclude |
| `u_clock_ctrl/u_PLLTS22ULPHVFRACB_dont_touch` | 20,762 | 11.5% | PLL model — exclude |
| `u_gpio` (reg + logic) | ~9,000 | 5.0% | **Real gap — needs tests** |
| `u_dac_ctrl` (digital ctrl, post AnaTop excl) | ~4,200 | 2.3% | **Real gap — needs tests** |
| `u_fabio_tgt` (reg file) | ~871 | 0.5% | **Real gap — may improve with existing tests** |

After applying Step 1, the meaningful uncovered count drops from 179,869 to ~33,500.

---

### Step 1 — CCF exclusions (IN PROGRESS)

Add `coverage.ccf` and wire it into `XRUN_FLAGS` when `COV=1`.  
Excludes analog IP, ARM IP, and PLL model from all coverage collection.

**File:** `verif/uvm/coverage.ccf`  
**Makefile change:** `XRUN_FLAGS += -covfile $(COV_CCF)` inside `ifeq ($(COV),1)` block.

Scopes excluded:

| Instance path | Reason |
|---|---|
| `.../u_dac_ctrl/u_AnaTop...` | Analog behavioral model; 64×64 holdcap pixel array not stimulated in UVM |
| `.../u_cpuss/u_CortexM4_Int...` | ARM Cortex-M4 Integration IP; not our RTL |
| `.../u_clock_ctrl/u_PLLTS22ULPHVFRACB_dont_touch...` | PLL behavioral model + assertions; clock gated in UVM |

CCF syntax: `deselect_coverage -all -instance /path...` (the `...` suffix recurses into all descendants).  
xrun flag: `-covfile coverage.ccf` (parsed at elaboration time by xmelab).

**Validation:** run `make sim COV=1 TESTNAME=msic_smoke_test` → confirm CCF loads cleanly
(no `*W,COVCCF` warnings for unresolved paths). Then re-run `make cov_report REPORT_TEST=merged`
and compare uncovered item count to ~33,500 baseline.

**Status: IN PROGRESS**

---

### Step 2 — GPIO coverage (IN PROGRESS)

Current uncovered: ~9,000 items in `u_gpio` (reg + logic).  
Existing tests: `gpio_output_test` (output driving), `gpio_test` (basic).

**Test written: `gpio_reg_coverage_test` (NOFW, FabIO C2T-driven APB writes)**

| Test name | Registers exercised | Coverage target |
|---|---|---|
| `gpio_reg_coverage_test` | All 123 `chip_io*_ctrl`, 4 `gpio_set*_core2pad` | gpio_ds/oe_n/pu/pd + all alt_en_* (except ie) |

FabIO APB routing (confirmed from `cmsdk_cpuss_ahb_decodeS_FIO.v`):
- FabIO AHB master maps 0x40000000-0x400FFFFF to MAPB after commit d9b6eccc
- GPIO base in CPU space: 0x4000_A000 (apb_base=0x40000000 + gpio_base=0xA000)
- `translate_addr()` is identity (commit a74168d3) → C2T addresses are CPU-space

ctrl write pattern = `0x2F0F`:
- Covers: ds(0), oe_n(1), pd(2), pu(3), alt_en_ds(8), alt_en_oe_n(9), alt_en_pd(10), alt_en_pu(11), alt_en_padout(13)
- Skips: gpio_ie(4), alt_en_ie(12) — `altfunc_pad_ie[N]=1'b1` hardwired; any write
  asserts chip_io_ie=1 → NI_BEHAVIORAL analog pad model → 600,000× slowdown
- gpio_ie and alt_en_ie for all 123 pins need vRefine exclusions (pending test pass)

Files created:
- `sequences/gpio_reg_coverage_vseq.sv`
- `tests/gpio_reg_coverage_test.sv`
- Registered in: `tb/msic_tb_pkg.sv`, `run_regression.sh` (NOFW_TESTS)

**Status: DONE** (committed b2367599; vRefine exclusions for gpio_ie/alt_en_ie ×123 in coverage.vRefine)

---

### Step 3 — DAC ctrl coverage (IN PROGRESS)

Current uncovered: ~4,200 items in `u_dac_ctrl` digital logic (post AnaTop exclusion).  
Existing: `fabio_write_dac_sram_test` exercises AHB SRAM write path only (no APB regs).

**DAC clock in UVM sim:** 10 kHz test clock forced via  
`force u_msic_top.u_digital_top.dac_clk = dac_clk_sim` (msic_tb_top_hdl.sv:64).  
`dac_resetn` syncs correctly to this clock; reset path IS exercised.

**State machine CDC constraint:** `run_command_wr = reg2hw.dac_cmd.cmd.qe`  
(dac_ctrl_half.sv:665 — FIXME comment). The HWQE fires for 1 hclk cycle (20 ns).  
With 10 kHz dac_clk (100 µs period), the pulse is **never** captured by the FSM FF.  
State machine states (DC_IDLE/DC_ROW_PRE_EN/DC_ROW_EN/DC_ROW_POST_EN) cannot be  
exercised without either: (a) RTL CDC fix, or (b) firmware with PLL-driven dac_clk.

**Test written: `dac_ctrl_reg_test` (NOFW, FabIO C2T-driven APB writes)**

| Register | Offset | Write pattern | Notes |
|---|---|---|---|
| DEBUG0 | 0x00 | read only | constant 0x43484950 |
| DEBUG1 | 0x04 | 0xFFFF/5555/AAAA/0 | pure RW |
| STATUS | 0x08 | read only | HW writes state/cur_row |
| DAC_CMD | 0x0C | 0x3F/0x15/0x2A/0 | CMD+IMAGE_SEL; FSM stays IDLE (CDC) |
| DACWDATA | 0x10 | 0xFFFF/5555/AAAA/0 | DACA[7:0],DACB[15:8] |
| TMR_CNT | 0x14 | 0xFFFFFFFF/5555/AAAA/0 | fast+slow timer counts |
| ANATEST_SEL | 0x18 | 0xFF/55/AA/0 (bits[7:0] only) | skip bit 8 (ANALOG_OUT_ENABLE) |
| ROW_CTRL | 0x1C | 0xFFF/0 | end_row[11:6],start_row[5:0] |
| ROW_EN_CTRL | 0x20 | 0xFFFFFF/55/AA/0 | pre/active/post counts |
| ROW_PGM_RANGE | 0x24 | 0xFFFF/5555/AAAA/0 | start_row[15:8],end_row[7:0] |
| CM_CTRL_MODE | 0x28 | 3/2/1/0 | all 3 modes |
| CM_CTRL_CNT | 0x2C | 0xFFFFFFFF/5555/AAAA/0 | iteration count |
| LFSR_SEED | 0x30 | 0xDEADC0DE/5A5A/0 | PRNG seed |
| SRAM_TRIM | 0x34 | 0x7F/0 | EMAA/EMAB/EMASA |
| OBSDATA | 0x38 | read after each OBSSEL | exercises 39 obs paths |
| OBSSEL | 0x3C | sweep 0..38 | observation mux select |

Excluded bits:
- ANATEST_SEL[8] (ANALOG_OUT_ENABLE): drives tst_en → NI_BEHAVIORAL pads (vRefine added)
- DAC FSM states: CDC FIXME blocks exercise from NOFW+10kHz dac_clk

Files created:
- `sequences/dac_ctrl_reg_coverage_vseq.sv`
- `tests/dac_ctrl_reg_test.sv`
- Registered in: `tb/msic_tb_pkg.sv`, `run_regression.sh` (NOFW_TESTS)
- vRefine: 1 exclusion for analog_out_enable (comment="10")

**Status: DONE** (committed 11f203e1; ANATEST_SEL vRefine exclusion in coverage.vRefine comment="10")

**Step 3b — DAC FSM coverage: DONE (RTL CDC fix).**
Root cause fixed in `dac_ctrl_half.pysv/.sv`: `run_command_wr = cmd.qe` crossed hclk→
dac_clk with no synchronizer, so the 20 ns HWQE pulse was invisible to the 10 kHz FSM.
Replaced with a `ni_toggle_pulse_sync2d` pulse synchronizer (edge-detect on hclk →
toggle-level cross → one dac_clk pulse).  Also tied off the previously-undriven
`hw2reg.dac_cmd.cmd.de` / `image_sel.{d,de}` (were X → prim_subreg hardware-write
enable X-hazard).  The dac_clk→hclk `status.cur_row` read-back (debug field) is left as a
benign direct multi-bit crossing.

New NOFW test `dac_fsm_test` (`dac_fsm_vseq`): programs small row/enable counts
(pre=active=post=1) and a short row range, then issues DAC_CMD.  Two spaced commands
cover the FSM without a full 111-row sweep.

DAC FSM coverage (top_dac_ctrl and bot_dac_ctrl): **9.09% (1/11) → 90.91% (10/11)**.
All 4 states now reachable (was DC_IDLE only).  6/7 transitions covered; the one
remaining (DC_ROW_EN → DC_IDLE at row_sel == NUM_ROWS-1 == 110) needs a full ~48-row
sweep (start_row is 6 bits, max 63) — slow at 10 kHz, left for a directed long test.

NOTE: discovered the ROW_CTRL / ROW_EN_CTRL field-position comments in
`dac_ctrl_reg_coverage_vseq` were wrong (end_row/start_row and post_cnt/pre_cnt swapped);
corrected against `dac_ctrl_reg_top.sv` (end_row[5:0], start_row[13:8]; post_cnt[7:0],
active_cnt[15:8], pre_cnt[23:16]).  The reg-walk test was functionally unaffected (it used
all-ones/all-zero patterns).

Verification: lint (`make slint`) Errors=0; `dac_fsm_test` PASS (UVM_ERROR=0).  `make jcdc`
could not elaborate due to pre-existing missing macro blackboxes (SRAM, AnaTop),
unrelated to this change.

---

### Step 4 — FabIO tgt coverage (IN PROGRESS)

Current uncovered: ~871 items in `u_fabio_tgt` reg file.  
Existing tests cover: CTRL, C2T/T2C_VIRTIO_EN, T2C_VIRTIO_SET, FABIO_STATUS.  
Gap: all 9 interrupt registers (INTR_EN/POL/RAW/STAT/MASK/MODE/EDGE/SET/CLR × 10 bits each),
DEBUG1, RESET (unconnected scratch), MODNAME and VERSION reads.

**FabIO TGT APB base:** `0x4000_9000` (apb_base=0x40000000 + fabio_tgt_base=0x9000)

FabIO C2T can write to fabio_tgt's own APB registers — this is how `fabio_cr_test` works.

**Test written: `fabio_tgt_reg_test` (NOFW)**

| Register | Offset | Write pattern | Notes |
|---|---|---|---|
| INTR_EN | 0x00 | 0x3FF/0x155/0x2AA/0 | enable all 10 sources |
| INTR_POL | 0x04 | patterns | polarity (active-high=0, active-low=1) |
| INTR_RAW | 0x08 | read | HW-written; INTR_SET forces bits |
| INTR_STAT | 0x0C | read | masked status |
| INTR_MASK | 0x10 | 0x3FF/0x155/0x2AA/0 | mask |
| INTR_MODE | 0x14 | 0x3FF/0x155/0x2AA/0 | level=0, edge=1 |
| INTR_EDGE | 0x18 | 0x3FF/0x155/0x2AA/0 | rising=0, falling=1 |
| INTR_SET | 0x1C | 0x3FF | force-set all 10 INTR_RAW bits |
| INTR_CLR | 0x20 | 0x3FF | clear all 10 INTR_RAW bits |
| MODNAME | 0x24 | read | RO constant |
| VERSION | 0x28 | read | RO major/minor |
| DEBUG1 | 0x2C | 0xFFFFFFFF/55/AA/0 | RW scratch (hw2reg wired to 0) |
| RESET | 0x34 | 0xFFFFFFFF/55/AA/0 | reg2hw unconnected — safe |
| FABIO_STATUS | 0x48 | read | RO HW-driven |

Skipped: CTRL (covered by fabio_cr_test), C2T_VIRTIO_EN/STATUS + T2C_VIRTIO_EN/SET (virtio tests).

Files created:
- `sequences/fabio_tgt_reg_coverage_vseq.sv`
- `tests/fabio_tgt_reg_test.sv`
- Registered in: `tb/msic_tb_pkg.sv`, `run_regression.sh` (NOFW_TESTS)

**Status: DONE** (committed 2f9c7815)

---

### Step 5 — vRefine path audit: prim_subreg flattening fix

**Root cause discovered:** Xcelium flattens `prim_subreg` module instances — they do NOT
appear as sub-hierarchy in the UCIS toggle database.  Toggle tracking is at the *parent
module* level using two signal name forms:
- `reg2hw.<field>.q` — packed-struct form (shows in IMC reports but cannot be used in vRefine
  entityName: IMC interprets `.` as scope separators → NOMATCH)
- `<inst_name>_qs` — flat net form (correct for vRefine entityName)

**Fixed entities:**

| Exclusion set | Old path (NOMATCH) | Correct path |
|---|---|---|
| gpio_ie ×123 + alt_en_ie ×91 (comment="9") | `.../u_reg/u_chip_ioN_ctrl_gpio_ie/q` | `.../u_reg/chip_ioN_ctrl_gpio_ie_qs` |
| ANATEST_SEL (comment="10") | `.../u_dac_ctrl_reg_top/u_anatest_sel_analog_out_enable/q` | `.../u_dac_ctrl_reg_top/anatest_sel_analog_out_enable_qs` |

Total: 246 wrong entries → 215 correct entries (214 `_qs` gpio_ie/alt_en_ie + 1 ANATEST_SEL).
reg2hw.*.q entries excluded from vRefine: the `_qs` exclusion also suppresses the reg2hw alias
(same underlying FF; IMC reports 0 uncovered gpio_ie signals after `_qs` exclusion alone).

**Validation:** `load -refinement coverage.vRefine` → zero NOMATCH warnings.

**Status: DONE** (committed ac523831)

---

### Step 6 — SPI host coverage

Current uncovered (pre-work): `u_spi_host` at 17.29% toggle (175/1012), the largest
structural hole inside `u_cpuss`.  Root-caused the low number into two parts:

**(a) Orphaned AHB-to-TL bridge — dead RTL, excluded.**
`u_AHB_to_TL_Bridge` (382 toggle nodes, was 2/382) is a leftover from the OpenTitan
TileLink→APB port.  Its TileLink side is physically disconnected:
- `tl_i` is declared but **never assigned** (spi_host.sv:81),
- `tl_o` output is **unused** (reg-file TL ports commented out, spi_host.sv:272-275),
- fifo windows tied to `TL_H2D_DEFAULT` (spi_host.sv:87-88).

Register + FIFO access flows through the APB path (`u_reg`), not this bridge, so its
TL-side FSM can never handshake and the block cannot toggle.  Excluded structurally
via `coverage.ccf` (`deselect_coverage -all -instance .../u_AHB_to_TL_Bridge...`).
Applies on next COV=1 re-elaboration.  NOTE: `exclude -toggle <inst>` and vRefine
instance-level toggle both fail in IMC 25.09 (MSGPTH / NOMATCH); CCF is the working
mechanism for whole-instance exclusion.

**(b) Register file / FIFO / cmd-queue — lifted by NOFW test `spi_host_reg_test`.**
FabIO C2T register walk of the SPI host CSRs at APB base `0x4000_8000`, modeled on
`dac_ctrl_reg_test`.  Walks INTR bank (EN/POL/MASK/MODE/EDGE + SET/CLR), CONFIGOPTS,
CSID, CONTROL (tx/rx watermark, output_en, sw_rst), ERROR_ENABLE, EVENT_ENABLE;
fills the TX FIFO (16 words) to exercise `u_data_fifos`/`u_tx_fifo` + STATUS.TXQD;
enqueues COMMAND segments to exercise `u_cmd_queue` + STATUS.CMDQD.

SAFETY: `CONTROL.SPIEN` held 0 the whole walk → SPI core FSM never leaves idle, so
no QSPI pad activity (no NI_BEHAVIORAL slowdown) and the TX FIFO never drains
(deterministic).  ~17.9 ms sim.

Per-test-alone lift (single NOFW run):

| Sub-block | Old (whole regr) | spi_host_reg_test alone |
|---|---|---|
| u_spi_host | 17.29% (175/1012) | 32.41% (328/1012) |
| u_reg | 47.39% | **70.68%** (622/880) |
| u_cmd_queue | 23.08% | **50.77%** (66/130) |
| u_data_fifos | ~48% (rx_fifo 3.7%) | 44.41% (151/340) |

Merged (all 67 tests, post-regression): `u_spi_host` module scope **17.29% → 35.38%**
(358/1012) with children `u_reg` **71.70%** (631/880), `u_cmd_queue` **53.85%**
(70/130), `u_data_fifos` **53.82%** (183/340), `u_spi_core` 22.04% (41/186).

NOTE on the CCF bridge exclusion: `report -summary -inst` numbers are *per-scope*
(a module's own signals), not recursive.  The 1012 above is `spi_host.sv`'s own
top-level signals — a scope distinct from the `u_AHB_to_TL_Bridge` child (its 382
internal nodes).  The CCF exclusion removes that child scope entirely (confirmed:
no `u_AHB_to_TL_Bridge` node in the merged hierarchy, direct query NOMATCHes), so
it drops from the *recursive* SPI-host rollup — but does not change the 358/1012
module-level line.  The residual dead AHB/TL wires still counted in the 1012 are
the undriven `tl_i`/`tl_o`/`ahb_in_if`/`ahb_wstrb` nets declared in `spi_host.sv`
itself (not inside the bridge instance); excluding those would need per-signal
refinement and is low value.

EXCLUDED (need firmware + flash model, deferred): SPI core datapath
(`u_spi_core` FSM 6.7%, shift_reg), RX FIFO / byte_merge — all require a real
transaction with a responding device (SPIEN=1), which drives the QSPI pads.

Files created:
- `sequences/spi_host_reg_coverage_vseq.sv`
- `tests/spi_host_reg_test.sv`
- Registered in: `tb/msic_tb_pkg.sv`, `run_regression.sh` (NOFW_TESTS)
- `coverage.ccf`: dead AHB-to-TL bridge exclusion

**Status: DONE** (test PASS, UVM_ERROR=0)

---

## Baseline coverage (67 tests, merged, with corrected vRefine + CCF bridge excl)

After full regression (67 PASS 0 FAIL, commit 94ea3a1d, elapsed 01:03:39) +
corrected exclusions.  Per-scope (module-level) toggle:

| Scope | Toggle | vs prev (66-test) |
|---|---|---|
| msic_top (pad_top only) | 40.55% (431/1063) | 40.36% |
| u_digital_top | 26.56% (549/2067/45 excl) | 26.27% |
| u_fabio_tgt | 63.71% (1255/1970) | 63.50% |
| u_cpuss | 11.93% (86/721) | 11.37% |
| u_spi_host | 35.38% (358/1012) | 17.29% |
| ⤷ u_reg (spi) | 71.70% (631/880) | 47.39% |
| ⤷ u_cmd_queue | 53.85% (70/130) | 23.08% |
| ⤷ u_data_fifos | 53.82% (183/340) | ~48% |
| u_gpio | 31.26% (1133/3625) | — |
| u_gpio/u_reg | 68.71% (4021/5852/214 excl) | gpio_ie excl applied |

SPI host was the headline gain this cycle: `spi_host_reg_test` (NOFW) plus the
dead AHB-to-TL bridge exclusion.  Numbers above are per-scope; the bridge's 382
dead nodes are removed from the recursive rollup (see Step 6).

### After Tier 1 + Tier 2 (75 tests, commit 8a238c25, 75 PASS/0 FAIL)

| Scope | prev | Tier 1+2 |
|---|---|---|
| msic_top | 40.55% | 40.55% |
| u_digital_top | 26.56% | 27.09% |
| u_chip_ctrl | 8.99% | **65.11%** (NOFW reg walk) |
| u_clock_ctrl | 6.91% | **52.36%** (NOFW reg walk + clock_ctrl_test1) |
| u_cpuss_apb_subsystem | 56.98% | 63.80% |
| u_apb_dualtimers_2 | 19.83% | **96.62%** (dualtimer_test1) |
| u_apb_timer_0 / _1 | ~33% | 49.61% each (timer_irq tests) |
| u_apb_uart_0 | 18.80% | 41.69% (uart0_tx_irq, TX path) |
| u_cmsdk_cpuss_ahb_busmatrix | 30.21% | 30.21% (unchanged) |

Findings: Tier 1/2 gains are real but block-local.  The AHB busmatrix did NOT
move — the pre-existing `fabio_write_*` FW tests already boot firmware and drive
the CPU→AHB path, so the new timer/uart IRQ tests reuse the same bus patterns;
the Tier-2 value is the APB peripheral datapaths, not the bus.  The top-line
(u_digital_top +0.5%) barely moves because the **DAC datapath's ~44k uncovered
nodes dominate the denominator** — moving the headline requires Tier 3 (DAC
data-flow) + structural exclusion of uninitialised DAC SRAM bits.

---

## Post-DAC-fix merged baseline + next-round hole ranking (89 PASS, commit 72c9caca)

Full regression with the **both-halves** DAC datapath test: `u_dac_ctrl` **92.43%**
(14528/15718), `top_dac_ctrl`/`bot_dac_ctrl` both 65.60%.  The DAC block — the single
biggest lever, once fully blocked — is essentially closed.

Remaining holes ranked by **absolute uncovered toggle nodes**:

| Block | Uncov | % | Class → next action |
|---|---|---|---|
| top_dac_ctrl / bot_dac_ctrl | 7844 ×2 | 65.6% | **CLOSED** the `ram*_gated_rdata` AHB debug-read path (56 macros × 128-bit quad-word = 7168 nodes) → **100% toggled** by `dac_sram_read_test` (firmware): CPU writes then reads back all 56 macro columns × 4×32-bit lanes.  Confirms **CPU can both write and read DAC SRAM** (0 mismatches, 280 reads).  The path could not be reached from a NOFW/FabIO test — a FabIO C2T read of DAC SRAM **times out** ("no T2C response") because it crosses the 10 kHz-forced `dac_clk` CDC and exceeds the FabIO read-response timeout, whereas the CPU tolerates the HREADY stall.  Test needs `TIMEOUT_NS=200000000` (sim ends ~112 ms; each read ~0.4 ms).  Remaining `vcom=1` branches / unused rows are the only genuinely-dead part (Tier-5). |
| u_gpio (pad logic) | 2447 | 32.5% | test-gap — needs pad in/out stimulus across 123 pins (gpio_input_* firmware, partly excluded today for sim speed) |
| AHB busmatrix + decoders/arbiters (`ahb_busmatrix`, `decodes_sys/fio`, `outputm*`) | ~3300 | 31.4% → 33.3% | **Arbiter contention now covered.**  Found+fixed a dead TB dispatch (concurrent-write cmd `0xA5A10000` keyed on the wrong ctrl byte, bug register #6) — no test had ever generated simultaneous multi-master traffic, so the arbiter contention nodes (`req_port1 & req_port2`, `addr_in_port[1:0]` winner-select, `active_op1/op2`, `no_port`) were all dead.  Now fully toggled on **arbMSRAM** (revived `fabio_bus_contention_test`) and **arbMAPB** (new `busmatrix_apb_contention_test`).  outputMSRAM 45.6%→47.3%, outputMAPB 44.6%→46.3%, FabIO master port `input_1` 30.6%→37.0%.  Remaining gap is the wide HADDR/HWDATA/HRDATA bus bits (need more address/data variety, not arbiter-specific) + single-master outputMSPI (21.6%, no arbiter) + PPB/NVIC access. |
| u_fabio_tgt (+ reg_top) | ~1100 | 64% | test-gap — targeted INTR/virtio register paths + error sequences |
| u_cpuss (glue) | 610 | 15.4% | firmware — broader CPU code paths (ARM core itself is CCF-excluded) |
| u_spi_host residual | 461 | 54.5% | test-gap — cmd_queue / data-fifo corner cases |
| u_apb_uart_2 | 293 | 20.2% | firmware — uart2 operational test (quick win, mirror uart0_tx_irq) |

**Recommended next round:** (1) legitimate DAC Tier-5 exclusion of the `vcom=1` /
unused-row dead logic (biggest number, now defensible) + a small AHB-read/`obsdata`
DAC test; (2) an **unmapped-address / error-response** test to hit the busmatrix
default-slave + arbiter error paths; (3) `uart2` operational firmware (easy, mirrors
Tier-2); (4) GPIO pad-I/O stimulus.  `msic_top`/`u_digital_top` per-scope stay
41.49%/29.03% (pad-ring-dominated own-signals); block-level and recursive aggregate is
where the gains land.

---

## DAC datapath fix folded in (89 tests, 89 PASS / 0 FAIL, commit cabb305b)

After fixing the SRAM read-enable gap (`design/dac_ctrl/doc/dac_sram_read_enable_gap.md`)
and the `dac_datapath_test` FF/00/FF sweep, the full regression re-elaborated with the
DAC RTL change — no regressions.  DAC block toggle:

| Scope | Before fix | After fix |
|---|---|---|
| u_dac_ctrl | 1.82% (286/15718) | **47.21% (7421/15718)** |
| ⤷ top_dac_ctrl | 2.48% | **65.59% (14957/22805)** |
| ⤷ bot_dac_ctrl | 1.71% | 3.00% (top-only test; bot needs symmetric load) |

+7,135 covered DAC toggle nodes — the biggest single lever in the design.  Per-scope
`msic_top` (41.49%) / `u_digital_top` (29.03%) are unchanged because they count each
module's *own* signals (pad-ring dominated); the DAC gain lives in the `u_dac_ctrl`
subtree and so lifts the recursive/aggregate design coverage.  The DAC command CDC bug
and this SRAM read-enable bug were both found and fixed during this campaign.

---

## Coverage campaign result — all tiers merged (89 tests, 89 PASS / 0 FAIL)

Full `make regress_parallel COV=1`, commit 5c9f95b9, 22:27 wall-clock.  Toggle,
start-of-campaign (68-test) → after Tiers 1/2/4:

| Scope | Before | After | Driver |
|---|---|---|---|
| msic_top | 40.55% | 41.49% | (pad-ring dominated) |
| u_digital_top | 26.56% | **29.03%** | sum of below |
| u_cpuss | 11.93% | **15.40%** | firmware + SPI |
| u_spi_host | 35.38% | **54.45%** | Tier 4 SPI firmware |
| ⤷ u_spi_core | 22.0% | **78.0%** | (FSM 6.7% → 93.3%) |
| u_chip_ctrl | 8.99% | **64.39%** | Tier 1 reg walk |
| u_clock_ctrl | 6.91% | **52.36%** | Tier 1 reg walk |
| u_apb_dualtimers_2 | 19.83% | **96.62%** | Tier 2 dualtimer_test1 |
| u_apb_uart_0 | 18.80% | **41.69%** | Tier 2 uart0_tx_irq |
| u_apb_timer_0/_1 | ~33% | 49.61% | Tier 2 timer_irq |
| u_dac_ctrl | 1.82% | 1.99% | blocked by open datapath bug |

**Summary:** block-level wins are large (SPI core +56 pts, chip_ctrl +55, clock_ctrl
+45, dualtimer +77); `u_digital_top` rose +2.5 pts overall.  The top-line is gated by
(a) `u_pad_top` dominating `msic_top`'s denominator and (b) the DAC datapath's ~44k
nodes stuck at ~2% behind the **open DAC datapath bug** (see
`design/dac_ctrl/doc/dac_sram_read_enable_gap.md`) — the single biggest remaining lever,
and a design-owner item.  Two genuine DAC RTL bugs were found along the way (command
CDC — fixed; SRAM→DAC datapath — open).

NOTE: the parallel COV merge can transiently fail with `*E,LICERR` if IMC can't get an
`Xcelium_Single_Core` license during the busy window; re-run `make cov_merge` once the
sims finish (licenses free) to produce the merged DB.

---

# Coverage Status Snapshot (current — HEAD 38b84e07, 2026-07-15)

Regression: **99 PASS / 0 FAIL** (merged DB from commit 38b84e07; adds
uart1_rx_test1 to the 98-test set).

## Refined toggle coverage by block

Refined = after `coverage.vRefine` exclusions (dead nodes removed).  Triples are
`covered / meaningful-denominator / excluded`.

| Block | Refined toggle | |
|---|---|---|
| **msic_top** | **86.45%** (919/1063) | pad-ring dominated |
| u_digital_top | 54.38% (1124/2067/45) | |
| **u_pad_top** | **86.45%** (919/1063) | lifted by GPIO ctrl walk ripple |
| **u_gpio** | **79.76%** (2499/3133/492) | 492 dead altfunc tie-offs excluded |
| u_gpio/u_reg | 92.86% (5633/6066) | ie bits now counted (stale excl removed) |
| u_dac_ctrl | 92.59% (14553/15718) | residual = dead structural |
| u_fabio_tgt | 66.45% (1309/1970) | rest capped by dead IRQ RTL (#8) |
| u_chip_ctrl | 65.83% (183/278) | |
| u_apb_uart_0 / _2 | 68.94% (253/367) | RX operational (#7 fix) |
| u_spi_host | 55.53% (562/1012) | 3/6 error conditions closed |
| u_clock_ctrl | 52.36% (144/275) | |
| u_apb_uart_1 | **75.48%** | RX covered (uart1_rx_test1) + stdout TX from all tests |
| u_cmsdk_ahb_busmatrix | 33.31% (818/2456) | arbiter contention nodes live (#6) |
| u_cpuss (glue) | 16.78% (121/721) | ARM core CCF-excluded |

## Exclusion categories

**CCF** (`coverage.ccf`, whole-instance, applied at elaboration): 4 instances —
`u_AnaTop` (analog model ~98.7k), `u_CortexM4_Int` (ARM IP ~26.9k),
`u_PLLTS22ULPHVFRACB_dont_touch` (PLL model ~20.8k), `u_AHB_to_TL_Bridge`
(orphaned TileLink bridge, bug #5, ~382).

**vRefine** (`coverage.vRefine`, signal-level toggle, applied at report via
`cov_exclusions.tcl`): 52 rules —
| # | Cat | Count | What |
|---|---|---|---|
| 1 | DFT | 4 | scan/DFT signals hardwired 0 |
| 2 | JTAG | 3 | JTAG pad outputs constant 0 (not wired in UVM) |
| 3 | PAD | 34 | pad-ring control constants |
| 4 | UNUSED | 2 | removed c2c_comm port tie-offs |
| 5 | CHIP | 2 | chip→analog outputs constant 0 |
| 6 | TIMER | 2 | timer external inputs not pinned in TB |
| 10 | DAC-ANATEST | 1 | analog test-enable path |
| 11 | GPIO-ALTFUNC | 4 | dead altfunc_pad_pu/pd/ds/ie tie-offs (492 bits) |

Principle held throughout: exclude **only** provably-dead nodes (constant drivers,
disconnected IP, un-instantiated paths); never mask coverable logic.  The former
comment=9 GPIO-ie exclusions (214) were **removed** once `gpio_ctrl_reg_walk_test`
covered them (IMC flagged them as "excluding covered entity").

## Pending / open

**Coverable test-gaps (real, lower-ROI):**
- `u_spi_host` — more SPI transfer modes/config; error conditions UNDERFLOW /
  CMDBUSY / ACCESSINVAL are timing-hard (RX underflow known-untriggerable).
- `u_clock_ctrl` (131) + `u_chip_ctrl` (95) — focused register-write firmware.
- ~~`u_apb_uart_1` RX~~ — DONE (uart1_rx_test1, time-multiplexed with stdout).
- GPIO/pad **pad2core input path** (~437 nodes) — needs pads driven; conflicts
  with the FabIO/QSPI agents on shared pads. Lowest ROI; the only part a pad-BFM
  would help. Would need a dedicated bank-0/1 pad driver + agent-quiet mode.

**Incomplete RTL — design-owner calls (documented in `doc/rtl_bugs_found_in_verification.md`):**
- #4 (OPEN) DAC output regs capture X in DC_IDLE — hold-semantics question.
- #8 (OPEN) FabIO tgt: 5 of 10 interrupt sources hardwired to 0 (write_op,
  read_op, protocol_err, fabio_if_hang, ahb_bus_hang) — caps u_fabio_tgt.

**Verification-infra note (RESOLVED 2026-07-14):**
- The FabIO→GPIO-APB write path is **verified working**.  The NOFW
  `gpio_reg_coverage_test` (FabIO C2T → MAPB → GPIO APB @0x4000_A000) lands its
  writes and toggles the GPIO register block (u_reg 63.9%); `gpio_pu/pd/ds.q`
  (reset 0, set by the test's 0x2F0F) are covered, proving the writes update the
  registers.  The earlier "writes don't toggle reg2hw.q" concern was a
  measurement artifact from sampling only the reset-1 / policy-held bits: the
  uncovered fields are `gpio_oe_n.q` (active-low, resets 1 → one edge without
  clear-first), `alt_en_*.q` (alt pins reset alt_en=1, same one-edge issue), and
  `gpio_ie.q` (the test deliberately holds ie=0 to avoid the NI_BEHAVIORAL
  slowdown).  All three are closed by the firmware `gpio_ctrl_reg_walk_test`
  (clear-first ordering + safe ie-enable).  The NOFW test could adopt clear-first
  ordering to close the alt-pin bits too, but is now redundant for that coverage.

**No action (dead/excluded):** AnaTop, ARM core, PLL, TL bridge, and the
constant tie-offs above.

---

## Campaign round 2 FINAL — 98 PASS / 0 FAIL (commit 6610619b, 2026-07-14)

Final merged tally after all seven new tests (dac_sram_read, busmatrix_apb_contention,
uart0_rx, uart2_rx, fabio_intr_event, spi_error_conditions, gpio_ctrl_reg_walk):

| Scope | Round-1 (89 tests) | Final (98 tests) | Driver |
|---|---|---|---|
| **msic_top** | 41.5% | **86.45%** | pad-ring ripple from gpio_ctrl_reg_walk |
| **u_digital_top** | 29.0% | **53.22%** | sum of below |
| **u_pad_top** | 41.8% | **86.45%** | gpio_ctrl_reg_walk ripple (+445) |
| **u_gpio** | 32.9% | **68.94%** | gpio_ctrl_reg_walk (+1305) |
| u_dac_ctrl | (post-fix) 92.6% | 92.59% | (round-1 DAC work) |
| u_fabio_tgt | 65.2% | 66.45% | virtio real-event (rest dead, #8) |
| u_spi_host | 54.5% | 55.53% | spi_error_conditions (3/6 errors) |
| u_cmsdk_ahb_busmatrix | 31.4% | 33.31% | arbiter contention nodes live (#6 fix) |
| u_apb_uart_0 / _2 | ~42% | **68.94%** | RX operational (#7 fix) |
| u_chip_ctrl | 65.8% | 65.83% | — |
| u_clock_ctrl | 52.4% | 52.36% | — |
| u_cpuss (glue) | 15.8% | 16.78% | ARM core CCF-excluded |

Biggest single lever: `gpio_ctrl_reg_walk_test` lifted **msic_top +45 pts** (u_gpio +1305,
u_pad_top +445 together) — a pure firmware register walk, no pad-BFM, no RTL change.
Four RTL/chip findings across the campaign (register #1-#8): 2 fixed silicon bugs (UART RX
pads #7, busmatrix dispatch #6), plus DAC datapath (#1-3 fixed), and 2 incomplete-RTL
documented (FabIO IRQ #8, DAC hold #4). Zero regressions.

---

## Campaign round 2 — DAC read-path + busmatrix arbiters + UART RX (95 PASS / 0 FAIL, commit 27f6e9f0, 2026-07-10)

Three targeted tasks, each of which closed real coverage **and** surfaced a real bug
(see `doc/rtl_bugs_found_in_verification.md`):

| Task | Coverage closed | Bug found (register #) |
|---|---|---|
| DAC SRAM read path | `ram*_gated_rdata` (56×128 = 7168 nodes) 0% → **100%** toggle; `dac_sram_read_test` (CPU write+read DAC SRAM) | (validation gap — read path never exercised) |
| Busmatrix arbiters | arbiter contention nodes (`req_port1&req_port2`, `addr_in_port` winner-select, `active_op1/2`, `no_port`) now toggled on **arbMSRAM + arbMAPB**; busmatrix 31.4% → 33.3% | **#6** — concurrent-write cmd `0xA5A10000` never dispatched (wrong ctrl byte); whole bus-contention feature was dead |
| UART RX/OVF | uart0 + uart2 **68.94%** (was TX-only); RX datapath + RXBF + RX-IRQ + RXOR | **#7** — UART RX pad input-enable tied low on all 3 UARTs (RX non-functional) |

New reusable TB infra: `uart_cmd_handler` + `uart_rx_inject_seq` (inject serial chars on
`uart_if.rx[n]` on a firmware TB_CTRL request, CTRL=0x20); `busmatrix_apb_contention_test`;
`dac_sram_read_test` (needs `TIMEOUT_NS=200000000`).

**Also fixed a self-inflicted regression:** regenerating `digital_top.sv` from `.pysv`
for the UART fix dropped a manual `.sv`-only CoreSight ROM-table edit (→ `coresight_fw_discovery_test`
FAIL); folded that block into the `.pysv` so the generator is now the complete source of truth
(commit 27f6e9f0).

### Merged block ranking (95 tests) — remaining holes by absolute uncovered toggle nodes

| Block | Toggle % | Uncovered | Class → next action |
|---|---|---|---|
| u_gpio | 32.9% → **68.9%** | ~1126 | **NOT a pad-BFM task** — the bulk was a register walk. The per-pin GPIO/altfunc mux select is a runtime register (`chip_ioN_ctrl.alt_en_*`), so all 123 pins' control logic is reachable by CPU register writes. `gpio_ctrl_reg_walk_test` (firmware) walks all 123 `chip_io*_ctrl` regs (clear-first so the alt pins, which reset with `alt_en=1`, see both edges) + safe input-enable (gpio_ie + pull-down, no pad X) → +1305 nodes. Residual: ~685 are **dead constant `altfunc_pad_*` tie-offs** (driven by constant assigns in digital_top per the pinout — cannot toggle); ~437 are the pad-input path (`pad2core`) that genuinely needs pads driven and fights the FabIO/QSPI agents — the only part a pad-BFM would help, and the lowest-ROI slice. |
| u_dac_ctrl | 92.6% | 1165 | mostly **dead** structural (vcom=1 branches, unused rows/bits) — leave |
| **u_fabio_tgt** | 65.2% | **686** | test-gap — INTR/virtio register paths + error sequences. **Best ROI (pure sequence work).** |
| u_pad_top | 41.8% → **86.5%** | 144 | Closed as a **ripple** of `gpio_ctrl_reg_walk_test`: toggling all 123 pins' pad-control signals (ie/oe_n/pu/pd/ds) propagates into the pad-cell control inputs. One firmware test lifted u_gpio (+1305) and u_pad_top (+445) together. |
| u_cpuss (glue) | 16.8% | 600 | ARM core CCF-excluded; rest = broader FW paths |
| u_spi_host | 54.5% → 55.5% | 450 | `spi_error_conditions_test` closed 3 of 6 error conditions (CSIDINVAL/CMDINVAL/OVERFLOW). Residual: ~156 nodes are dead `tl_o`/`tl_i` (orphaned TileLink bridge, bug #5, excluded); `error_busy`/`error_underflow`/`error_access_inval` are timing-hard (RX underflow known-untriggerable); rest = more SPI transfer modes/config. |
| u_clock_ctrl | 52.4% | 131 | small register-path cleanup |
| u_chip_ctrl | 65.8% | 95 | small |
| u_apb_uart_1 | 54.0% | — | RX untested (stdout UART; uart0/uart2 now 68.9%) |

**Next target: `u_fabio_tgt` INTR/virtio register paths** (best ROI — 686 nodes, reachable with
targeted sequences on the existing FabIO agent, no new TB infra).

---

## Parallel regression (`run_regression_parallel.sh` / `make regress_parallel`)

Sharded parallel runner: N workers run concurrently, each in its own
`scratch_parN/` (isolated Xcelium worklib — the shared worklib CANNOT be run
concurrently, it races).  Within a shard, `xrun` reuses its elaboration snapshot
across the shard's tests (re-elaborates only when a compile-time `-define`
changes, e.g. the `FABIO_CLK` variants).  Workers are **license-capped**:
effective = min(JOBS, MAX_LIC, free `Xcelium_Single_Core`); `MAX_LIC` defaults
to 5 (leaves headroom for others).  `COV=1` collects every shard's per-test
`.ucd` + `.ucm` into `scratch/cov_work/scope` and runs the normal
`cov_merge`/`cov_report`.

**Validated (68 tests, COV=1, commit c426ed37):**

| | Serial | Parallel (5 workers) |
|---|---|---|
| Wall-clock | 01:05:36 | **00:21:26** (≈ 3.06×) |
| Result | 68 PASS / 0 FAIL | 68 PASS / 0 FAIL |

Coverage parity is essentially exact — 7 of 8 tracked scopes match to the node
(msic_top 40.55%, u_digital_top 26.56%, u_cpuss 11.93%, u_spi_host 35.38%,
u_dac_ctrl 1.82%, u_gpio 31.26%, DAC FSM 90.91% both halves).  Only
`u_fabio_tgt` differs: 63.55% (1252/1970) vs 63.71% (1255/1970) = 3 toggle nodes.

**Cause of the 3-node delta (a pre-existing `covtest=TESTNAME` quirk, not a
parallelism bug):** the `FABIO_CLK` clock-variant tests
(`fabio_burst_write_test_{10,1000}mhz`, `fabio_burst_write_sram_test_{10,1000}mhz`)
use `-covtest $(TESTNAME)`, so they share a coverage-dir name with their base
test.  Serial keeps whichever ran *last*; parallel collection (`cp -n`) keeps
whichever shard is copied *first*.  Different variant retained → 3 near-identical
nodes differ.  Neither runner captures all three variants separately today.
Optional fix (helps both): switch the variant runs to `-covtest $(RUN_LABEL)`.

Single-simulation multi-core (`xrun -mce`, "M4 in its own partition") was
investigated and is **not available**: `-mce` elaborates but fails to check out
`Xcelium_Multi_Core` at sim time (`*F,NOLICN`); that license is not on the
server (only `Xcelium_Single_Core` ×7).  Multi-*test* parallelism is the
practical speedup lever.

---

## Coverage-hole analysis + roadmap (68-test merged, 2026-07-04)

Holes ranked by **absolute uncovered toggle nodes** (a 2%/15k-node block matters
more than a 5%/40-node one) and grouped by what unblocks them.

| Block | Uncovered (toggle) | Nature | Unblocked by |
|---|---|---|---|
| DAC datapath (top+bot `dac_ctrl` recursive, incl `dac_rams`) | ~44,000 | SRAM memory bits + 222 DAC output regs; only toggle with real image data | DAC-SRAM-load + full FSM programming test; structural exclusion of uninit SRAM bits |
| APB peripherals (uart0/2, timer0/1, dualtimer, watchdog) | ~2,700 | CMSDK IP only register-poked by `fabio_write_*`; datapaths idle | **Enable existing operational firmware** (see below) |
| GPIO pad logic (`u_gpio` module, excl `u_reg`) | ~2,500 | pad in/out paths need real pin toggling across 123 pins | gpio_input/output firmware (partly excluded today for speed) |
| CPU AHB busmatrix (`u_cmsdk_cpuss_ahb_busmatrix`) | ~1,700 | needs diverse multi-master AHB traffic + all slave ports | CPU firmware exercising every slave (timers/uart/wdog) |
| SPI core datapath (`u_fsm` 3%, `u_shift_reg` 6%, `u_merge`, `u_rx_fifo` 5%) | ~950 | needs a real SPI transaction (SPIEN=1) with a responding device | QSPI flash-responder + spi_* firmware |
| `u_chip_ctrl` reg + logic | ~610 | register file barely written | **NOFW reg walk** (easy) |
| `u_clock_ctrl` reg + logic | ~540 | register file barely written | **NOFW reg walk** (easy) + clock_ctrl_test1 fw |
| `u_fabio_tgt_reg_top` | ~430 | 64% done; remaining = specific IRQ/virtio paths | targeted IRQ/virtio sequences |

**Key discovery:** `firmware/msic_tests/` holds **88 tests**, but the regression runs
only the ~44 `fabio_write_*` register-poke variants.  Operational tests that actually
drive the peripherals already exist and are unused: `timer0_irq_test`, `timer1_irq_test`,
`dualtimer_test1`, `uart0_{tx,rx,ovf}_irq_test1`, `clock_ctrl_test1`, `dac_ctrl_test1`,
and the `spi_*`/`quad_spi_*`/`dual_spi_*` set.

### Prioritized plan

**Tier 1 — NOFW register walks (low effort, proven pattern, do first):**
`clock_ctrl_reg_test` + `chip_ctrl_reg_test`, mirroring `spi_host_reg_test` /
`dac_ctrl_reg_test`.  ~1,150 reg nodes, ~15 ms each, no firmware/model.

**Tier 2 — Enable existing operational firmware (highest ROI, tests already written):**
add `timer0_irq_test`, `timer1_irq_test`, `dualtimer_test1`, `uart0_{tx,rx,ovf}_irq_test1`,
`clock_ctrl_test1`, `dac_ctrl_test1` (+ watchdog) to the regression.  Validate each runs
clean in the UVM TB.  Lifts the ~2,700 APB-peripheral nodes and much of the ~1,700 AHB
busmatrix (CPU running real code touches all slaves).

**Tier 3 — DAC datapath: ATTEMPTED, BLOCKED by an RTL bug.** Built `dac_datapath_test`
(loads DAC SRAM, runs the FSM sweep).  It exercised the SRAM write path but the 222 DAC
output registers never toggled — SRAM→DAC programming is **non-functional in sim**
(see `design/dac_ctrl/doc/dac_sram_read_enable_gap.md`, OPEN/high-priority).  The
`dac_datapath_test` is kept as the validation hook for when the datapath is fixed.

**Tier 4 — SPI datapath:** wire a QSPI flash-responder (agent exists at
`verif/uvm/agents/qspi/`; no flash model yet) so `spi_word_write_test` /
`spi_jedec_read_test` etc. run — unblocks the ~950-node SPI core (`u_fsm` 3% → high).

**Tier 5 — structural exclusions: REASSESSED — the DAC does NOT qualify.** The original
plan assumed ~30 k structurally-dead DAC nodes.  That was wrong: the uncovered DAC bulk
(DAC output regs, `ram*_rdata`, macro I/O) is **blocked by the open datapath bug —
coverable once fixed, not dead.**  Excluding it would mask a functional bug behind a
coverage waiver and hide coverable logic; exclusions are for genuinely-unreachable
logic only.  So **no DAC exclusion** while the bug is open — the DAC path is the *fix*,
not exclusion.  `vcom` is hardwired to 0 (dac_ctrl.sv:620) but that is a single
stuck node, not a large excludable set.  Remaining genuine candidates are small
(`ppb_ahb_if` 2/51 — but may just need a PPB/NVIC firmware access; busmatrix
default-slave/error paths — better covered by an unmapped-address *test* than an
exclusion).  Net: little clean exclusion value here; the reachable low-hanging fruit
(Tiers 1–2) is done, and the remaining real gaps need either the DAC bug fix (Tier 3)
or the SPI flash responder (Tier 4).

---

## Quick-reference commands

```bash
# Run with coverage + CCF
make sim COV=1 TESTNAME=msic_smoke_test

# Merge all test runs
make cov_merge

# Batch uncovered report (merged)
make cov_report REPORT_TEST=merged

# GUI review (merged)
make cov_gui TESTNAME=merged

# Wave debug (Phase 1, after WAVE=1 sim)
make debug_waves TESTNAME=msic_smoke_test
```
