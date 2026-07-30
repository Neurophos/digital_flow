---
name: rnm-mixed-signal
description: Derive and integrate Real-Number Models (RNM) of analog blocks for mixed-signal UVM simulation on Neurophos SoCs — Cadence EEnet discipline, rnmgen2 netlist type-inference, the 6-phase transistor→RNM derivation flow, netlist snapshotting, and leaf authoring from Virtuoso. Use when modeling AnaTop/analog for digital-speed AMS sim or refreshing the RNM netlist.
---

# RNM / Mixed-Signal Modeling (analog↔digital integration)

## When to use
Bringing an analog block (e.g. AnaTop metasurface array) into the digital UVM
testbench as a fast Real-Number Model; refreshing the committed netlist snapshot
after an analog design change; authoring or reviewing a leaf model; deciding
whether a block is RNM-suitable.

## What RNM buys
Simulate analog behavior at **digital speed** inside the UVM TB — no Spectre in
the loop — using real-valued electrical nets instead of transistor-level. Lets
DAC/driver/pixel datapaths be verified functionally against the digital side.

## Discipline: Cadence native `EE_pkg::EEnet`
Analog nets are modeled as `EEnet` (real-number electrical, native Cadence
AMS-RNM), not `wreal`/user nettypes. Digital nets stay `logic`. The boundary is
resolved automatically (see rnmgen2). Keep leaves in this discipline.

## rnmgen2 — automated netlist → full-RNM
`verif/model/tools/rnmgen2.py <netlist.vams> <out.sv> <leaf1.sv> ...`
- **Seeds** exact port types from hand-authored leaf `.sv` (EEnet vs logic).
- **Fixpoint inference:** a net is `EEnet` iff it touches ≥1 EEnet port and 0
  logic ports; `logic` iff only logic ports; `conflict` (reported, left logic) if
  both. A module's port type = the type of its internal same-named net (propagates
  up the hierarchy).
- Retypes EEnet nets/ports, declares implicit EEnet nets, keeps logic/packed
  buses, and **de-electrifies primitives** (a 2-terminal resistor → ideal short;
  MOS/cap devices dropped) since the leaves carry the behavior.

## The 6-phase derivation flow (transistor-level → RNM)
1. **Automated topology analysis** — classify devices (tech-independent rules),
   select stimulus categories per sub-block (`pixel_hh` map).
2. **Designer interrogation** — a questionnaire (`rnm_questionnaire.csv`) captures
   intent the netlist can't express (modes, don't-cares, bias points).
3. **Spectre stimuli generation** (semi-auto) — TB1 source-follower transfer
   curve, TB2 track-and-hold settling, TB3 operating-point sweep, TB4 resistor
   characterization.
4. **Transfer-equation extraction** (semi-auto) — fit each TB's data (e.g. SF
   transfer, settling τ→RON, VSF_OFF polynomial); escalate to higher-order fit if
   residual > error budget.
5. **Designer equation review** — human checkpoint on the extracted equation table.
6. **RNM code-gen + validation overlay** — equation table → RNM parameter block;
   overlay compares RNM vs reference within the error budget.

## Netlist snapshot (extraction from OA)
The committed `.vams` netlist is a snapshot of the live OpenAccess design. Refresh
it only deliberately (analog changed): re-export from OA, then re-run rnmgen2 to
regenerate the RNM `.sv`. Keep the snapshot + generated model committed so digital
sim is reproducible without OA access. Layout under `verif/model/netlist/`.

## Leaf authoring from Virtuoso
Author/refresh leaf models directly from schematic via the F9/F10 bindkey
(`verif/model/tools/bindkeys/rnm_editor.py`, `RMgenRnm.il`). Leaves live in
`verif/model/src/leaves/`; roles in `src/roles/`.

## Applicability (flag before investing sim time)
- **Runs as-is:** SF/T&H/bias-driven datapaths (pixel/driver/DAC-facing) with
  well-separated device roles.
- **Requires modification:** feedback/oscillatory or strongly-coupled blocks.
- **Not suitable:** RF/continuous-time blocks whose behavior can't be reduced to a
  transfer table within budget — flag early.

## Key principle
The RNM must be **conservative and validated against reference**, not a guess: the
extraction → review → overlay loop exists so the model's error is bounded and
signed off, not assumed.

## Sources (MSIC)
`verif/model/README.md`, `verif/model/doc/rnm_flow.md`,
`verif/model/doc/context/{anatop-rnm-build-run,anatop-rnm-project,rnmgen2-transformer}.md`,
`verif/model/tools/rnmgen2.py`, `tools/bindkeys/{rnm_editor.py,RMgenRnm.il}`,
`verif/model/src/{leaves,roles}/`, `verif/model/netlist/`,
`doc/rnm_flow.md`, `verif/uvm/rnm_flow.md`.
