# project/

Project‑level, cross‑cutting methodology (not tied to one flow area) — repository
hygiene, artifact organization, and external‑handoff/delivery conventions.

## Skills
- **`ai-artifact-separation`** — separate internal/AI working artifacts from shareable
  engineering deliverables via a `.ai/` convention, so a repo can be handed to an external
  party (PCB design house, foundry, vendor) by deleting every `.ai/` directory. Covers the
  directory pattern, the `doc/` = SPEC + THEORY_OF_OPERATION consolidation, the
  shared‑never‑links‑into‑`.ai/` invariant, the clone→strip→zip handoff builder, and the
  verification gates (no‑leak / no‑dangling‑link / share dry‑run).
