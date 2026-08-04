---
name: allegro-specctra-routing
description: Headless PCB autorouting with Cadence SPECCTRA / Allegro PCB Router (push-and-shove) driven from the CLI — Specctra DSN in / SES out, do-file batch, license/product/Xvfb setup. Use to route a dense board (0.5 mm-pitch LQFP / BGA fan) that greedy routers (FreeRouting) congestion-collapse on. Includes the FreeRouting fallback and why it fails.
---

# allegro-specctra-routing

## When to use
Autorouting a **dense** board headless from the CLI — many 0.5 mm-pitch LQFPs, a BGA
fanout, thousands of connections — where a **greedy ripup-retry router (FreeRouting)
congestion-collapses** (failed count climbs, never converges). SPECCTRA's **push-and-shove**
shoves existing traces aside to open room instead of just failing, so it closes boards
FreeRouting can't. Same **Specctra DSN in / SES out** flow, so it drops into a KiCad pipeline
(`ExportSpecctraDSN` → route → `ImportSpecctraSES`). It is also the engine behind the Allegro
production flow, so an in-house pre-route validates routability before a design-house handoff.

## Prerequisites (one-time, host)
- Cadence SPB/Allegro installed + a **`Allegro_PCB_Router_610`** license (check:
  `lmstat -c <server> -f Allegro_PCB_Router_610`). It is a **single seat** — one route at a time.
- The DSN/SES front-end **`specctra` is a 32-bit binary** → the 64-bit host needs 32-bit libs:
  `sudo dnf install -y glibc.i686 libstdc++.i686 libgcc.i686 libX11.i686 libXext.i686 libXt.i686 motif.i686 elfutils-libelf.i686 libxcrypt.i686`
  (satisfies its `readelf -d` NEEDED set incl. the `/lib/ld-linux.so.2` loader + Motif `libXm`).
- `Xvfb` (the router opens a Motif GUI even in batch) and `ImageMagick` (`import`) to read the
  live GUI status bar.

## Flow (verified headless invocation — all four pieces are REQUIRED)
```bash
module load cadence/allegro/25.10.010            # sets PATH + CDS_LIC_FILE
export PATH=<spb>/tools.lnx86/bin:<spb>/bin:$PATH
export LM_LICENSE_FILE=$CDS_LIC_FILE             # (1) 32-bit router reads LM_, NOT CDS_LIC_FILE
# do-file = route/write/quit ONLY (the DSN is a command-line arg, NOT `read design`):
printf 'route 25\nroute 50 16\nwrite session /abs/board.ses\nquit\n' > route.do
# (2) pin a FIXED display (not xvfb-run -a); (3) detach; (4) -product Allegro_performance:
setsid bash -c "
  /usr/bin/Xvfb :177 -screen 0 1600x1000x24 -nolisten tcp & sleep 4
  DISPLAY=:177 specctra /abs/board.dsn -do /abs/route.do -product Allegro_performance
" > specctra.log 2>&1 & disown
```
- **`route N [M]`** = N ripup-retry passes (optional via/cost arg). Typical: `route 25` (initial)
  then `route 50 16` (conflict-cleanup). End with `write session out.ses` then `quit`.
- **Read progress** two ways: the log streams per-pass `Start Route Pass N of M` /
  `Nets .. Connections .. Unroutes ..` / `Total Conflicts ..` (with a real license); and the GUI
  status bar (`Unconnects` / `Conflicts` / `Completion %`) via
  `import -display :177 -window root shot.png` (crop the bottom bar).
- **Convergence signature (good):** `Unroutes` → 0 in the first passes, then `Conflicts` fall
  monotonically toward 0 across the cleanup passes (`Completion %` climbs to ~100). A residual few
  unroutes/conflicts (BGA core) is hand-finishable.
- **Import back:** `pcbnew.ImportSpecctraSES(board, "board.ses")` → `SaveBoard`. See the
  `kicad-pcb-flow` skill for DSN export / SES import.

## Gotchas (each cost real debugging time)
1. **`LM_LICENSE_FILE=$CDS_LIC_FILE`** — the 32-bit router reads `LM_LICENSE_FILE`, not
   `CDS_LIC_FILE`. Without it: `No License file found: Entering Demo Mode: NO SAVES PERMITTED!`
   (it routes but writes no `.ses`).
