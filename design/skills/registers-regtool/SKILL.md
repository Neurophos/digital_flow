---
name: registers-regtool
description: Generate register blocks (reg_top, reg_pkg, apb_adapter, C headers, docs) from hjson with regtool/reggen for a Neurophos SoC. Use when adding or changing peripheral registers.
---

# registers-regtool

## When to use
Adding or changing a peripheral's registers; regenerating a `reg_top`/`reg_pkg`
after editing the register `.hjson`; producing the firmware C header or the
register doc.

## External tools (versioned disk install — like the EDA tools)
`regtool` (OpenTitan-derived reggen/topgen, ~29M) and `ipxact2hjson` are **not
bundled** — they are large third-party toolchains installed on disk and pinned by
version, exactly like the Cadence/ARM EDA tools (see the `env-setup` skill).
Reference them through a versioned path / env var, **TBD**, e.g.:
```bash
export REGTOOLS_HOME=/tools/neurophos/regtools/<version>       # provides regtool.py + reggen/topgen
export IPXACT2HJSON_HOME=/tools/neurophos/ipxact2hjson/<version>
```
This repo bundles only the flow-owned glue: `scripts/Makefile.regtool` (config)
and `scripts/build_regs.pl` (cross-module orchestration).

## Flow
Register source is hjson in the module's `regs/reg_src/`. `$REGTOOLS_HOME/regtool.py`
generates every artifact; driven by `scripts/Makefile.regtool` (needs the venv):

```bash
make all        # in the module regs dir -> generates all of:
#   <reg>_reg_top.sv  <reg>_reg_pkg.sv  <reg>_apb_adapter_reg.sv
#   inc/<reg>.h (C header)   html/<reg>.html   md/<reg>.md
```
Underlying commands (venv-activated):
```
$REGTOOLS_HOME/regtool.py -r -t <rtl_dir>  <reg_src>   # RTL (reg_top / reg_pkg / apb_adapter)
$REGTOOLS_HOME/regtool.py -s -t <dv_dir>   <reg_src>   # DV RAL pkg
$REGTOOLS_HOME/regtool.py -D -t <inc_dir>  <reg_src> > <inc_dir>/<reg>.h   # firmware C header
```
IPXACT sources go through `$IPXACT2HJSON_HOME` first; `scripts/build_regs.pl`
orchestrates across modules (invoked by `build_rtl`).

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
