Board-level (PCB) design & routing flow — schematic capture, layout, and autorouting for the
Neurophos boards (driver/backplane/control boards). Headless/CLI-driven (KiCad + Cadence SPECCTRA).

## Skills
- `skills/kicad-pcb-flow` — KiCad headless: `kicad-cli` + pcbnew Python (flatpak sandbox),
  generator-authored schematics + F8 update, Specctra DSN export / SES import, stackup & DRC via
  scripts, ERC/DRC, footprint-library lookup, deterministic-UUID / non-standard-refdes gotchas.
- `skills/allegro-specctra-routing` — headless autorouting with Cadence SPECCTRA / Allegro PCB
  Router (push-and-shove): DSN in / SES out, do-file batch, license/product/Xvfb setup, and the
  FreeRouting fallback (why greedy routers congestion-collapse on dense boards).

These pair with `implementation/skills/xilinx-fpga` (the ball-map is the shared FPGA↔PCB pinout
contract) and feed the fab handoff (Allegro conversion uses the same SPECCTRA engine).
