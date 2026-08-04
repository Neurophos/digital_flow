---
name: env-setup
description: Bring up the Neurophos SoC build/sim environment — Cadence + ARM tool modules, the Python venv, MDV_XLM_HOME for coverage, and workspace/chip detection. Use at the start of any flow or whenever a fresh shell reports a missing tool.
---

# env-setup

## When to use
Starting any flow (RTL build, sim, lint, coverage, impl); a fresh/background
shell that reports `command not found` (`xrun`, `imc`, `jg`, `genus`) or a Python
import error.

## Flow
- **Tools** come from environment modules. The tool-setup fragments are included
  by the Makefiles: `utils/tool_setup/cadence_setup.make` (Xcelium, Verisium/IMC,
  JasperGold, Genus) and `arm_setup.make` (Cortex-M4 firmware toolchain). By hand:
  ```bash
  source /usr/share/Modules/init/bash
  module load cadence/vmanager/25.09.003     # IMC / Verisium
  # (xcelium / jaspergold / genus modules similarly, per cadence_setup.make)
  ```
- **Python venv** at `scripts/venv` (used by prepro, regtool, pinout, docgen):
  ```bash
  source activate_venv.sh                    # builds venv from requirements.txt if missing
  ```
  Add packages via `pip` and update `scripts/requirements.txt`.
- **Coverage engine** — `imc` needs Xcelium on `MDV_XLM_HOME`; the `make cov_*`
  targets set it via `IMC_LOAD`, but a bare `imc` in a fresh shell needs:
  ```bash
  export MDV_XLM_HOME=/tools/cadence/xcelium/25.09.001
  ```
  else `*E,coverage_engine_lib.not_found_env`.
- **Internal tools need NO env setup** — unlike the EDA tools, the Neurophos
  toolchains are committed to this repo and resolved from `ROOT_DIR` by the
  Makefiles. Nothing to export, nothing to `module load`:
  ```
  utils/chip_utils/scripts/regtools/regtool.py   # reggen/topgen (registers-regtool)
  utils/chip_utils/scripts/ipxact2hjson/         # IPXACT -> hjson
  utils/chip_utils/scripts/alchemy               # filelist generator (rtl-build-prepro)
  utils/chip_utils/scripts/prepro                # .pysv -> .sv
  ```
  (`REGTOOLS_HOME` / `IPXACT2HJSON_HOME` appeared in earlier revisions of this
  skill and in `registers-regtool`; no such env vars exist and nothing sets them.)
- **Workspace / chip** — `ROOT_DIR := $(git rev-parse --show-toplevel)/` anchors
  every Makefile; `scripts/which_chip.pl` resolves the active chip from `ROOT_DIR`;
  `scripts/Makefile.ws` sets workspace paths.

## Gotchas
- Module state and env vars do **not** persist across background/detached shells —
  re-source per shell (this bites `imc` via missing `MDV_XLM_HOME`).
- Path convention: `/projects/<soc>/<soc_rev>/users/<unix_id>/`.
- EDA tools exist only in the Neurophos compute environment.

## Bundled here (self-contained — no external workspace paths)

  - `scripts/activate_venv.sh`
  - `scripts/arm_setup.make`
  - `scripts/cadence_setup.make`
  - `scripts/Makefile.ws`
  - `scripts/requirements.txt`
  - `scripts/which_chip.pl`

## Provenance
Distilled from the Neurophos MSIC digital flow; the bundled `references/`
and `scripts/` are snapshots — regenerate against the live source if the
flow evolves. Command paths in the body (e.g. `verif/uvm/`, `design/<blk>/`)
are the *consuming project's* conventional layout, not this repo.
