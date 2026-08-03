---
name: rtl-build-prepro
description: Generate RTL filelists with alchemy and preprocess .pysv->.sv (Python-templated Verilog) for a Neurophos SoC. Use when compiling RTL, adding a module, or regenerating generated .sv (e.g. digital_top pin config, dac_ctrl).
---

# rtl-build-prepro

## When to use
Compiling/elaborating RTL; adding a module; regenerating a `.sv` produced from a
`.pysv` (pin config in `digital_top`, `dac_ctrl`, etc.); producing a filelist for
sim / synth / lint.

## Flow
Run from a module's `rtl/` dir (or the module dir). `ROOT_DIR` and the flow live
in `utils/chip_utils/config/Makefile.rtl`.

- **Preprocess `.pysv` → `.sv`** (Python-templated Verilog; embeds params from
  `common_data/soc_sysinfo/msic_sysinfo.yaml` via `read_sysinfo`/`read_pinout`):
  ```bash
  make prepro        # or bare `make` in the rtl dir
  # tool: utils/chip_utils/scripts/prepro -o <file>.sv <file>.pysv
  ```
- **Filelist / manifest** — `alchemy` reads the module `config/*.yaml` hierarchy
  and emits an option-file (`+incdir`, `-y`, packages, interfaces, rtl):
  ```
  alchemy -ws $ROOT_DIR -yaml <config>.yaml -top <top> -sim  run.f    # sim manifest
  alchemy ... -syn syn.f | -lef lef.f | -gds gds.f | -mmmc mmmc.tcl   # other flows
  ```
- **Compile check** — `make build_rtl` runs `xrun` over the RTL filelist (also
  runs `build_regs` first).

## Gotchas
- **Generated `.sv` may carry manual edits not in the `.pysv`.** e.g. `digital_top.sv`
  had a hand-added CoreSight ROM-table block that lived only in the `.sv`;
  regenerating from `.pysv` silently dropped it (broke `coresight_fw_discovery_test`).
  **Fold any manual `.sv` edit back into the `.pysv`** so the generator is the
  complete source of truth. Verify with `diff <regenerated.sv> <last-good.sv>` —
  the diff should be *only* your intended change.
- `.pysv` runs Python at prepro time — it's real code (loops over pins, reads the
  pinout spreadsheet); a wrong pin attribute (e.g. an input-enable `alt_ie_val=0`)
  produces functionally-dead RTL. Trace generated assigns to the pinout source.
- alchemy `+/-` suffixes select `*_sim_only` / `*_syn_only` files; `...` on a path
  = that instance + all descendants.

## Bundled here (self-contained — no external workspace paths)

  - `references/digital_design_flow.md`
  - `references/Makefile.rtl`
  - `references/msic_sysinfo.yaml`
  - `references/python_prepro.md`
  - `scripts/alchemy`
  - `scripts/compile_rtl.pl`
  - `scripts/prepro`
  - `scripts/read_pinout.py`
  - `scripts/read_sysinfo.py`

## Provenance
Distilled from the Neurophos MSIC digital flow; the bundled `references/`
and `scripts/` are snapshots — regenerate against the live source if the
flow evolves. Command paths in the body (e.g. `verif/uvm/`, `design/<blk>/`)
are the *consuming project's* conventional layout, not this repo.
