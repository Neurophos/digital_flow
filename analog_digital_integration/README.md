Scripts, flows and documention relating to analog digital handoff and integration 

## Skills
- `skills/rnm-mixed-signal` — RNM (EEnet) modeling, in two flows:
  - **Flow A — proven (today):** `rnmgen2` assembles a full-chip RNM from
    hand-authored EEnet leaves; `make rnm`/`make sim` run and pass (role assertions).
  - **Flow B — prospective (pending proof):** the 6-phase Spectre-driven
    auto-derivation of leaf equations (`doc/rnm_flow.md`, PoC on `pixel_hh`) — the
    intended end-state, not yet proven end-to-end.
