---
name: registers-regtool
description: Generate register blocks (reg_top, reg_pkg, apb_adapter, C headers, docs) from hjson with regtool/reggen for a Neurophos SoC. Use when adding or changing peripheral registers.
---

# registers-regtool

## When to use
Adding or changing a peripheral's registers; regenerating a `reg_top`/`reg_pkg`
after editing the register `.hjson`; producing the firmware C header or the
register doc.

## Tools live IN the repo (not an external install)
`regtool` (OpenTitan-derived reggen/topgen) and `ipxact2hjson` are **committed to
this repo**, not installed on disk like the Cadence/ARM EDA tools. No env var to
set, nothing to `module load`:
```
utils/chip_utils/scripts/regtools/regtool.py      # + reggen/ topgen/ subdirs
utils/chip_utils/scripts/ipxact2hjson/            # IPXACT -> hjson converter
utils/chip_utils/config/Makefile.regtool          # sets REGTOOL_DIR / REGTOOL, drives generation
utils/chip_utils/scripts/build_regs.pl            # cross-module orchestration
```
`Makefile.regtool` defines `REGTOOL_DIR = $(ROOT_DIR)utils/chip_utils/scripts/regtools`
and `REGTOOL = $(REGTOOL_DIR)/regtool.py`. Read that Makefile if a path here looks
stale — it is the source of truth.

(Earlier revisions of this skill described `$REGTOOLS_HOME` /
`$IPXACT2HJSON_HOME` pointing at `/tools/neurophos/...`. Those env vars do not
exist and nothing sets them.)

## Flow
Register source is hjson in the module's `regs/reg_src/`. `regtool.py`
generates every artifact; driven by `Makefile.regtool` (needs the venv):

```bash
make all        # in the module regs dir -> generates all of:
#   <reg>_reg_top.sv  <reg>_reg_pkg.sv  <reg>_apb_adapter_reg.sv
#   inc/<reg>.h (C header)   html/<reg>.html   md/<reg>.md
```
Underlying commands (venv-activated):
```
regtools/regtool.py -r -t <rtl_dir>  <reg_src>   # RTL (reg_top / reg_pkg / apb_adapter)
regtools/regtool.py -s -t <dv_dir>   <reg_src>   # DV RAL pkg
regtools/regtool.py -D -t <inc_dir>  <reg_src> > <inc_dir>/<reg>.h   # firmware C header
```
IPXACT sources go through `ipxact2hjson` first; `scripts/build_regs.pl`
orchestrates across modules (invoked by `build_rtl`).

## Generated register RTL is NOT in git — generate it in every fresh workspace
`design/<blk>/regs/.gitignore` ignores `rtl/ dv/ inc/ html/ md/ pdf/`, so a fresh
clone has the `.hjson` sources and **no generated RTL at all**. Nothing in the sim
flow generates it on demand: the top-level UVM regression dies at compile with

```
xrun: *SE,FILEMIS: Cannot find the provided file .../design/spi_host/regs/rtl/spi_host_reg_pkg.sv
```

…times 3 files (`_reg_pkg` / `_reg_top` / `_apb_adapter_reg`) for every peripheral
with registers. In the parallel runner this surfaces as **every test failing
instantly as `FAIL (no log)`** — which looks like catastrophic breakage but is just
an unbuilt workspace. Generate all of them up front, enumerated from the design
YAML rather than hardcoded:

```bash
for d in $(utils/chip_utils/scripts/alchemy -ws $(pwd) \
             -yaml design/msic_top/config/msic_top.yaml -quiet -regs -); do
    make -C "$d" all
done
```
On MSIC that is 6 dirs / 18 files: `spi_host dac_ctrl gpio clock_ctrl chip_ctrl
fabio_tgt`. Do this **before** any top-level regression on a new checkout; see
`regression-parallel`.

## Gotchas
- **prim_subreg flattening (matters for coverage/formal):** Xcelium flattens the
  generated `prim_subreg` instances, so each field appears at the `u_reg` level as
  a flat net `<reg>_<field>_qs` (read-back) — *not* the dotted `reg2hw.<field>.q`.
  Use the `_qs` name for vRefine exclusions / signal lookups (dotted paths NOMATCH).
- The C header field offsets/masks (`<REG>_<FIELD>_OFFSET/_MASK`) are the
  firmware's source of truth — read them, don't hand-compute bit positions.
- Regenerate through `make` (venv + correct `-t` target dirs); running `regtool.py`
  by hand without the venv fails on imports.

## Bundled here (self-contained — no external workspace paths)

  - `references/register_flow.md`
  - `references/regtool_README.md`
  - `scripts/build_regs.pl`
  - `scripts/Makefile.regtool`

External (versioned disk install, TBD — see body): `regtool`/reggen/topgen,
`ipxact2hjson`.

## Provenance
Distilled from the Neurophos MSIC digital flow; the bundled `references/`
and `scripts/` are snapshots — regenerate against the live source if the
flow evolves. Command paths in the body (e.g. `verif/uvm/`, `design/<blk>/`)
are the *consuming project's* conventional layout, not this repo.
