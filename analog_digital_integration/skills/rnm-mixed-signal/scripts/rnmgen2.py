#!/usr/bin/env python3
# rnmgen2.py <netlist.vams> <out.sv> <leaf1.sv> ...
# PRECISE per-net type inference -> full-RNM EEnet netlist.
#   * leaf .sv seed exact port types (EEnet vs logic).
#   * fixpoint: each net's type = EEnet iff it touches >=1 EEnet port and 0 logic ports;
#     'logic' iff only logic ports; 'conflict' if BOTH (reported, left as logic).
#   * a module's port type = the type of its internal same-named net (propagates up).
#   * retype EEnet nets/ports, declare implicit EEnet nets, keep logic/packed buses,
#     de-electrify primitives (2-term resistor -> ideal short).
import sys, re
netlist, outfile = sys.argv[1], sys.argv[2]; leaves = sys.argv[3:]
RES={'rm8w','rmzw','resistor','rupolym_m'}
OTHER={'pch_25_mac','nch_25_mac','pch_mac','nch_mac','cfmom_2t','pwdnw','dnwpsub','nwdio'}
KW={'wire','input','output','inout','assign','module','endmodule','reg','logic','parameter',
    'localparam','genvar','generate','endgenerate','real','initial','always','EEnet','tri',
    'supply0','supply1','defparam','specify','endspecify','for','if','begin','end'}
base=lambda n:re.sub(r'\[.*$','',n.strip()).strip()
conn_re=re.compile(r'\.(\w+)\s*\(\s*([^()]*?)\s*\)')

# ---- seed leaf port types ----
ptype={}   # module -> {port: 'ee'|'logic'}
leaf_mods=set()   # modules provided externally (.sv) -> seed types, do NOT emit from netlist
for p in leaves:
    t=open(p).read(); m=re.search(r'\bmodule\s+(\w+)\s*\((.*?)\)',t,re.S)
    if not m: continue
    mod=m.group(1); leaf_mods.add(mod); allp=[base(x) for x in m.group(2).split(',') if x.strip()]
    eep=set()
    for mm in re.finditer(r'(?:input|output|inout)\s+EEnet\s+([^;]+);',t):
        for tok in mm.group(1).split(','): eep.add(base(tok))
    ptype[mod]={pp:('ee' if pp in eep else 'logic') for pp in allp}

# ---- parse netlist.vams ----
src=open(netlist).read()
src=re.sub(r'(?m)^`(worklib|view)\b.*\n','',src)
src=re.sub(r'(?m)^.*`include "(disciplines|userDisciplines)\.vams".*\n','',src)
mod_re=re.compile(r'\bmodule\s+(\w+)\s*\((.*?)\)\s*;(.*?)\bendmodule',re.S)
mods={m.group(1):{'ports':[base(x) for x in m.group(2).split(',') if x.strip()],'body':m.group(3)}
      for m in mod_re.finditer(src)}
inst_re=re.compile(r'(?m)^[ \t]*(\w+)\s+(\w+)\s*\((.*?)\)\s*;',re.S)
insts={}
for mn,md in mods.items():
    lst=[]
    for im in inst_re.finditer(md['body']):
        if im.group(1) in KW: continue
        lst.append((im.group(1),[(c.group(1),base(c.group(2))) for c in conn_re.finditer(im.group(3))]))
    insts[mn]=lst
    if mn not in ptype: ptype[mn]={pp:'?' for pp in md['ports']}

