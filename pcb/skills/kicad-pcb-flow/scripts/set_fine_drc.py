#!/usr/bin/env python3
"""set_fine_drc.py — set fine DRC (track/clearance/via) on all net classes + board minimums.

For a dense 0.5 mm-pitch escape the default 0.2/0.2/0.6 rule physically cannot route between pins;
0.10/0.10 track/clearance + 0.40/0.20 via can. Run with KiCad's sandbox Python:
    flatpak run --command=python3 org.kicad.KiCad set_fine_drc.py board.kicad_pcb [track clear via drill]  # mm

Defaults: 0.10 0.10 0.40 0.20 mm. Sets every net class (KEEP power wide separately if needed — pass
higher values or edit the PWR class after) and lowers the board-wide minimums so the values are legal.
NOTE: net-class widths also live in the .kicad_pro (net_settings.classes); for a durable, GUI-visible
change edit that JSON too (this touches the board's in-memory classes + design settings).
"""
import sys, pcbnew

board = sys.argv[1]
NM = 1_000_000
vals = [float(x) for x in (sys.argv[2:6] or [])] or [0.10, 0.10, 0.40, 0.20]
tw, cl, vd, vdr = (int(v * NM) for v in vals)

b = pcbnew.LoadBoard(board)
done = []
try:
    ncmap = b.GetAllNetClasses()                        # KiCad 7/8/9: name -> NETCLASS
    for name in ncmap.keys():
        nc = ncmap[name]
        nc.SetTrackWidth(tw); nc.SetClearance(cl); nc.SetViaDiameter(vd); nc.SetViaDrill(vdr)
        done.append(name)
except Exception as e:
    print("netclass loop err:", e)

ds = b.GetDesignSettings()
for attr, v in (("m_TrackMinWidth", tw), ("m_ViasMinSize", vd), ("m_ViasMinDrill", vdr), ("m_MinClearance", cl)):
    try: setattr(ds, attr, v)
    except Exception as e: print("designsettings %s err: %s" % (attr, e))

pcbnew.SaveBoard(board, b)
print("fine DRC set (%.2f/%.2f track/clear, %.2f/%.2f via) on classes: %s" % (*vals, done))
