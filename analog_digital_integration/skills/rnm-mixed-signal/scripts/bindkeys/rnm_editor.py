#!/usr/bin/python3.12
# ============================================================================
# rnm_editor.py -- interactive editor for the RNM (EE_pkg::EEnet) verilog.sv
# view, launched by RMgenRnm.il (bindkey F9 in a Virtuoso schematic).
#
#   python3.12 rnm_editor.py <specfile>
#
# The spec file is written by SKILL and describes one cell:
#   lib=<libName>
#   cell=<cellName>
#   view=<viewName>
#   viewdir=<abs path to the functional view dir>
#   svfile=verilog.sv
#   svpath=<abs path to verilog.sv inside viewdir>
#   [ports]
#   <name>\t<oadir>\t<type>\t<dir>      (one per line; tab separated)
#
# GUI: per-signal Direction + Type table (color-coded for pin-list changes),
# plus an editable module body. On Save it assembles verilog.sv, writes it
# into viewdir, and repoints master.tag (old tag backed up to master.tag.bak).
# Exits 0 on save, 1 on cancel, 2 on error.
#
# Pin-change color coding:
#   orange  -- new pin (present in OA symbol, absent in existing verilog.sv)
#   red     -- deleted pin (present in old verilog.sv, absent in OA symbol);
#              shown disabled at the bottom, NOT written to the output
#   normal  -- unchanged pin
# ============================================================================
import sys, os, re

TYPES = ["EEnet", "logic", "real", "wreal"]   # selectable nettypes
DIRS  = ["input", "output", "inout"]
ZSTR  = "'{V:`wrealZState, I:`wrealZState, R:`wrealZState}"
# Marker separating regenerated port declarations from the editable body.
BODY_MARK = "  // ===== RNM editable body below (header above is regenerated) ====="

# colour constants (tk foreground strings)
COL_NEW     = "#c05000"   # orange
COL_DELETED = "#bb0000"   # red
COL_NORMAL  = None        # default (inherit -- do not pass foreground kwarg)
COL_HINT    = "#555555"   # grey hint text

# ----------------------------------------------------------------------------
def parse_spec(path):
    hdr, ports, section = {}, [], None
    with open(path) as f:
        for raw in f:
            line = raw.rstrip("\n")
            if line == "[ports]":
                section = "ports"; continue
            if section == "ports":
                if not line.strip():
                    continue
                c = line.split("\t")
                ports.append({
                    "name":  c[0],
                    "oadir": c[1] if len(c) > 1 else "input",
                    "type":  c[2] if len(c) > 2 else "EEnet",
                    "dir":   c[3] if len(c) > 3 else (c[1] if len(c) > 1 else "input"),
                })
            elif "=" in line:
                k, v = line.split("=", 1)
                hdr[k.strip()] = v.strip()
    for key in ("cell", "viewdir", "svfile", "svpath"):
        if key not in hdr:
            raise ValueError("spec missing required key: %s" % key)
    return hdr, ports

# ----------------------------------------------------------------------------
def extract_old_ports(svpath):
    """Parse an existing verilog.sv and return a dict of name -> {type, dir}
    for every declared port. Returns {} if the file doesn't exist or can't be
    parsed. Used to diff the OA terminal list against the saved model."""
    try:
        txt = open(svpath).read()
    except OSError:
        return {}
    # module header: collect port names listed there
    mhdr = re.search(r'\bmodule\b\s+\w+\s*\(([^)]*)\)', txt, re.S)
    if not mhdr:
        return {}
    hdr_names = {n.strip() for n in mhdr.group(1).split(',') if n.strip()}
    # port declaration lines:  "  input  EEnet vpix, column_out;"
    decl_re = re.compile(
        r'^\s*(input|output|inout)\s+(EEnet|logic|real|wreal)?\s*(.+?)\s*;',
        re.M)
    port_info = {}
    for m in decl_re.finditer(txt):
        d = m.group(1)
        t = m.group(2) or "logic"
        for nm in [x.strip() for x in m.group(3).split(',')]:
            if nm:
                port_info[nm] = {"dir": d, "type": t}
    # fill any header names with no decl (shouldn't happen; be safe)
    for nm in hdr_names:
        if nm not in port_info:
            port_info[nm] = {"dir": "input", "type": "EEnet"}
    return port_info