2. **`-product Allegro_performance`** — the product that checks out `Allegro_PCB_Router_610`.
   Other accepted names (`SiP_Layout_XL`, `Allegro_X_Designer_Plus`) fall to Demo Mode. And with
   **no** `-product`, a **modal Product-Selection dialog blocks forever under Xvfb** (GUI spins at
   100 % CPU, never routes). Valid codes: `strings <spb>/tools.lnx86/bin/32bit/specctra | grep -i designer`.
3. **DSN on the command line, NOT `read design` in the do-file** — `read design <file>` makes it
   sit idle at 0 % CPU. Correct: `specctra board.dsn -do route.do` (`doc/spcmdref/ROcmdsS.html`).
4. **Pin a fixed display** — `Xvfb :177` + `DISPLAY=:177`, **not** `xvfb-run -a`, which auto-picks
   `:99` and **collides** with any concurrent run → `X connection to :99 broken` kills the router
   mid-route. Cadence doesn't ship Xvfb — use the system `/usr/bin/Xvfb`.
5. **`.ses` is written only at the end** (after the last `route`/`write session`) — a kill before
   that yields nothing. Detach with `setsid` so a harness/`run_in_background` can't reap the forking
   launcher; poll for the `.ses`.
6. **stdout is block-buffered when redirected to a file** — per-pass lines flush in chunks; use the
   GUI screenshot for a truly-live count.
7. **Single license seat** — coordinate concurrent boards; the second run gets Demo Mode.

## FreeRouting fallback (open-source; diagnostic-only on dense boards)
If Cadence is unavailable, FreeRouting reads the same DSN/SES but **does not close dense boards** —
its greedy ripup-retry congestion-collapses (`failed` rises monotonically; more layers / finer DRC
don't fix it). Use it only to prove a DSN parses / for sparse boards.
- **Use 1.9.0, not 2.2.4.** 2.2.4's rewritten engine NPE-crashes on plane pours; 1.9.0 (original
  maze router) ingests the full DSN with planes intact.
- 1.9.0 has **no headless mode** (`getScreenSize()` in `main` → `HeadlessException`) → run under
  `xvfb-run`. The jpackage launcher + bundled JRE are broken → run the jar with an external Java 17+:
  `xvfb-run -a java -jar freerouting-executable.jar -de board.dsn -do board.ses -mp N -mt 1`
  (`-mt 1`: the multi-threaded optimizer is broken). Never `pkill -f freerouting` (self-kills the
  shell that names it — kill by PID). It hangs after "session completed" → kill by PID.

## Escape-rule reality (applies to any router)
A router can only route what physically fits. At 0.5 mm pitch (~0.2 mm inter-pad gap), a
0.2 mm trace + 2×0.2 mm clearance (0.6 mm) **cannot** go between pins, and a 0.6 mm via needs
0.8 mm keepout. Set **fine DRC (~0.10/0.10 mm track/clearance, ≤0.40/0.20 mm via)** and enough
signal layers *before* routing — see `kicad-pcb-flow`. If a via can't fit between pins (e.g.
0.4 mm-pitch BGA/FFC) **no** autorouter can place the breakout there; that fan needs a
deterministic/interactive router.

## Bundled scripts
- `scripts/specctra_route.sh -i board.dsn -o board.ses [-d "route 25;route 50 16"]` — the whole
  verified run in one command (module + `LM_LICENSE_FILE` + `-product` + pinned Xvfb, detached, writes
  the do-file, prints how to poll for the `.ses` / read the live GUI count). Env overrides:
  `SPECCTRA_MODULE`, `SPECCTRA_PRODUCT`, `SPECCTRA_DISPLAY`, `SPB_BIN`.
- DSN export / SES import: `../kicad-pcb-flow/scripts/export_dsn.py` and `import_ses.py`.

## Sources
Distilled from a full head-to-head on a dense 6×AD5380-LQFP + Spartan-7 FGGA676 board:
FreeRouting (1.9.0/2.2.4) collapsed (~650 failed, rising); SPECCTRA closed the 8-layer + 0.1/0.1/0.4
variant (unroutes 2861→0, conflicts 24,311→~31, ~99.9 %, 33,383 tracks + 5,003 vias).
