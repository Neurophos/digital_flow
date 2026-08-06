#!/usr/bin/env bash
# export_kicad_odb.sh — export a routed KiCad board to ODB++ (+ IPC-2581) for SIwave import.
# The kicad-cli subcommands are VERIFIED present (KiCad 9). SIwave-side import is TO VALIDATE.
#   export_kicad_odb.sh board.kicad_pcb [outdir]
set -euo pipefail
BOARD=${1:?usage: export_kicad_odb.sh board.kicad_pcb [outdir]}
OUT=${2:-$(dirname "$BOARD")/si_export}
CLI=$(command -v kicad-cli || echo "$HOME/bin/kicad-cli")
mkdir -p "$OUT"
base=$(basename "$BOARD" .kicad_pcb)

# ODB++ (preferred SIwave import): single zip, mm
"$CLI" pcb export odb     --units mm --compression zip -o "$OUT/$base.odb.zip" "$BOARD"
# IPC-2581 fallback (some importers prefer it; carries stackup + netlist too)
"$CLI" pcb export ipc2581 -o "$OUT/$base.xml" "$BOARD" || echo "  (ipc2581 export skipped)"

echo "exported:"
ls -la "$OUT/$base".* 2>/dev/null
echo "NEXT: import $OUT/$base.odb.zip into SIwave via scripts/siwave_dcir.py (set the REAL fab stackup)."
