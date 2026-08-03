# Mental Model: pf_ed Formal Verification Flow

## What the formal engine actually does

Jasper Gold treats the design as a mathematical transition system. It picks up
every possible state the design can reach after reset and asks: "for every
reachable state, does every assertion hold?" It doesn't run a test — it
exhaustively covers the entire state space. The three engines used here attack
the problem differently:

- **Ht (Heuristic Transformation)** — preprocesses the design, simplifies the
  state space, finds shallow counterexamples fast (≤10 cycles). This is what
  caught the 4 timing bugs; they were reachable in 7–9 cycles.
- **I (k-induction)** — proves properties by showing: (a) they hold in the
  reset state, and (b) if they hold for k consecutive cycles, they hold for
  cycle k+1. Most simple structural properties close this way.
- **Tri (IC3/PDR)** — proves properties by finding a strengthened inductive
  invariant automatically. Used for complex properties where k-induction alone
  doesn't converge. `ast_update_data_correct` (the preload→DAC transfer check
  with 16 local variables) was proven here in ~0.8 s.

"Proven" means the property holds for **all** reachable states, for all time —
not just the traces a simulation happened to exercise.

---

## The design as the formal engine sees it

```
                    ┌────────────────────────────────────────────┐
  rst_in ───────────┤ ni_rst_sync (4-stage sync)                 │
  clk_in ──────┬───┤                             arst_n (active-low, async)
               │   └────────────────────────────────────────────┘
               │
               ▼ clk_int (= clk_in through double-inversion, transparent in NI_BEHAVIORAL)

  addr_sel[3:0] ─── assumed stable, range [0x0..0xB]

  din[15:0]     ──── buffered passthrough ──► dout
  cmd_ndata_in  ──── buffered passthrough ──► cmd_ndata_out
  rdata_in      ──── OR'd with rdata_out_int ──► rdata_out

  ┌─────── pf_ed core ─────────────────────────────┐
  │  cmd_ndata_q, din_q      ← flopped interface   │
  │  fsm_st[2:0]             ← 5-state machine     │
  │  daca_preload[8][8]      ← staging memory      │
  │  dacb_preload[8][8]                             │
  │  row[3:0], col[3:0]      ← counters            │
  │  En[7:0]                 ← registered n_row_sel│
  │  DinA0-7, DinB0-7        ← registered DAC data │
  │  rdata_out_int           ← registered busy flag│
  └────────────────────────────────────────────────┘
```

The reset model (`rst_in == 1'b1`) holds the primary input high for an initial
window, then releases it. The 4-stage synchronizer means `arst_n` deasserts 4
clock cycles after `rst_in` goes low. During those 4 cycles the DUT flops are
still held in reset state by `arst_n=0`, but the primary inputs are already
unconstrained — this is where the short CEX paths (depth 7–9) were found.

---

## The property taxonomy

### Section 1 — Passthrough integrity

The simplest properties. With `NI_BEHAVIORAL`, every inverter-pair is a wire,
so `dout == din` is a combinational tautology. These prove trivially (depth 0,
pre-proven or 1 cycle).

### Section 2 — FSM correctness

Structural invariants about the state encoding and legal transitions. These
prove by induction: the reset state is IDLE, and for each state only one valid
successor exists. The key property here is `prop_reset_holds_idle` — it
directly images the async reset logic.

### Section 3 — Row-enable (En) protocol

The subtlety here is the **one-cycle registered lag**:

```
UPDATE0_ST:  n_row_sel = '0   (default)  →  En stays 0
UPDATE1_ST:  n_row_sel[row]=1            →  En gets one-hot   ← SET HERE
UPDATE2_ST:  n_row_sel = '0   (default)  →  En = one-hot still ← VISIBLE HERE
next state:  n_row_sel = '0              →  En = 0
```

The correct mental model: **`En` is the registered form of `n_row_sel`. It is a
delayed echo.** The one-hot value is DRIVEN in UPDATE1_ST, VISIBLE in
UPDATE2_ST, CLEARED by the following posedge. Properties must check UPDATE2_ST,
not UPDATE1_ST.

### Section 4 — rdata_out protocol

Same registered-lag issue, same mental model:

```
IDLE_ST:     n_rdata_out_int = hold(0)   →  rdata_out_int = 0
PGM_ST[0]:   n_rdata_out_int = 1         →  rdata_out_int = 0  ← entry lag
PGM_ST[1+]:  n_rdata_out_int = 1         →  rdata_out_int = 1  ← stable
PGM_ST last: n_rdata_out_int = 0         →  rdata_out_int = 1  ← still 1
IDLE_ST:     n_rdata_out_int = hold(0)   →  rdata_out_int = 0
```

The `$past(fsm_st) == PGM_ST` guard in the property skips the first entry cycle
precisely because that is an RTL implementation artefact, not a protocol bug.

### Section 5 — UPDATE data correctness

This is the most powerful property. It uses SVA local variables to capture 16
preload bytes at UPDATE0_ST time, then asserts the registered DAC outputs match
those bytes one cycle later (UPDATE1_ST). This proves that the combinational
mux → register path is correct for all 64 preload values simultaneously. It
closed with the IC3 engine — induction alone couldn't find a strong enough
invariant because the property spans two time steps and involves unpredictable
memory contents.

### Section 6 — Counter bounds

`row < 8` and `col < 8` close as pre-proven (trivial arithmetic bound on 4-bit
counters reset to 0 and incremented conditionally).

---

## What the CEX depths tell you

| Depth        | Meaning                                                                      |
|--------------|------------------------------------------------------------------------------|
| Pre-proven   | Property is true by construction (arithmetic, reset value)                   |
| 1–5          | Reset-phase property; no interesting trace needed                            |
| 7–9          | Reachable after synchronizer delay — where the 4 timing bugs lived           |
| 30–100+      | Requires driving the full protocol: PGM_START + data beats                  |
| Infinite (I) | Property closes as an inductive invariant — proven for all time              |

The 4 timing bugs were caught at depth 7–9 because: reset releases →
synchronizer propagates (4 cycles) → one valid command sets up the state → the
property fires on the first problematic cycle. Short traces, shallow bugs.

---

## The key lesson: `n_` vs registered signals in SVA

In this RTL style, every combinational output is named `n_X` and the final
value is `X <= n_X` at the posedge. When writing SVA properties that check `X`
(the registered form), there is always a **one-cycle lag** between the state
that *computed* the value and the cycle where that value is *observable*:

```
State where n_X is computed   →  State where X reflects it
UPDATE1_ST (sets n_row_sel)   →  UPDATE2_ST  (En = one-hot)
PGM_ST[0]  (sets n_rdata=1)   →  PGM_ST[1]  (rdata_out_int = 1)
UPDATE0_ST (sets n_rdata=1)   →  UPDATE1_ST  (rdata_out_int = 1)
```

Properties that check `X` with a state-based antecedent must use one of:

- `$past(fsm_st) == S` in the antecedent — to check X in the cycle **after** S
- `|=>` instead of `|->` — to check X on the **next** cycle
- The successor state in the antecedent — check where X is actually visible

Getting this wrong produces valid-RTL counterexamples that are not bugs — they
are accurate descriptions of the one-cycle lag the designer intentionally built
in.

---

## Final results

| Category    | Count | Status                          |
|-------------|-------|---------------------------------|
| Assertions  | 20    | 20 proven (100%)                |
| Cover points| 18    | 18 covered (100%)               |
| Assumptions | 2     | addr_sel stable + range [0..0xB]|

All proofs are unbounded (k-induction / IC3). The design is fully verified
against its SVA specification.
