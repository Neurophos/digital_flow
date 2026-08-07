# digital_flow

All digital development flow scripts, documentation, and methodology for
Neurophos SoC projects (MSIC and successors). Intended to be cloned as a
**git submodule** into a digital design project repo:

```bash
git submodule add git@github.com:Neurophos/digital_flow.git digital_flow
git submodule update --remote digital_flow
```

## Organization

Five flow areas, each holding its scripts/docs plus a `skills/` subdir:

| Area | Scope |
|---|---|
| `design/` | RTL build & prepro, register generation, lint, CDC |
| `verification/` | Xcelium sim, UVM, regression, coverage closure, firmware, debug |
| `implementation/` | synthesis (Genus), LEC, physical verification, **Xilinx FPGA build** |
| `analog_digital_integration/` | RNM / mixed-signal modeling, analog↔digital handoff |
| `pcb/` | board-level: KiCad schematic/layout headless flow, Cadence SPECCTRA autorouting |
| `project/` | cross-cutting: repo hygiene, artifact organization, external-handoff/delivery methodology |

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
| implementation | `xilinx-fpga` — 7-series FPGA (Vivado): ball-map→XDC, synth/impl/bitstream |
| analog_digital_integration | `rnm-mixed-signal` |
| pcb | `kicad-pcb-flow` — KiCad headless (kicad-cli + pcbnew), DSN/SES, stackup/DRC, F8 |
| pcb | `allegro-specctra-routing` — SPECCTRA/Allegro PCB Router headless (push-and-shove) |
| project | `ai-artifact-separation` — `.ai/` split of internal-vs-deliverable; clone+delete-`.ai/` external handoff |

All skills are written (When to use / Flow / Gotchas / Sources). Each `Sources`
section lists the MSIC files it distills, so it can be verified/regenerated
against the code as the flow evolves.

### Make skills invokable in a consuming project

Claude Code discovers skills under `.claude/skills/`. Symlink each skill dir
(single source of truth — edits live in this submodule):

```bash
mkdir -p .claude/skills
for d in digital_flow/*/skills/*/; do
  ln -sfn "../../${d%/}" ".claude/skills/$(basename "$d")"
done
```

**Operational notes:**
- **Discovery happens at Claude Code session start.** Newly-added/symlinked skills
  become invokable in the **next** session, not retroactively in the one where you
  wired them.
- **The symlinks point into this submodule**, so after a fresh clone of the parent
  repo they only resolve once the submodule is checked out:
  ```bash
  git submodule update --init digital_flow
  ```
  Until then the links dangle harmlessly. Re-run `git submodule update --remote
  digital_flow` to pull newer methodology, and commit the bumped pointer.
- Keep the symlinks committed in the parent repo so the whole team gets the same
  invocation wiring; local-only settings (`.claude/settings.local.json`) stay out.

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
- **Internal vs deliverable — the `.ai/` convention.** Keep AI/working artifacts
  (status/findings notes, generators & tooling, intermediate/scratch) under `.ai/`
  directories so a project stays one repo yet ships to an external party by deleting
  every `.ai/`. A shared doc must never link *into* `.ai/`. See the
  **`project/ai-artifact-separation`** skill for the directory pattern, the
  `doc/` = SPEC + THEORY_OF_OPERATION consolidation, the clone→strip→zip handoff, and
  the verification gates.
