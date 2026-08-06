#!/usr/bin/env python3
"""
siwave_dcir.py — SKELETON: PyAEDT-driven SIwave DCIR (IR-drop / current-density) on a routed board.

STATUS: UNVALIDATED SCAFFOLD (2026-08-06). No solve has been run from this repo yet. The PyAEDT API
names below follow the documented AEDT 2025.1 / PyAEDT interface but MUST be verified against the
installed version — treat every call as TO VALIDATE. Do NOT report results from this until a real
DCIR solve closes and the numbers are sanity-checked.

Purpose: quantify whether a power rail droops out of spec (the power-trace-width / IR-drop question,
e.g. DAC PWR net-class flattened 0.5->0.1 mm). Produces per-rail voltage drop + current density.

Prereqs:
  module load ansys                      # ANSYSLMD_LICENSE_FILE=27018@fs1
  pip install pyaedt                     # or AEDT bundled CPython
Inputs the USER must set (physics — garbage in => garbage out):
  RAILS below: source (VRM) refdes/pin + net + voltage, and sink pins + current budget per rail.
Run:
  python3 siwave_dcir.py board.odb.zip
"""
import sys, json, os

BOARD = sys.argv[1] if len(sys.argv) > 1 else "dac_brd.odb.zip"
OUTDIR = os.path.join(os.path.dirname(os.path.abspath(BOARD)) or ".", "siwave_dcir_out")

# ---- USER-SUPPLIED PHYSICS (edit these; placeholders derived from the DAC power tree) -------------
# per rail: source net, source component (VRM out), nominal V, tolerance, and load current budget [A]
RAILS = [
    {"net": "+1V0",     "vrm": "U55", "vnom": 1.00, "tol_pct": 5, "iload_A": 0.30},   # FPGA VCCINT (tight)
    {"net": "+5V_ANA",  "vrm": "J1",  "vnom": 5.00, "tol_pct": 5, "iload_A": None},   # 6x AD5380 + 15x ADS7953  [TODO budget]
    {"net": "+3V3",     "vrm": "J1",  "vnom": 3.30, "tol_pct": 5, "iload_A": None},   # [TODO]
    {"net": "+1V8",     "vrm": "U56", "vnom": 1.80, "tol_pct": 5, "iload_A": None},   # [TODO]
]
# --------------------------------------------------------------------------------------------------

def main():
    os.makedirs(OUTDIR, exist_ok=True)
    try:
        # TO VALIDATE: exact import surface. Options seen in PyAEDT: ansys.aedt.core.Siwave /
        # ansys.aedt.core.Edb (EDB) for layout import; class + import method name vary by version.
        from ansys.aedt.core import Siwave, Edb                      # noqa: F401
    except Exception as e:
        print("PyAEDT not importable:", e)
        print("=> pip install pyaedt, or run with AEDT bundled CPython. This is a SCAFFOLD.")
        print("Planned steps (implement + verify against the installed PyAEDT):")
        for s in [
            "1. Edb(edbpath=<translate ODB++ to .aedb>) OR Siwave().import_layout(BOARD)",
            "2. set REAL fab stackup on the EDB (dielectric heights, Er, tan-d, Cu weight)",
            "3. for each RAIL: create DCIR source (VRM pins) + sinks (load pins, iload_A)",
            "4. add SIwave DCIR analysis setup; solve (non_graphical=True)",
            "5. export per-net IR-drop + current-density; write %s/dcir.json" % OUTDIR,
            "6. compare max drop vs vnom*tol_pct -> PASS/FAIL per rail",
        ]:
            print("   ", s)
        # emit a template result so downstream parsing can be built now
        json.dump({"status": "scaffold", "board": BOARD, "rails": RAILS},
                  open(os.path.join(OUTDIR, "dcir_template.json"), "w"), indent=2)
        return

    # --- real flow goes here once the API calls are verified (kept minimal + guarded) ---
    raise NotImplementedError("Implement + verify the SIwave DCIR calls against installed PyAEDT.")

if __name__ == "__main__":
    main()