# ----------------------------------------------------------------------------
def extract_body(svpath):
    """Return the editable body of an existing verilog.sv, or None.
    Prefers our BODY_MARK; otherwise falls back to stripping leading port-decl
    lines (so hand-written legacy files load cleanly without duplicating decls)."""
    try:
        txt = open(svpath).read()
    except OSError:
        return None
    e = txt.rfind("endmodule")
    if e < 0:
        return None
    if BODY_MARK in txt:
        start = txt.index(BODY_MARK) + len(BODY_MARK)
        return txt[start:e].strip("\n")
    m = re.search(r"\bmodule\b.*?\)\s*;", txt, re.S)
    if not m or e <= m.end():
        return None
    out, skipping = [], True
    for ln in txt[m.end():e].splitlines():
        if skipping and (not ln.strip() or re.match(r"\s*(input|output|inout)\b", ln)):
            continue
        skipping = False
        out.append(ln)
    return "\n".join(out).strip("\n")

def mark_deleted_refs(body, deleted_names):
    """Scan body line-by-line. Any line that:
      - is not already a comment (// ...), and
      - contains a deleted pin name as a whole word (\b boundary)
    is commented out and flagged with the TODO marker.
    Returns (modified_body, count_of_lines_changed)."""
    if not deleted_names:
        return body, 0
    pattern = re.compile(
        r'\b(' + '|'.join(re.escape(nm) for nm in sorted(deleted_names)) + r')\b')
    out = []
    count = 0
    for line in body.splitlines():
        if pattern.search(line) and not line.lstrip().startswith('//'):
            line = '// ' + line + '  // TODO - REVIEW NEEDED DUE TO PIN CHANGE'
            count += 1
        out.append(line)
    return '\n'.join(out), count

def gen_default_body(ports):
    """Stub body: ROUT param + per-output driver stubs (SPEC-TODO).
    `ports` should be the LIVE (non-deleted) port list."""
    out = ["  parameter real ROUT = 1.0e3;  // SPEC-TODO default output R (ohm)", ""]
    for p in ports:
        if p["dir"] not in ("output", "inout"):
            continue
        nm, t, d = p["name"], p["type"], p["dir"]
        if t == "EEnet":
            rhs = "'{V:0.0, I:0.0, R:ROUT}" if d == "output" else ZSTR
        elif t in ("real", "wreal"):
            rhs = "0.0"
        else:
            rhs = "1'b0" if d == "output" else "1'bz"
        out.append("  assign %s = %s;  // TODO" % (nm, rhs))
    return "\n".join(out)

def assemble(hdr, ports, body):
    """Build the full verilog.sv text from the live (non-deleted) port list."""
    cell  = hdr["cell"]
    names = [p["name"] for p in ports]
    lines = [
        "// %s -- real-number model (RNM, Cadence EE_pkg::EEnet)" % cell,
        "// Generated/edited via rnm_editor.py (RMgenRnm bindkey flow).",
        "import EE_pkg::*;",
        "module %s (" % cell,
        "    " + ",\n    ".join(names) + " );",
    ]
    for d in ("output", "inout", "input"):
        for t in ("EEnet", "real", "wreal", "logic"):
            grp = [p["name"] for p in ports if p["dir"] == d and p["type"] == t]
            if not grp:
                continue
            tfield = "" if t == "logic" else (t + " ")
            lines.append("  %-6s %s%s;" % (d, tfield, ", ".join(grp)))
    lines.append("")
    lines.append(BODY_MARK)
    lines.append(body.rstrip("\n"))
    lines.append("endmodule")
    return "\n".join(lines) + "\n"

def write_files(hdr, text):
    viewdir, svpath, svfile = hdr["viewdir"], hdr["svpath"], hdr["svfile"]
    os.makedirs(viewdir, exist_ok=True)
    with open(svpath, "w") as f:
        f.write(text)
    tag, bak = os.path.join(viewdir, "master.tag"), os.path.join(viewdir, "master.tag.bak")
    if os.path.exists(tag) and not os.path.exists(bak):
        with open(tag) as i, open(bak, "w") as o:
            o.write(i.read())
    with open(tag, "w") as f:
        f.write("-- Master.tag File, Rev:1.0\n%s\n" % svfile)

