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

| Area | Skill | Status |
|---|---|---|
| design | `env-setup` | stub |
| design | `rtl-build-prepro` | stub |
| design | `registers-regtool` | stub |
| design | `lint-jasper` | stub |
| design | `cdc-jasper` | stub |
| verification | `simulation-xcelium` | stub |
| verification | **`uvm-methodology`** | **full** |
| verification | `regression-parallel` | stub |
| verification | **`coverage-closure`** | **full** |
| verification | `firmware-tbctrl` | stub |
| verification | `debug-bughunting` | stub |
| implementation | `synthesis-impl` | stub |
| analog_digital_integration | **`rnm-mixed-signal`** | **full** |

Stubs have complete frontmatter (discoverable) and a Sources list; their bodies
are filled from those sources following the three full exemplars.

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