# ---- fixpoint type inference ----
ntype={mn:{} for mn in mods}; conflicts=set()
for _ in range(300):
    chg=False
    # ---- UP: net type from child leaf/struct ports (+ sticky ee already on the net) ----
    for mn in mods:
        touch={}   # net -> [ee?, logic?]
        for master,conns in insts[mn]:
            if master in OTHER: continue         # devices are commented out -> no nets
            if master in RES:                    # resistor -> ideal voltage short -> terminals are EEnet
                for port,net in conns:
                    if net: touch.setdefault(net,[False,False])[0]=True
                continue
            pt=ptype.get(master,{})
            for port,net in conns:
                if not net: continue
                t=pt.get(port,'logic')      # unknown master port -> logic
                d=touch.setdefault(net,[False,False])
                if t=='ee': d[0]=True
                elif t=='logic': d[1]=True
        for net,cur in ntype[mn].items():
            if cur=='ee': touch.setdefault(net,[False,False])[0]=True   # sticky (e.g. pushed down)
        for net,(ee,lo) in touch.items():
            nt='ee' if (ee and lo) else 'ee' if ee else 'logic' if lo else '?'
            if ee and lo: conflicts.add((mn,net))
            if ntype[mn].get(net)!=nt: ntype[mn][net]=nt; chg=True
        for pp in mods[mn]['ports']:    # module port type = its internal net type
            nt=ntype[mn].get(pp)
            if nt=='ee' and ptype[mn].get(pp)!='ee': ptype[mn][pp]='ee'; chg=True
            elif nt=='logic' and ptype[mn].get(pp) not in ('ee','logic'): ptype[mn][pp]='logic'; chg=True
    # ---- DOWN: push a parent's ee net into the child instance's port (and its net) ----
    for mn in mods:
        for master,conns in insts[mn]:
            if master in (RES|OTHER): continue
            for port,net in conns:
                if ntype[mn].get(net)=='ee':
                    if master in mods:                       # structural child: propagate ee down
                        if ntype[master].get(port)!='ee':
                            ntype[master][port]='ee'; ptype[master][port]='ee'; chg=True
                    elif ptype.get(master,{}).get(port)=='logic':   # parent ee -> leaf logic port
                        conflicts.add((mn,net))
    if not chg: break

REAL={mn:{n for n,t in ntype[mn].items() if t=='ee'} for mn in mods}

# ---- emit ----
decl_re=re.compile(r'^(\s*)(wire|input|output|inout)\s+(\[[^\]]+\]\s*)?(.+?)\s*;\s*$')
def xform(mn,body):
    R=REAL[mn]; ports=set(mods[mn]['ports']); declared=set(); out=[]; lines=body.split('\n'); i=0
    while i<len(lines):
        s=lines[i].strip()
        is_decl=re.match(r'^(wire|input|output|inout)\b',s)
        sp=s.split('(')[0].split(); is_prim=bool(sp) and sp[0] in (RES|OTHER) and re.match(r'^\w+\s+\w+\s*\(',s)
        if is_decl or is_prim:
            stmt=lines[i]
            while ';' not in stmt and i+1<len(lines): i+=1; stmt+='\n'+lines[i]
            flat=re.sub(r'\s+',' ',stmt.replace('\n',' ')).strip()
            dm=decl_re.match(flat)
            if dm:
                ind,kw,rng,names=dm.group(1),dm.group(2),(dm.group(3) or '').strip(),dm.group(4)
                ee=[x.strip() for x in names.split(',') if x.strip() in R]
                di=[x.strip() for x in names.split(',') if x.strip() not in R]
                pre='' if kw=='wire' else kw+' '
                for x in ee:
                    out.append(f"{ind}{pre}EEnet {x}{(' '+rng) if rng else ''};")
                    if kw=='wire': declared.add(x)
                if di: out.append(f"{ind}{kw} {rng+' ' if rng else ''}{', '.join(di)};")
                i+=1; continue
            pm=re.match(r'^(\s*)(\w+)\s+(\w+)\s*\(\s*(.*?)\)\s*;\s*$',flat)
            if pm and pm.group(2) in (RES|OTHER):
                ind,master,conns=pm.group(1),pm.group(2),pm.group(4)
                out.append(f"{ind}// [RNM] removed {master}")
                if master in RES:
                    t=dict((k,v.strip()) for k,v in conn_re.findall(conns))
                    if 'PLUS' in t and 'MINUS' in t:
                        out.append(f"{ind}assign {t['MINUS']} = '{{V:{t['PLUS']}.V, I:0.0, R:0.0}};")
                i+=1; continue
            out.append(stmt); i+=1; continue
        out.append(lines[i]); i+=1
    implicit=sorted(R-ports-declared)
    return ''.join(f"  EEnet {x};\n" for x in implicit)+'\n'.join(out)

def emit(m):
    if m.group(1) in leaf_mods:   # provided by external .sv -> drop netlist's (empty/schematic) copy
        return f"// [rnmgen2] module {m.group(1)} provided externally"
    return f"module {m.group(1)} ({m.group(2)});{xform(m.group(1),m.group(3))}\nendmodule"
newsrc=mod_re.sub(emit,src)
open(outfile,'w').write("import EE_pkg::*;  // rnmgen2\n"+newsrc)
tot=sum(len(v) for v in REAL.values())
sys.stderr.write(f"rnmgen2: {len(mods)} modules, {tot} EEnet nets, {len(conflicts)} conflict net(s)\n")
for c in sorted(conflicts)[:20]: sys.stderr.write(f"  CONFLICT {c[0]}::{c[1]} (touches analog AND digital)\n")

