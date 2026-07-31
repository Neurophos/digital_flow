---
name: registers-regtool
description: Generate register blocks (reg_top, reg_pkg, apb_adapter, C headers, docs) from hjson with regtool/reggen for a Neurophos SoC. Use when adding or changing peripheral registers.
---

# registers-regtool

## When to use
Adding or changing a peripheral's registers; regenerating a `reg_top`/`reg_pkg`
after editing the register `.hjson`; producing the firmware C header or the
register doc.

## Flow
Register source is hjson in the module's `regs/reg_src/`. `regtool.py`
(OpenTitan-derived reggen/topgen) generates every artifact. Driven by
`utils/chip_utils/config/Makefile.regtool` (needs the venv):

```bash
make all        # in the module regs dir -> generates all of:
#   <reg>_reg_top.sv  <reg>_reg_pkg.sv  <reg>_apb_adapter_reg.sv
#   inc/<reg>.h (C header)   html/<reg>.html   md/<reg>.md
```
Underlying commands (venv-activated):
```
regtool.py -r -t <rtl_dir>  <reg_src>      # RTL (reg_top / reg_pkg / apb_adapter)
regtool.py -s -t <dv_dir>   <reg_src>      # DV RAL pkg
regtool.py -D -t <inc_dir>  <reg_src> > <inc_dir>/<reg>.h   # firmware C header
```
IPXACT sources go through `ipxact2hjson/` first; `build_regs.pl` orchestrates
across modules (invoked by `build_rtl`).

## Gotchas
- **prim_subreg flattening (matters for coverage/formal):** Xcelium flattens the
  generated `prim_subreg` instances, so each field appears at the `u_reg` level as
  a flat net `<reg>_<field>_qs` (read-back) — *not* the dotted `reg2hw.<field>.q`.
  Use the `_qs` name for vRefine exclusions / signal lookups (dotted paths NOMATCH).
- The C header field offsets/masks (`<REG>_<FIELD>_OFFSET/_MASK`) are the
  firmware's source of truth — read them, don't hand-compute bit positions.
- Regenerate through `make` (venv + correct `-t` target dirs); running `regtool.py`
  by hand without the venv fails on imports.

## Sources (MSIC)
`utils/chip_utils/scripts/regtools/regtool.py` (+ `reggen/`, `topgen/`),
`utils/chip_utils/scripts/ipxact2hjson/`,
`utils/chip_utils/scripts/build_manifest/build_regs.pl`,
`utils/chip_utils/config/Makefile.regtool`, module `regs/` dirs,
`doc/{register_flow,regtool_README}.md`.
