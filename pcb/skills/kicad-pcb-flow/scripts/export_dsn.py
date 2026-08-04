#!/usr/bin/env python3
"""export_dsn.py — export a Specctra DSN from a KiCad board (for the autorouter).

kicad-cli has NO Specctra export; use pcbnew. Run with KiCad's sandbox Python, e.g.:
    flatpak run --command=python3 org.kicad.KiCad export_dsn.py board.kicad_pcb board.dsn [width_um clearance_um]

pcbnew.ExportSpecctraDSN writes the Default net-class rule into the DSN. For a fine 0.5 mm-pitch
(or 0.4 mm FFC) escape you can text-patch the global width/clearance down (DSN units = 1 um):
optional args set them (default: leave whatever the board's net class exports). Prefer setting fine
DRC on the board first (see set_fine_drc.py) so the exported rule is already correct.
"""
import sys, pcbnew

board, dsn = sys.argv[1], sys.argv[2]
b = pcbnew.LoadBoard(board)
try:    ok = pcbnew.ExportSpecctraDSN(b, dsn)          # KiCad 7.99+ two-arg
except TypeError: ok = pcbnew.ExportSpecctraDSN(dsn)   # older one-arg (uses loaded board)

if len(sys.argv) >= 5:                                  # optional width/clearance patch (um)
    w, c = sys.argv[3], sys.argv[4]
    t = open(dsn, encoding="utf-8").read()
    import re
    nw = len(re.findall(r'\(width \d+\)', t)); nc = len(re.findall(r'\(clearance \d+\)', t))
    t = re.sub(r'\(width \d+\)', '(width %s)' % w, t)
    t = re.sub(r'\(clearance \d+\)', '(clearance %s)' % c, t)
    open(dsn, "w", encoding="utf-8", newline="\n").write(t)
    print("patched width x%d -> %s um, clearance x%d -> %s um" % (nw, w, nc, c))

print("ExportSpecctraDSN ->", ok, "->", dsn)
