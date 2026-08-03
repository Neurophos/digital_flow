# Virtuoso Schematic Bindkeys — RNM Generator & Wire Tracker

Tools loaded from `.cdsinit_user` in the workspace
`/projects/msic/msic_a0/users/robson/wksp1/cds`.

```
load(".../bindkeys/RMgenRnm.il")       ; F9, F10
load(".../bindkeys/wiretracking.il")   ; F4, F5
```

---

## F9 / F10 — RNM functional-view generator

**Files:**
- `bindkeys/RMgenRnm.il` — SKILL driver
- `bindkeys/rnm_editor.py` — Python 3.12 / tkinter GUI

### What they do

| Key | Action |
|-----|--------|
| **F9** | Reads OA terminals from the selected instance (or the open schematic's symbol), writes a spec file to `/tmp`, launches the Python GUI editor async (`ipcBeginProcess`). When you click **Save** the GUI writes `verilog.sv` into the cell's `functional` view and repoints `master.tag`. |
| **F10** | Dry-run: prints the would-be `verilog.sv` to the CIW, writes nothing to disk. |

### How to invoke

1. Open a schematic that contains the cell you want to model **or** select exactly one instance of it.
2. Press **F9**.  The Python GUI opens.
3. In the GUI, set **Type** (EEnet / logic) and **Direction** (input / output / inout) for each port.
4. Edit the module body in the text area at the bottom.
5. Click **Save** — writes `<viewdir>/verilog.sv` and updates `master.tag`.
6. Refresh Library Manager to see the new/updated `functional` view.

### OA path written

```
<lib_disk_path>/<cell>/functional/verilog.sv
<lib_disk_path>/<cell>/functional/master.tag   (repointed: verilog.v → verilog.sv)
<lib_disk_path>/<cell>/functional/master.tag.bak  (first-time backup of original)
```

### Port type heuristics

Defaults applied before the GUI opens (all overridable in the GUI):

| Pattern | Default type |
|---------|--------------|
| `^ph_`, `_en$`, `_en_b$`, `^clk`, `^rst`, `_b$` | `logic` |
| everything else | `EEnet` |

Force-`inout` names (regardless of OA direction): `^diag_bus$`, `^column$`.

Both lists are tunable via globals at the top of `RMgenRnm.il`:
```skill
RMrnmDigitalPats = '("^ph_" "_en$" ...)
RMrnmForceInout  = '("^diag_bus$" "^column$")
```

### Pin-change detection

When a `verilog.sv` already exists and the schematic port list has changed:

- **Orange ★** — new port (present in schematic, not in existing file)
- **Red ✕** — deleted port (was in existing file, no longer in schematic)

Lines in the editable body that reference a deleted port are automatically commented out and flagged:
```systemverilog
// assign old_port = ...;   // TODO - REVIEW NEEDED DUE TO PIN CHANGE
```

### Idempotent round-trip

The generated file has a marker line separating the regenerated header (port decls) from the editable body:

```systemverilog
  // ===== RNM editable body below (header above is regenerated) =====
```

Re-opening and re-saving preserves the body unchanged; only the header is regenerated.

### EEnet conventions (functional view)

These views use Cadence-native **`EE_pkg::EEnet`** (from `dmsLib`, precompiled):

```systemverilog
import EE_pkg::*;

output EEnet vpix;
input  EEnet column;
output logic ph_smp;

// Drive with Thevenin struct:
assign vpix = '{V: gain*column.V - VSF_OFF, I: 0.0, R: ROUT};

// High-Z:
assign col_out = '{V:`wrealZState, I:`wrealZState, R:`wrealZState};

// Read voltage:
real v_in;
always @(column) v_in = column.V;
```

> **Note:** standalone models in `cds/rnm/*.sv` use a *different* custom package
> `ee_pkg::ee_net` with helpers `ee_vr(v,R)` / `ee_getv(net)`.
> Always use `EE_pkg::EEnet` when writing into OA functional views.

### Environment gotcha

The default `/usr/bin/python3` (3.6) lacks tkinter and crashes under Virtuoso's
`LD_LIBRARY_PATH` (points at Xcelium shared libs).  `RMgenRnm.il` scrubs the
environment and calls Python 3.12 explicitly:

```skill
RMrnmPython   = "/usr/bin/python3.12"
RMrnmEnvScrub = "/usr/bin/env -u LD_LIBRARY_PATH -u PYTHONHOME -u PYTHONPATH"
```

`DISPLAY` is intentionally kept for X11/tkinter.

---

## F4 / F5 — Wire net tracker (`wiretracking.il`)

| Key | Action |
|-----|--------|
| **F4** | Highlights the selected wire and all hierarchically connected nets. Each press uses the next color in a cycling palette. |
| **F5** | Removes all wire-tracking highlights from every open window. |

### Design notes

- **Color function auto-detection**: at load time the script probes 11 candidate
  color functions (`hiSetObjectColor`, `geSetObjectColor`, `schSetObjectFG`, …)
  with `isCallable` and uses the first callable one.  If none is found, a warning
  is printed and sessions record without visual highlights (no hang, no crash).
  Run `RMwtDiagColorFns()` in the CIW to see which functions are available.

- **Lazy hierarchy extension**: F4 records the current window only.  A 500 ms idle
  proc (`hiAddIdleProc`) extends sessions one level using only *already-open* cell
  views — no recursive `dbOpenCellViewByType`.

- **Supply net guard**: nets with more than 20 `instTerms` are skipped during
  extension (clock/supply protection).  Tune via `RMwtMaxInstTerms`.

- **CV-key cache**: a list of `"lib|cell|view"` strings prevents redundant
  re-coloring per idle tick; cleared on each F4 / F5.

### Reload

```skill
load("/projects/msic/msic_a0/users/robson/wksp1/cds/bindkeys/wiretracking.il")
```

The load banner prints the detected color function:
```
wiretracking: color function = hiSetObjectColor
wiretracking.il loaded: F4 = highlight wire | F5 = clear all.
```

If neither function is found:
```
wiretracking: no object-color function found; visual highlighting disabled.
wiretracking: run RMwtDiagColorFns() in the CIW to identify available functions.
```
Then run `RMwtDiagColorFns()` and report the output to determine the correct function.

---

## Manual reload

To reload both tools after editing:

```skill
load("/projects/msic/msic_a0/users/robson/wksp1/cds/bindkeys/RMgenRnm.il")
load("/projects/msic/msic_a0/users/robson/wksp1/cds/bindkeys/wiretracking.il")
```

Or restart Virtuoso — both files are loaded from `.cdsinit_user` automatically.
