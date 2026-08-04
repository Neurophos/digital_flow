#!/usr/bin/env python3
"""import_ses.py — import a routed Specctra .ses back into a KiCad board.

kicad-cli has NO Specctra import; use pcbnew. Run with KiCad's sandbox Python:
    flatpak run --command=python3 org.kicad.KiCad import_ses.py board.kicad_pcb board.ses out.kicad_pcb

Loads `board`, applies the routed session `ses`, saves to `out`, and reports track/via counts.
"""
import sys, pcbnew

board, ses, out = sys.argv[1], sys.argv[2], sys.argv[3]
b = pcbnew.LoadBoard(board)
try:    ok = pcbnew.ImportSpecctraSES(b, ses)           # KiCad 7.99+ two-arg
except TypeError: ok = pcbnew.ImportSpecctraSES(ses)    # older one-arg (uses loaded board)
pcbnew.SaveBoard(out, b)

tracks = b.GetTracks()
ntr = sum(1 for t in tracks if t.GetClass() == "PCB_TRACK")
nvia = sum(1 for t in tracks if t.GetClass() == "PCB_VIA")
print("ImportSpecctraSES ->", ok, "| tracks:", ntr, "vias:", nvia, "->", out)