# ----------------------------------------------------------------------------
def run_gui(hdr, ports):
    import tkinter as tk
    from tkinter import ttk, messagebox, scrolledtext

    # --- compute pin diff against existing verilog.sv -----------------------
    old_ports  = extract_old_ports(hdr["svpath"])   # {} if no existing file
    cur_names  = {p["name"] for p in ports}
    old_names  = set(old_ports.keys())
    new_names  = cur_names - old_names              # in OA, not in old SV
    deleted_names = old_names - cur_names           # in old SV, not in OA

    # build deleted port records from what was parsed out of the old verilog.sv
    deleted_ports = []
    for nm in sorted(deleted_names):
        info = old_ports[nm]
        deleted_ports.append({"name": nm, "oadir": info["dir"],
                               "type": info["type"], "dir": info["dir"]})

    has_diff = bool(new_names or deleted_names)

    # --- window -------------------------------------------------------------
    root = tk.Tk()
    root.title("RNM editor -- %s/%s (%s)" % (hdr.get("lib","?"), hdr["cell"], hdr["view"]))

    ttk.Label(root,
              text="%s / %s / %s" % (hdr.get("lib","?"), hdr["cell"], hdr["view"]),
              font=("TkDefaultFont", 11, "bold")).pack(anchor="w", padx=8, pady=(8,0))
    ttk.Label(root,
              text="Set the type/direction of each signal, then edit the module body. "
                   "Save writes verilog.sv and repoints master.tag.",
              foreground=COL_HINT).pack(anchor="w", padx=8)

    # pin-change summary banner
    if has_diff:
        parts = []
        if new_names:
            parts.append("%d new pin%s" % (len(new_names), "s" if len(new_names)>1 else ""))
        if deleted_names:
            parts.append("%d deleted pin%s" % (len(deleted_names),
                                                "s" if len(deleted_names)>1 else ""))
        banner = tk.Frame(root, background="#fff3cd", padx=6, pady=4)
        banner.pack(fill="x", padx=8, pady=(4,0))
        tk.Label(banner, text="Pin list changed vs existing verilog.sv: " + ", ".join(parts) + ".",
                 background="#fff3cd", foreground="#7a5000",
                 font=("TkDefaultFont", 9, "bold")).pack(side="left")
        # legend chips
        for label, fg, bg in (("  new ", COL_NEW, "#fff3e0"),
                               ("  deleted ", COL_DELETED, "#ffebee")):
            tk.Label(banner, text=label, foreground=fg, background=bg,
                     font=("TkDefaultFont", 9, "bold"), padx=4).pack(side="right", padx=2)

    # --- scrollable signal table --------------------------------------------
    box = ttk.LabelFrame(root, text="Signals  (orange = new  |  red = deleted, not written to output)")
    box.pack(fill="both", expand=False, padx=8, pady=6)

    canvas = tk.Canvas(box, highlightthickness=0)
    vsb = ttk.Scrollbar(box, orient="vertical", command=canvas.yview)
    table = ttk.Frame(canvas)
    table.bind("<Configure>",
               lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
    canvas.create_window((0,0), window=table, anchor="nw")
    canvas.configure(yscrollcommand=vsb.set)
    canvas.pack(side="left", fill="both", expand=True)
    vsb.pack(side="right", fill="y")

    # dynamically size canvas height: ~22px per row, min 160, max 340
    n_rows = len(ports) + len(deleted_ports)
    canvas.configure(height=min(340, max(160, 30 + n_rows * 22)))

    for c, h in enumerate(["Signal", "OA dir", "Direction", "Type"]):
        ttk.Label(table, text=h, font=("TkDefaultFont", 9, "bold")).grid(
            row=0, column=c, sticky="w", padx=6, pady=(4,2))

    # rows for live (OA) ports — coloured orange if new
    live_rows = []   # (port_dict, dvar, tvar) — only these are written on Save
    for r, p in enumerate(ports, start=1):
        is_new = p["name"] in new_names
        badge  = " ★" if is_new else ""
        lbl_kw = {"foreground": COL_NEW} if is_new else {}
        tk.Label(table, text=p["name"] + badge, **lbl_kw).grid(
            row=r, column=0, sticky="w", padx=6, pady=1)
        tk.Label(table, text=p["oadir"], foreground=COL_HINT).grid(
            row=r, column=1, sticky="w", padx=6)
        dvar = tk.StringVar(value=p["dir"])
        tvar = tk.StringVar(value=p["type"])
        ttk.Combobox(table, textvariable=dvar, values=DIRS,
                     state="readonly", width=8).grid(row=r, column=2, padx=6, pady=1)
        ttk.Combobox(table, textvariable=tvar, values=TYPES,
                     state="readonly", width=8).grid(row=r, column=3, padx=6, pady=1)
        live_rows.append((p, dvar, tvar))

    # separator + deleted ports section
    if deleted_ports:
        sep_row = len(ports) + 1
        tk.Frame(table, height=1, background="#dddddd").grid(
            row=sep_row, column=0, columnspan=4, sticky="ew", padx=6, pady=4)
        tk.Label(table, text="Deleted from schematic (not written to output):",
                 foreground=COL_DELETED, font=("TkDefaultFont", 8, "italic")).grid(
            row=sep_row+1, column=0, columnspan=4, sticky="w", padx=6)
        for i, p in enumerate(deleted_ports):
            r = sep_row + 2 + i
            tk.Label(table, text=p["name"] + " ✕", foreground=COL_DELETED).grid(
                row=r, column=0, sticky="w", padx=6, pady=1)
            tk.Label(table, text=p["oadir"], foreground=COL_DELETED).grid(
                row=r, column=1, sticky="w", padx=6)
            # disabled combos showing the last-known values (read-only, informational)
            dvar = tk.StringVar(value=p["dir"])
            tvar = tk.StringVar(value=p["type"])
            ttk.Combobox(table, textvariable=dvar, values=DIRS,
                         state="disabled", width=8).grid(row=r, column=2, padx=6, pady=1)
            ttk.Combobox(table, textvariable=tvar, values=TYPES,
                         state="disabled", width=8).grid(row=r, column=3, padx=6, pady=1)

    def current_live_ports():
        """Return the live (non-deleted) ports with current table selections."""
        out = []
        for p, dvar, tvar in live_rows:
            q = dict(p); q["dir"] = dvar.get(); q["type"] = tvar.get()
            out.append(q)
        return out

    # --- body editor --------------------------------------------------------
    bframe = ttk.LabelFrame(root, text="Module body  (between port declarations and endmodule)")
    bframe.pack(fill="both", expand=True, padx=8, pady=6)
    body_txt = scrolledtext.ScrolledText(bframe, wrap="none", height=16,
                                          font=("monospace", 10), undo=True)
    body_txt.pack(fill="both", expand=True)

    existing = extract_body(hdr["svpath"])
    if existing is not None:
        if deleted_names:
            existing, n_commented = mark_deleted_refs(existing, deleted_names)
        else:
            n_commented = 0
        body_txt.insert("1.0", existing)
        msg = "Loaded existing body from %s" % hdr["svpath"]
        if n_commented:
            msg += "  |  %d line%s auto-commented (deleted pins)" % (
                n_commented, "s" if n_commented > 1 else "")
        ttk.Label(root, text=msg,
                  foreground=COL_DELETED if n_commented else "#070").pack(anchor="w", padx=8)
    else:
        body_txt.insert("1.0", gen_default_body(ports))

    # --- buttons ------------------------------------------------------------
    def on_regen():
        if messagebox.askyesno("Regenerate body",
                               "Replace the body with fresh stubs from the current table "
                               "selections? Manual edits will be lost."):
            body_txt.delete("1.0", "end")
            body_txt.insert("1.0", gen_default_body(current_live_ports()))

    def on_preview():
        text = assemble(hdr, current_live_ports(), body_txt.get("1.0", "end"))
        win = tk.Toplevel(root); win.title("Preview verilog.sv")
        t = scrolledtext.ScrolledText(win, wrap="none", width=90, height=40,
                                       font=("monospace", 10))
        t.pack(fill="both", expand=True)
        t.insert("1.0", text); t.configure(state="disabled")

    def on_save():
        live = current_live_ports()
        text = assemble(hdr, live, body_txt.get("1.0", "end"))
        try:
            write_files(hdr, text)
        except OSError as e:
            messagebox.showerror("Write failed", str(e)); return
        print("rnm_editor: wrote %s (%d live ports, %d deleted skipped); master.tag -> %s"
              % (hdr["svpath"], len(live), len(deleted_ports), hdr["svfile"]))
        root.destroy()

    def on_cancel():
        print("rnm_editor: cancelled, nothing written.")
        root.destroy(); sys.exit(1)

    bar = ttk.Frame(root); bar.pack(fill="x", padx=8, pady=(0,8))
    ttk.Button(bar, text="Regenerate body", command=on_regen).pack(side="left")
    ttk.Button(bar, text="Preview",         command=on_preview).pack(side="left", padx=4)
    ttk.Button(bar, text="Cancel",          command=on_cancel).pack(side="right")
    ttk.Button(bar, text="Save",            command=on_save).pack(side="right", padx=4)
    root.protocol("WM_DELETE_WINDOW", on_cancel)

    root.minsize(640, 580)
    root.mainloop()

# ----------------------------------------------------------------------------
def main():
    if len(sys.argv) != 2:
        sys.stderr.write("usage: rnm_editor.py <specfile>\n"); sys.exit(2)
    try:
        hdr, ports = parse_spec(sys.argv[1])
    except Exception as e:
        sys.stderr.write("rnm_editor: bad spec: %s\n" % e); sys.exit(2)
    if not ports:
        sys.stderr.write("rnm_editor: no ports in spec.\n"); sys.exit(2)
    try:
        run_gui(hdr, ports)
    except Exception as e:
        sys.stderr.write("rnm_editor: GUI error: %s\n" % e); sys.exit(2)

if __name__ == "__main__":
    main()
