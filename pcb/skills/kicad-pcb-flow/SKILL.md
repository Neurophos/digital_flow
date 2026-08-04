---
name: kicad-pcb-flow
description: Drive KiCad PCBs headless from the CLI — kicad-cli + pcbnew Python (flatpak sandbox), generator-authored schematics + F8 update, Specctra DSN export / SES import, stackup & DRC via scripts, ERC/DRC, footprint-library lookup, and the deterministic-UUID / non-standard-refdes gotchas. Use to build, modify, or check a KiCad board programmatically.
---

# kicad-pcb-flow

## When to use
Building/modifying a KiCad board without the GUI: authoring schematics from a generator,
scripting board edits (layers, DRC, nets, footprints) via pcbnew, exporting a Specctra DSN for
autorouting (see `allegro-specctra-routing`), importing the routed SES, running ERC/DRC, and
producing fab output.

## Setup
- **`kicad-cli`** (KiCad 10, flatpak): `~/bin/kicad-cli` → `flatpak run --command=kicad-cli org.kicad.KiCad`.
  Needs `flatpak override --user org.kicad.KiCad --filesystem=host --filesystem=/tmp` to read the repo / write `/tmp`.
- **pcbnew Python** runs only in the sandbox: `flatpak run --command=python3 org.kicad.KiCad script.py`.
  The host `python3` cannot `import pcbnew`.
- **Standard libraries** live inside the flatpak: list them headless via
  `flatpak run --command=sh org.kicad.KiCad -c 'ls /app/extensions/Library/Footprints/footprints/<Lib>.pretty'`.

## Flow
**Generator-authored schematics (deterministic-UUID pattern).** A Python generator emits
`.kicad_sch` with **deterministic symbol UUIDs** (`uuid5(NS, "sym:"+refdes)`) so a regen re-links
to the same PCB footprints. Regen the schematics, then the user opens KiCad and runs
**Update-PCB-from-Schematic (F8)** — there is **no headless F8**; only the user's GUI applies the
netlist to the board. Guard emitted `.kicad_pcb` / `.kicad_pro` with keep-if-exists so a regen
never clobbers the GUI-enriched project (DRC rules / net classes).

**pcbnew board edits (sandbox Python):**
```python
import pcbnew
b = pcbnew.LoadBoard(path)
b.SetCopperLayerCount(8)                                    # add layers
b.SetLayerName(pcbnew.In5_Cu, "SIG5"); b.SetLayerType(pcbnew.In5_Cu, pcbnew.LT_SIGNAL)
pcbnew.ZONE_FILLER(b).Fill(b.Zones())                      # re-pour planes after a stack change
pcbnew.SaveBoard(path, b)
```
**Stackup & DRC** are best kept in build scripts (durable across rebuilds): the stackup (copper
layers + `(stackup ...)` block) via a pcbnew script; DRC (net-class `track_width`/`clearance`/
`via_diameter`/`via_drill` + `design_settings.rules` minimums) written into the `.kicad_pro` JSON.
For dense 0.5 mm-pitch escape use **0.10/0.10 mm track/clearance, 0.40/0.20 mm via** (keep power
nets wide, ~0.5 mm).

**DSN export / SES import** (kicad-cli has NEITHER — use pcbnew):
```python
pcbnew.ExportSpecctraDSN(board, "board.dsn")               # for the autorouter
pcbnew.ImportSpecctraSES(board, "board.ses")               # bring routes back; then SaveBoard
```
Export a **fresh** DSN from the current board each time — a stale DSN silently drops recently-added
nets.

**Checks / output (kicad-cli):**
```bash
kicad-cli sch erc --exit-code-violations board.kicad_sch -o erc.rpt
kicad-cli pcb drc --schematic-parity board.kicad_pcb -o drc.rpt
kicad-cli pcb export gerbers / drill / svg / step
kicad-cli sch export netlist --format kicadsexpr        # (no DSN export here — see above)
```

## Gotchas
- **No headless F8 / DSN / SES.** PCB-update-from-schematic is GUI-only; DSN export and SES import
  are pcbnew-only. Plan the loop around the user running F8.
- **Non-standard refdes duplicate on F8.** Descriptor refdes (`J_USB1`, `U_VREF1`, `RINT1`,
  `C_REFIO1`) get re-annotated by KiCad → their symbol UUIDs drift from the generator's `ref_uuid`
  → on the next F8 the board footprints don't match and get **duplicated** (orphan = footprint with
  no `(path)`). Fix: use **standard `<CLASS><N>` refdes** (a `REFMAP` remap in the generator);
  clean stale orphans with F8's "Delete footprints with no symbols".
- **Random vs deterministic UUIDs.** Symbol *instance* UUIDs must be `uuid5`-deterministic (F8
  matching); label/pin/power-flag UUIDs can be random (cosmetic diff only). A generator that
  randomizes symbol UUIDs breaks the kept PCB link.
- **Footprint naming.** KiCad names a male DE-9 `DSUB-9_Pins_...` (female `DSUB-9_Socket_...`), not
  `_Male_`. `kicad-cli sch erc` flags a wrong footprint string as `footprint_link_issues` — use it
  to validate.
- **Fine-pitch mask.** `solder_mask_bridge` on a fine-pitch part usually means the footprint's pad
  `solder_mask_margin` is too large (openings overlap). Fix the footprint margin, not the board rule.
- **`copper_edge_clearance` at a connector** is often the part's own NPTH mounting holes (treated as
  edges), not the board outline — lower `min_copper_edge_clearance` (e.g. 0.25 mm) rather than moving
  the part.
- **Never `pkill -f <tool>` from a script that names the tool** — `-f` matches the running shell's
  own command line → self-kill (exit 144). Kill background jobs by PID.

## Sources
KiCad 10 (flatpak) headless flow; generator-authored DAC/backplane schematics with deterministic
UUIDs; pcbnew stackup/DRC scripting; Specctra DSN/SES round-trip into `allegro-specctra-routing`.
