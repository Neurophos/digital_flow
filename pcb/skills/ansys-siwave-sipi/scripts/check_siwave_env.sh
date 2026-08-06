#!/usr/bin/env bash
# check_siwave_env.sh — verify the ANSYS SIwave / AEDT SI-PI toolchain is present + licensed.
# VERIFIED probes (2026-08-06): confirms AEDT install, the 27018@fs1 ANSYS license features, and
# whether PyAEDT is importable. Also confirms Cadence Sigrity is NOT licensed (so we use ANSYS).
set -uo pipefail
LMUTIL=${LMUTIL:-/tools/bin/prod/latest/lmutil}
ANSYS_LIC=${ANSYSLMD_LICENSE_FILE:-27018@fs1}
AEDT_DIR=${ELECTRONICS_INST_DIR:-/tools/ansys/electronics/2025.1/v251/AnsysEM}

echo "== AEDT install =="
if [ -d "$AEDT_DIR" ]; then
  echo "  OK  $AEDT_DIR"
  ls "$AEDT_DIR"/ansysedt 2>/dev/null && echo "  ansysedt present" || echo "  WARN ansysedt not at top level (check Linux64/)"
else
  echo "  MISSING $AEDT_DIR  (try: module load ansys)"
fi

echo "== ANSYS SI/PI license features on $ANSYS_LIC =="
for f in elec_solve_siwave siwave_level1 elec_solve_hfss elec_solve_q3d elec_solve_icepak anshpc_pack; do
  if [ -x "$LMUTIL" ]; then
    n=$("$LMUTIL" lmstat -c "$ANSYS_LIC" -f "$f" 2>/dev/null | grep -oE 'Total of [0-9]+ licenses? issued' | grep -oE '[0-9]+' | head -1)
    printf "  %-20s issued=%s\n" "$f" "${n:-0}"
  fi
done

echo "== Cadence Sigrity (expected: NONE licensed here) =="
for srv in 27000@fs1 27018@fs1 27020@fs1; do
  hit=$("$LMUTIL" lmstat -a -c "$srv" 2>/dev/null | grep -ioE 'PowerSI|PowerDC|Sigrity|SystemSI|3DEM|_Aurora' | sort -u | tr '\n' ' ')
  echo "  $srv: ${hit:-none}"
done

echo "== PyAEDT (Python automation API) =="
python3 -c "import pyaedt; print('  pyaedt', pyaedt.__version__)" 2>/dev/null \
  || echo "  NOT installed in node python -> 'pip install pyaedt' (user site), or use AEDT bundled CPython"
find "$AEDT_DIR" -maxdepth 4 -path '*CPython*' -name 'python3' 2>/dev/null | head -1 \
  | sed 's/^/  AEDT bundled python: /' || true
