---
name: formal-verification
description: Prove block-level SVA properties with Cadence JasperGold on a Neurophos RTL block, using the pf_ed formal setup as the template — jg.tcl (analyze/elaborate/clock/reset/assume/prove), a sectioned property module, engine modes, CEX-depth reading, and the n_-vs-registered SVA pitfall. Use when writing/proving formal properties for a block. Complements uvm-block-level.
---

# Formal Verification (JasperGold, block level)

## When to use
Exhaustively proving a block's protocol/FSM invariants (passthrough, legal state
transitions, one-hot strobes, counter bounds, data correctness) — where UVM gives
breadth, formal gives an all-inputs guarantee. Template: `design/pf_ed/formal`.

## What formal actually does
It searches **all input sequences** for a counterexample (CEX) to each assert; a
property with no CEX up to its proof bound (or proven inductive) holds for all
legal inputs. `assume`s constrain the inputs to *legal* traffic (else you get
false CEXs from illegal stimulus). `cover`s prove a scenario is reachable.

## Layout
```
design/<block>/formal/
├── Makefile          prove / check / gui / report / clean
├── jg.tcl            analyze -> elaborate -> clock/reset -> assume -> prove -all
├── sva/<block>_props.sv   the property module (bound to the DUT)
├── jg_html_report.py HTML report from the latest prove results
├── mental_model.md   the "why": property taxonomy + CEX-depth guide + pitfalls
└── logs/             prove.stdout
```

## Run
```bash
cd design/<block>/formal
make check     # elaborate only — validate compile + bind (fast, no proof)
make prove     # full batch proof -> logs/prove.stdout
make report    # HTML from the latest results
make gui       # interactive JasperGold
```

## jg.tcl skeleton (from pf_ed)
```tcl
analyze -sv12 <files...>
elaborate -top <block>_wrapper
clock clk_in                              # source-synchronous: one clock domain
reset -expression {rst_in == 1'b1}        # active-high primary reset window
assume -name asm_<x>_stable { $stable(<cfg>) }        # config stable during a run
assume -name asm_<x>_range  { <sel> inside {[lo:hi]} } # legal address/id range
set_engine_mode {Ht Tri I}                # engine mix (Ht/Tri/Induction)
prove -all                                # all asserts + covers
```

## Property taxonomy (organize the property module in sections)
From pf_ed's `<block>_props.sv`: (1) **passthrough integrity**, (2) **FSM
correctness** (valid states, legal transitions, reset state), (3) **strobe
protocol** (one-hot row-enable), (4) **output protocol** (rdata OR/valid),
(5) **data correctness** (programmed value reaches the output), (6) **counter
bounds**. Keep assumes minimal and justified — an over-constraint hides bugs.

## Reading CEX depth (triage)
| Depth | Meaning |
|---|---|
| Pre-proven | True by construction (arithmetic / reset value) |
| 1–5 | Reset-phase; no interesting trace |
| 7–9 | Reachable after synchronizer delay — **where timing bugs live** |
| 30–100+ | Needs the full protocol driven (PGM_START + data beats + UPDATE) |
| Infinite (I) | Closes as an inductive invariant — proven for all time |

Timing bugs surface at shallow depth (7–9): reset releases → synchronizer
propagates → one legal command sets up state → the property fires. Short traces,
shallow bugs — formal finds them without needing a long directed test.

## The key pitfall: `n_` vs registered signals in SVA
In this RTL style every combinational output is `n_X` and `X <= n_X` at the
posedge — so there is a **one-cycle lag** between the state that *computes* a value
and the cycle where the registered `X` is *observable*. A property that checks the
registered `X` with a state-based antecedent must account for the lag:
- use `$past(fsm_st) == S` in the antecedent (check `X` the cycle after S), or
- use `|=>` instead of `|->` (check on the next cycle), or
- put the **successor** state in the antecedent (where `X` is actually visible).

Getting this wrong yields valid-RTL CEXs that are **not bugs** — they accurately
describe the intended one-cycle lag. When a CEX looks like a bug, first check
whether it's this lag before filing it.

## Complements UVM
Do both for a block: `uvm-block-level` for datapath/coverage breadth,
`formal-verification` for exhaustive protocol/FSM invariants. Formal caught 4
timing bugs in pf_ed at depth 7–9 that a directed UVM test would have to
specifically hit.

## Sources (MSIC)
`design/pf_ed/formal/` (Makefile, jg.tcl, sva/pf_ed_props.sv, mental_model.md,
jg_html_report.py), `design/pf_ed/rtl/pf_ed_wrapper.sv`.
