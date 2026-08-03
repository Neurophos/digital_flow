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

- **Reference, don't fork:** chip-specific scripts are pointed to in place (paths
  in each skill's Sources); only chip-agnostic scripts/templates are copied here
  (`verification/scripts/`, `verification/templates/`, …).
- Skills capture both the tool flow *and* the hard-won gotchas (e.g. the coverage
  exclusion discipline, the tb_ctrl command-handler pattern, the RNM derivation
  loop).
