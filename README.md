# digital_flow

All digital development flow scripts, documentation, and methodology for
Neurophos SoC projects (MSIC and successors). Intended to be cloned as a
**git submodule** into a digital design project repo:

```bash
git submodule add git@github.com:Neurophos/digital_flow.git digital_flow
git submodule update --remote digital_flow
```

## Organization

Four flow areas, each holding its scripts/docs plus a `skills/` subdir:

| Area | Scope |
|---|---|
| `design/` | RTL build & prepro, register generation, lint, CDC |
| `verification/` | Xcelium sim, UVM, regression, coverage closure, firmware, debug |
| `implementation/` | synthesis (Genus), LEC, physical verification |
| `analog_digital_integration/` | RNM / mixed-signal modeling, analog↔digital handoff |

## Skills (AI-invokable methodology)

Each methodology is a **Claude Code skill**: `<area>/skills/<name>/SKILL.md`, with
YAML frontmatter (`name`, `description`) so it is auto-discoverable/invokable by an
agent, and a body of **When to use / Flow / Gotchas / Sources**. The `Sources`
section lists the repo files each skill distills, so it can be verified against
the code.

| Area | Skill |
|---|---|
| design | `env-setup` |
| design | `rtl-build-prepro` |
| design | `registers-regtool` |
| design | `lint-jasper` |
| design | `cdc-jasper` |
| verification | `simulation-xcelium` |
| verification | `uvm-system-level` — top/system TB (verif/uvm) + full-chip RNM (verif/model) |
| verification | `uvm-block-level` — block unit TB (design/`<blk>`/uvm; template pf_ed) |
| verification | `formal-verification` — JasperGold block formal (design/`<blk>`/formal) |
| verification | `regression-parallel` |
| verification | `coverage-closure` |
| verification | `firmware-tbctrl` |
| verification | `debug-bughunting` |
| verification | `vcd-debug` — no-GUI VCD debug (targeted dump + `analyze_waves.py`) |
| implementation | `synthesis-impl` |
| analog_digital_integration | `rnm-mixed-signal` |

All skills are written (When to use / Flow / Gotchas / Sources). Each `Sources`
section lists the MSIC files it distills, so it can be verified/regenerated
against the code as the flow evolves.

### Make skills invokable in a consuming project

Claude Code discovers skills under `.claude/skills/`. Symlink them (single source
of truth):

```bash
for d in digital_flow/*/skills/*; do ln -s "../../$d" ".claude/skills/$(basename "$d")"; done
```

## Conventions

- **Self-contained skills.** Each `SKILL.md` bundles what it needs in its own
  directory (Claude Code format): reference docs in `references/`, the flow's own
  scripts in `scripts/`, examples in `references/examples/`. No skill points at an
  external workspace/repo to *read* — everything is here. Command paths in a skill
  body (e.g. `verif/uvm/`, `design/<blk>/`) are the *consuming project's*
  conventional layout, not this repo.
- **External tools are referenced, not bundled.** Large third-party toolchains —
  the Cadence/ARM EDA tools **and** the Neurophos `regtools` (reggen/topgen) and
  `ipxact2hjson` — are versioned disk installs pointed to by env var
  (`MDV_XLM_HOME`, `REGTOOLS_HOME`, `IPXACT2HJSON_HOME`, …; see `env-setup`). Only
  the flow's *own* glue scripts are copied in.
- Skills capture both the tool flow *and* the hard-won gotchas (the coverage
  exclusion discipline, the tb_ctrl command-handler pattern, the RNM two flows,
  the formal `n_`-vs-registered pitfall).