# ============================================================================
#  ADDITIVE role stamping (does NOT alter the emitted netlist above).
#  Classifies each already-typed EEnet net by NAME and writes:
#    <out>.roles.csv          module,net,role  (all modules)
#    <out>_roles_bind.sv      bind <top> chk_* ... for top-level VDD/GND/BIAS nets
#  Roles are labels, not types (nettypes can't be typedef'd) -> safe by construction.
# ============================================================================
ROLE_RULES=[
  ('GND',    re.compile(r'(^|_)(gnd|gnda|gndc|gndr|vss|vsub)(_|$|\d)')),
  ('VDD',    re.compile(r'(^|_)(vdd|vddr|vddc|vddh|vddl|vcc|vdd2p5)(_|$|\d)')),
  ('BIAS_V', re.compile(r'(^|_)(vcm|vref|vgcsn|vgcsp|vbp|vbn|vbias|vcas|vts)(_|$|\d)')),
  ('BIAS_I', re.compile(r'(^|_)(ibg|iti|ibias|iref|iptat)(_|$|\d)')),
  ('DIAG',   re.compile(r'(^|_)(diag|anatst|tst)(_|$|\d)')),
]
def role_of(net):
    b=net.lower()
    for role,rx in ROLE_RULES:
        if rx.search(b): return role
    return 'SIGNAL_V'
CHK ={'VDD':'chk_vdd','GND':'chk_gnd','BIAS_V':'chk_bias'}
CHKB={'VDD':'chk_vdd_bus','GND':'chk_gnd_bus','BIAS_V':'chk_bias_bus'}
# ---- per-domain windows (V). First substring match wins; specific BEFORE generic. SPEC-TODO ----
VDD_DOMAINS=[('vddh',(3.0,3.6)),('vddr',(2.3,2.7)),('vdd2p5',(2.3,2.7)),
             ('vddc',(2.3,2.7)),('col_vdd',(2.3,2.7)),('vddl',(0.8,1.0)),('vdd',(0.8,1.0))]
BIAS_DOMAINS=[('vts',(0.4,1.4)),('vcm',(0.4,1.4)),('vgcs',(0.0,2.5))]
def vwin(net,table,dflt):
    nl=net.lower()
    for key,win in table:
        if key in nl: return win
    return dflt
stem=outfile[:-3] if outfile.endswith('.sv') else outfile
with open(stem+'.roles.csv','w') as rf:
    rf.write('module,net,role\n')
    for mn in sorted(REAL):
        for net in sorted(REAL[mn]): rf.write(f"{mn},{net},{role_of(net)}\n")
TOP='anatop'; nb=0
am=re.search(r'\bmodule\s+anatop\b.*?\bendmodule', newsrc, re.S)
atxt=am.group(0) if am else ''
def width(net):   # unpacked EEnet array width from the generated anatop decl, else scalar
    m=re.search(r'EEnet\s+'+re.escape(net)+r'\s*\[(\d+):(\d+)\]', atxt)
    return abs(int(m.group(1))-int(m.group(2)))+1 if m else 1
if TOP in REAL:
    with open(stem+'_roles_bind.sv','w') as bf:
        bf.write(f"// auto-generated role-checker binds for {TOP} (additive; needs ee_roles.sv)\n")
        for net in sorted(REAL[TOP]):
            r=role_of(net)
            if r not in CHK: continue
            w=width(net)
            if r=='VDD':      a,b=vwin(net,VDD_DOMAINS,(0.7,3.6)); p=f'.VMIN({a}),.VMAX({b}),.NAME("{net}")'
            elif r=='BIAS_V': a,b=vwin(net,BIAS_DOMAINS,(0.0,3.6)); p=f'.VMIN({a}),.VMAX({b}),.NAME("{net}")'
            else:             p=f'.NAME("{net}")'   # GND uses default TOL
            if w<=1: bf.write(f'bind {TOP} {CHK[r]} #({p}) cr_{net} (.n({net}));\n')
            else:    bf.write(f'bind {TOP} {CHKB[r]} #(.N({w}),{p}) cr_{net} (.n({net}));\n')
            nb+=1
sys.stderr.write(f"rnmgen2 roles: stamped {sum(len(v) for v in REAL.values())} nets -> {stem}.roles.csv ; {nb} top binds -> {stem}_roles_bind.sv\n")
