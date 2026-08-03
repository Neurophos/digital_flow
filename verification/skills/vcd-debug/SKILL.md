---
name: vcd-debug
description: Debug a Neurophos UVM testbench from waveforms WITHOUT a GUI — dump a curated set of signals to a text VCD, then parse it programmatically (analyze_waves.py) to read exact values/edges/times and diff two runs. Use when an agent (or anyone headless) must root-cause RTL/TB behavior from waves — reset release, clock toggling, FSM/protocol timing, a datapath value — instead of eyeballing a waveform viewer.
---

# VCD Debug (no-GUI, script-parsed waveforms)

## When to use
Root-causing behavior that needs waveform truth — did reset release? is the clock
toggling? does the FSM advance? what value is on this bus at time T? — in a
**headless / agentic** context where you can't open a waveform viewer. Also for
**A/B comparison** of two runs (e.g. new vs legacy TB, pass vs fail).

## The strategy
An AI agent (or a CI job) can't see a GUI. So instead of dumping the whole design
to an SHM database and staring at it:
1. **Curate a small signal set** relevant to the question (reset, clocks, the FSM
   state, the datapath net, the protocol pins).
2. **Dump those signals to a text VCD** — human- and *script*-readable.
3. **Parse the VCD programmatically** with `scripts/analyze_waves.py` — read first
   edges, transition counts, and value-at-time; assert the expected behavior.
4. **Diff two runs** side-by-side to localize a regression.

This is faster and more reliable than GUI hunting: you check exact values at exact
times, and the check is reproducible.

## Dump a targeted VCD (Makefile knobs)
The sim Makefile has topic-scoped VCD probes — each opens a `-vcd` database and
`probe -create`s a **named signal list** (not the whole design):
```bash
make sim TESTNAME=<t> VCD=1        # UART1 + capture signals   -> <run>/waves.vcd
make sim TESTNAME=<t> FABIO_VCD=1  # FabIO C2T/T2C signals     -> <run>/fabio_waves.vcd
make sim TESTNAME=<t> JTAG_VCD=1   # JTAG pins                 -> <run>/jtag_waves.vcd
make sim TESTNAME=<t> DAC_VCD=1    # DAC SRAM wr/rd datapath   -> <run>/dac_waves.vcd
# (GUI path, not agentic:) WAVE=1 -> waves.shm ; GUI=1 PROBE=1 -> Simvision + all sigs
```
**Add a new topic probe** by mirroring an existing block in the Makefile — define
`<TOPIC>_VCD_SIGNALS := hier.path.a  hier.path.b …`, a `<TOPIC>_VCD_PROBE` that
opens a `-vcd` db and `probe -create`s each, and gate it on `ifeq ($(<TOPIC>_VCD),1)`.
Curate the signals to the question; a tight list keeps the VCD small and the parse
fast.

## Parse it (analyze_waves.py — bundled)
```bash
python3 scripts/analyze_waves.py <run>/waves.vcd                 # report key signals
python3 scripts/analyze_waves.py waves_new.vcd waves_legacy.vcd  # side-by-side A/B
```
`scripts/analyze_waves.py` ships a minimal VCD parser plus reusable primitives you
can extend for any signal set:
- `find_signal(changes, *fragments)` — locate a net by name fragments
- `first_value(changes, sig, value)` — the time a signal first reaches a value
  (e.g. reset released, EOT fired)
- `count_transitions(changes, sig)` — did a clock/line actually toggle?
- `value_at(changes, sig, time_ps)` — exact value at a time
- `fmt_time` — VCD ps → readable ns (mind the ps/ns trap; see below)

Its built-in `analyse()` checks the firmware-UART-capture chain (PRESETn released,
PCLK toggling, `reg_ctrl` HSTM bit, `tx_state` running, `TXD` transitions, capture
`rx_shift` advancing, `sim_end`/EOT). For a new problem, add a few `first_value` /
`value_at` assertions on your curated signals — the parser is generic.

## Worked pattern (how the DAC datapath bug was found)
`DAC_VCD=1` dumped `dac_clk` + the SRAM read address/enable + `ram_rdata` + a
`dacNNN_a` output; parsing showed the read-enable never asserted during
programming (SRAM→ram_rdata→DAC never flowed) — a real RTL bug, proven from the
VCD without a GUI. The same probe then *confirmed* the fix (values flowed).

## Gotchas
- **Curate, don't dump-all.** A whole-design VCD is huge and slow to parse; probe
  the ~5–20 signals that answer the question.
- **ps vs ns.** VCD times are in the file's timescale (ps here); convert before
  reporting. UVM log stamps are ps too, but the `$finish at time N NS` line is ns.
- **Absence of a transition is a finding.** `count_transitions == 0` on a clock or
  an "enable" is often the bug (stuck/ungated), not a missing probe.
- **A/B diff localizes fast.** When one run passes and one fails, the first signal
  that differs (and when) points straight at the divergence.
- Pair with `debug-bughunting` (classify: bug vs dead vs test-gap) and
  `simulation-xcelium` (the sim knobs).

## Bundled here (self-contained — no external workspace paths)

  - `scripts/analyze_waves.py`   — the no-GUI VCD parser (+ reusable primitives)
  - `references/toggle_signals.md` — signal-classification notes (what's
    observable vs stuck) used to pick probe sets and coverage exclusions

## Provenance
Distilled from the Neurophos MSIC digital flow (`verif/uvm` targeted-VCD probes +
`scripts/analyze_waves.py`). The bundled script/doc are snapshots — regenerate
against the live source if the flow evolves. The `<TOPIC>_VCD` probe blocks live
in the consuming project's sim Makefile (see the `simulation-xcelium` skill).
