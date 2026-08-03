# pf_ed UVM Unit Testbench

A UVM unit testbench for **pf_ed** (Pixel Frame – Embedded Digital), driven by
Xcelium (`xrun`). The DUT is `pf_ed_wrapper` (the friendly-pin-name wrapper
around `pf_ed`, in `design/pf_ed/rtl/`).

## What pf_ed does

`pf_ed` is one cell of a 12×12 array of pixel frames, daisy-chained left→right.
A source-synchronous stream (`clk_in`, `din[15:0]`, `cmd_ndata_in`) carries
**commands** (when `cmd_ndata=1`, encoded as `{8'h0, pf_sel[3:0], cmd[3:0]}`)
and **pixel data** (when `cmd_ndata=0`, as `{dac_b[7:0], dac_a[7:0]}`). The
stream is buffered straight through to the next frame (`dout`, `clk_out`,
`cmd_ndata_out`). When a `PGM_START` addressed to this frame's `addr_sel` is
followed by `8×8` data beats and an `UPDATE`, the internal FSM strobes the
programmed DAC values out a row at a time on `DinA0..7`/`DinB0..7` with `En[row]`.

## Quick start

```bash
cd design/pf_ed/uvm
make                 # prints help (default target)
make sim             # build + run the default test (pf_program_test)
make sim WAVE=1      # + dump waveforms
make sim COV=1       # + coverage, then: make cov_gui
```

The first `sim`/`filelist` invokes Alchemy on `design/pf_ed/config/pf_ed.yaml`
to generate the design filelist (preprocesses `pf_ed.pysv` → `pf_ed.sv` and
pulls in `ni_parts`). The `pf_ed_wrapper.sv` DUT wrapper is added explicitly.

## Targets & options

Same interface as the top-level MSIC UVM TB — run `make help` for the full list.
Key options: `TESTNAME`, `SEED`, `WAVE=1`, `GUI=1`, `PROBE=1`, `COV=1`,
`TIMEOUT_NS=<ns>`.

## Tests

| Test               | Description                                                        |
|--------------------|--------------------------------------------------------------------|
| `pf_base_test`     | Builds the env, prints topology, idles.                            |
| `pf_program_test`  | Programs a full 8×8 frame with a known pattern and updates it (default). |

## Structure (HDL / HVL split)

```
design/pf_ed/uvm/
├── Makefile
├── README.md
├── common/        pf_pkg.sv          (geometry + command encodings)
├── interfaces/    pf_clk_rst_if, pf_stream_if, pf_dac_if
├── agents/
│   ├── stream/    active: drives the command/data bus, monitors passthrough
│   └── dac/       passive: captures DAC values on each En row strobe
├── env/           pf_env_cfg, pf_env
├── scoreboards/   pf_scoreboard   (passthrough + program/update reference check)
├── sequences/     pf_base_vseq, pf_program_frame_vseq
├── tests/         pf_base_test, pf_program_test
└── tb/            pf_tb_pkg + two tops:
    ├── pf_tb_top_hdl.sv  (clk/rst + interfaces + DUT, synthesizable partition)
    └── pf_tb_top_hvl.sv  (UVM run_test + config_db, behavioral partition)
```

The HVL top binds the virtual interfaces to the HDL top's instances via
hierarchical references and both are elaborated
(`-top pf_tb_top_hdl -top pf_tb_top_hvl`).

## Scoreboard checks

1. **Passthrough** — `dout`/`cmd_ndata_out` must equal `din`/`cmd_ndata` every cycle.
2. **Program/update** — pixel values streamed during `PGM_START`→data→`UPDATE`
   are recorded row-major; each `En`-strobed DAC row must match in the same order.
   `En` is also checked for one-hot.

## Pass/fail

```bash
grep -E "TEST (PASSED|FAILED)|SCOREBOARD|UVM_ERROR :" scratch/simland/<TESTNAME>/sim.log
```

## Caveats (first-run tuning)

These are structurally complete but unverified against a live run:

- **Cross-library `pf_pkg`**: `pf_pkg` compiles into the HDL library and the HVL
  agent packages `import pf_pkg::*`. Xcelium normally resolves this within one
  `xrun`; if the HVL compile can't see it, move `pf_pkg` into the HVL `-makelib`
  block (or compile it in both via a small wrapper).
- **Scoreboard alignment**: `pf_ed` flops `cmd_ndata` before the FSM acts while
  capturing `din` combinationally, so there is a 1-cycle internal skew. The
  scoreboard checks *ordering* (values stream in and come back out row-major),
  which is robust to that skew; if a real run shows an off-by-one, adjust the
  data-collection window in `pf_scoreboard.sv::_model_program`.
