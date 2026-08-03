# RNM Derivation Flow: Transistor-Level to Real-Number Model

**Proof of concept block:** `msic_a0/pixel_hh` (S/H + source-follower pixel)  
**Discipline:** Cadence native `EE_pkg::EEnet` (V/I/R, Kirchhoff resolution)  
**Principle:** Spectre transistor-level simulation is the **golden reference and extraction engine**.
No transistors are replaced by RNM primitives — the transistors run as-is in Spectre and
produce the behavioral equations the RNM implements.

---

## Flow Map

```
Any transistor-level subckt (e.g. pixel_hh.scs)
         │
         ▼
┌─────────────────────────────────────────────────────────┐
│ PHASE 1  Topology Analysis (automated)                  │
│  parse netlist → classify devices → map sub-blocks      │
│  identify: which equations need extraction              │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
              All device classes known?
              No ──► add classifier rule, re-run
              Yes ──► select stimulus category
                         │
         ┌───────────────┼───────────────┬───────────────┐
    Sampling/S-H    Amp / Filter    Threshold/Ref   Oscillator
    (pixel_hh)     (OTA, LDO)     (comparator)      (VCO)
    TB1-TB4        TB_AC+DC        TB_ramp+temp     TB_freq
         │               │               │               │
         └───────────────┴───────────────┴───────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ PHASE 2  Designer Interrogation (human checkpoint 1)    │
│  structured questionnaire: A/B/C/D sections             │
│  gates: operating range, intent, error budget,          │
│         resistor treatment, corner coverage             │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ PHASE 3  Spectre Stimuli Generation (semi-automated)    │
│  auto-generate testbenches from Phase 1+2 answers:      │
│  TB1: transfer curve (SF gain, VSF_OFF)                 │
│  TB2: S/H settling (RON, C, tau, charge injection)      │
│  TB3: operating-point sweep (VSF_OFF vs. bias, T)       │
│  TB4: resistor characterization (actual PDK R values)   │
│  run: spectre -batch TB1..TB4  →  PSF/CSV output        │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ PHASE 4  Transfer Equation Extraction (semi-automated)  │
│  curve fit: linear → quadratic → piecewise (auto-order) │
│  output: equation table + confidence bounds per corner  │
│          (gain, VSF_OFF, RON, C, tau, R_PDK, droop...)  │
└────────────────────────┬────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ PHASE 5  Designer Equation Review (human checkpoint 2)  │
│  validate each extracted parameter                      │
│  flag nuances: nonlinearity, body effect, ISI, mismatch │
│  sign off: constant vs. polynomial VSF_OFF?             │
│            absorb charge injection or model separately?  │
│            R_Rdaca negligible or finite-R model needed?  │
└────────────────────────┬────────────────────────────────┘
                         │
                  Signed off?
                  No ──► revise stimuli / model order (Phase 3/4 loop)
                  Yes ──►
                         │
                         ▼
┌─────────────────────────────────────────────────────────┐
│ PHASE 6  RNM Code Generation + Validation Overlay       │
│  auto-generate verilog.sv from signed-off table         │
│  run same stimuli: Spectre (golden) vs. RNM (candidate) │
│  error = |V_Spectre - V_RNM| per node per corner        │
│  compare against designer error budget (D2)             │
└────────────────────────┬────────────────────────────────┘
                         │
               Within error budget?
               Yes ──► commit to OA functional view
               No  ──► escalate model order, restrict
                        operating range, or flag as
                        "not RNM-suitable" (see §Limitations)
```

---

## Phase 1 — Automated Topology Analysis

**Input:** transistor-level Spectre subckt (`.scs`)  
**Output:** sub-block map, stimulus category, equation list

### Device classification rules (technology-independent)

| Connectivity pattern | Inferred function | `pixel_hh` example |
|---|---|---|
| Gate = digital control net | Switch | `MN<0,1>` (ph_smp), `MP<0,1>` (ph_smp_b) |
| Diode-connected or gate = drain | Current source / diode | `MPcurr`, `MNcurr` |
| Source drives output, drain to supply | Source follower | `MPsf` |
| Differential pair to a load | Amplifier / comparator | — |
| Capacitor from signal to reference | Sampling / hold | `Csamp<0,1>` (cfmom) |
| Resistor in signal path | Routing / degeneration | `Rdaca`, `Rvddc`, `R1`, `R3` (rmzw) |
| Ring of inverters | Oscillator | — |

### Stimulus category selection

| Category | Block types | Key stimuli |
|---|---|---|
| **Sampling / S-H** | Pixel, T/H, SC, ADC input | ph_smp pulse + column step |
| **Amp / Filter** | OTA, op-amp, LDO, Gm-C | AC sweep + DC ramp + load step |
| **Threshold / Reference** | Comparator, bandgap, level-shift | Slow ramp + temperature sweep |
| **Oscillator** | VCO, ring, relaxation | Freq vs. Vctrl; not a voltage-transfer model |

### `pixel_hh` sub-block map

```
pixel_hh
├── SUB-BLOCK 1: Sampling network (Track/Hold)
│     Devices: Csamp<0,1>, MN<0,1> (ph_smp), MP<0,1> (ph_smp_b), MNdum, MPdum
│     Key node: sample (internal)
│     Equations: V(sample) = f(V(column), RON, C, t_settle, charge_injection)
│
├── SUB-BLOCK 2: Source follower (Signal buffer)
│     Devices: MPsf, MPcurr (vgcsp bias), MNcurr (vgcsn tail), Mn1min, Mn2min
│     Key node: vpix (output)
│     Equations: V(vpix) = gain_SF × V(sample) − VSF_OFF(vgcsp, vgcsn, T)
│
├── SUB-BLOCK 3: Diagnostic readout
│     Devices: M6 (PMOS, diag_en_b), M7 (NMOS, diag_en)
│     Key node: diag_bus
│     Equations: V(diag_bus) = V(vpix) when diag_en=1, else Hi-Z
│
└── SUB-BLOCK 4: Routing resistors  [NOT ideal shorts — actual PDK R values]
      Devices: Rdaca (column→column_out, l=30n/w=1u)
               Rvddc (l=30n/w=850n), R1 (l=30n/w=1.25u), R3 (l=30n/w=600n)
      Equations: V(x_out) = V(x_in) − I_load × R_PDK
                 R_PDK = Rsheet × (L/W) [from PDK, not approximated as 0]
```

> **Resistor treatment:** Routing resistors are actual impedance elements in the
> signal path. An ideal short (`R=0`) misses IR drop under load, RC bandwidth
> limits, and thermal noise. Each `rmzw` is characterized by a dedicated Spectre
> DC extraction (TB4) and appears as a finite `R:` in the EEnet Thevenin model.

---

## Phase 2 — Designer Interrogation (Questionnaire)

Completed before any simulation is run. Answers gate which testbenches are generated and at what fidelity. Sections A and D are universal; B and C are auto-customized from the Phase 1 topology map.

```
══════════════════════════════════════════════════════════════════
  RNM EXTRACTION — DESIGNER QUESTIONNAIRE  (pixel_hh example)
══════════════════════════════════════════════════════════════════

SECTION A — OPERATING CONDITIONS  (gates OP sweep ranges)
──────────────────────────────────────────────────────────
A1. column input range?   ∈ [___V, ___V]  nominal = ___V
A2. vgcsp nominal?        = ___V   (critical: seeds VSF_OFF extraction)
A3. vgcsn nominal?        = ___V
A4. vddc / vddr?          vddc = ___V   vddr = ___V
A5. temperature range?    T ∈ [___°C, ___°C]

SECTION B — FUNCTIONAL INTENT  (gates which equations to extract)
──────────────────────────────────────────────────────────────────
B1. SF gain intent?
    □ Unity (gain ≈ 1, VSF_OFF dominates)  □ Intentional gain = ___
B2. VSF_OFF vs. column swing?
    □ Stable (linear model sufficient)
    □ Varies — significant at column < ___V or column > ___V
B3. Charge injection treatment?
    □ Absorb into constant offset    □ Must model (varies with V(column))
B4. Hold-mode droop significant?
    □ Negligible    □ Significant — hold time = ___ns, spec = ___mV/µs
B5. Diagnostic path accuracy?
    □ Test-only (1% acceptable)    □ Critical (same accuracy as vpix)

SECTION C — RESISTORS  (not ideal shorts)
──────────────────────────────────────────
C1. Rsheet for rmzw layer?   = ___ Ω/sq  (or: □ run Spectre extraction)
C2. Column daisy-chain RC ladder significant?
    □ No — R×C << readout time    □ Yes — cumulative RC = ___ns
C3. Are column_out / vcm_out / gndc_out / vddc_out loaded?
    □ Unloaded (<1 mV drop)    □ Loaded — expected I_load = ___µA

SECTION D — VALIDATION REFERENCE
──────────────────────────────────
D1. Reference Spectre waveform available?
    □ Yes — path: ___    □ No — generate new (proceed Phase 3)
D2. RNM error budget?   |V_RNM − V_Spectre| < ___ mV at 3σ
D3. Corner coverage?
    □ TT/27°C only    □ FF/SS/FS/SF × −40/27/125°C
D4. Known anomalies (body effect, DIBL, output impedance variation)?
    _______________________________________________________________
══════════════════════════════════════════════════════════════════
```

---

## Phase 3 — Spectre Stimuli Generation (semi-automated)

Each testbench isolates **one equation** at a time.

### TB1 — Source-follower transfer curve
Extracts: `VSF_OFF`, `gain_SF`, `ROUT`  
Method: force `V(sample)` directly (HOLD mode), sweep across operating range, measure `V(vpix)`.

```verilog
// pixel_hh_tb1_sf.vams
analog begin
  V(column) <+ ramp(-0.3, 0.3, 100n) + V_nominal;  // ±300 mV around vcm
  V(ph_smp) <+ 0;  V(ph_smp_b) <+ 1.8;             // HOLD — switches open
  $strobe("%g %g %g", $abstime, V(column), V(vpix));
end
```

### TB2 — Track-and-hold settling
Extracts: `RON_switch`, `C_samp`, `tau = RON×C`, charge-injection pedestal

```verilog
// pixel_hh_tb2_sh.vams
analog begin
  V(column) <+ 0.5 + 0.2 * step($abstime - 10n);           // column step
  V(ph_smp) <+ pulse(0, 1.8, 0n, 0.1n, 0.1n, 50n, 100n);  // 50 ns track
  $strobe("%g %g %g %g", $abstime, V(column), V(sample), V(vpix));
end
```

### TB3 — Operating-point sweep
Extracts: `VSF_OFF(vgcsp, vcol, T)`, `gain_SF(bias)`, `gm`, `gds`

```tcl
; pixel_hh_tb3_op.ocn
paramset "bias_sweep" list(
    'vgcsp list(0.5 0.6 0.7 0.8 0.9)
    'vcol  list(0.2 0.4 0.6 0.8 1.0 1.2))
analysis( 'dc 'saveOppoint t )
run()
VSF_OFF = OP("/MPsf:vgs")
gain_SF = OP("/MPsf:gm") / (OP("/MPsf:gm") + OP("/MPsf:gds") + OP("/MNcurr:gds"))
RON_MN  = 1.0 / OP("/MN<0>:gds")
```

### TB4 — Resistor characterization
Extracts: actual `R_PDK` values for all `rmzw` routing resistors

```spice
* pixel_hh_tb4_res.sps
Rdaca_test (p m) rmzw l=30n  w=1u    multi=1
Rvddc_test (p m) rmzw l=30n  w=850n  multi=1
R1_test    (p m) rmzw l=30n  w=1.25u multi=1
R3_test    (p m) rmzw l=30n  w=600n  multi=1
.op   * R = V(p) / I(Vsrc)
```

---

## Phase 4 — Transfer Equation Extraction (semi-automated)

Python post-processor reads Spectre PSF/CSV and fits equations, auto-escalating model order:

```python
# pixel_hh_extract.py

# TB1: SF transfer curve
def linear_sf(col, gain, VSF_OFF): return gain*col - VSF_OFF
p, cov = curve_fit(linear_sf, col_data, vpix_data)
gain, VSF_OFF = p
resid = vpix_data - linear_sf(col_data, *p)
# if max(|resid|) > error_budget → escalate to quadratic fit

# TB2: settling time constant
tau, _ = curve_fit(lambda t, tau: Vfinal*(1-np.exp(-t/tau))+Vinit, t, v_sample)
# → RON = tau / C_samp  (C_samp from cfmom geometry)

# TB3: VSF_OFF polynomial
coeffs = np.polyfit(df.vgcsp, df.VSF_OFF, deg=2)
# → VSF_OFF(vgcsp) = a*vgcsp² + b*vgcsp + c

# TB4: resistor values
R_Rdaca = V_test / I_test   # from Spectre DC OP
```

### Extracted equation table (pixel_hh, TT/27°C, nominal bias)

```
═══════════════════════════════════════════════════════════════════
PIXEL_HH EXTRACTED EQUATIONS  —  TT / 27°C / nominal bias
═══════════════════════════════════════════════════════════════════
Source follower:
  V(vpix)   = gain_SF × V(sample) − VSF_OFF(vgcsp)
  gain_SF   = 0.9982
  VSF_OFF   = 0.623 V   (at vgcsp=0.7V, vcol=0.5V)
  ROUT      = 892 Ω
  VSF_OFF(vgcsp) = −0.31·vgcsp² + 0.44·vgcsp + 0.47  [quadratic fit]
  dVSF_OFF/dT    = −0.8 mV/°C

Track / Hold:
  RON_switch = 4.2 kΩ  (NMOS+PMOS composite at vcol=0.5V)
  C_samp     = 47.3 fF  (2 × cfmom units, from geometry)
  tau        = 0.20 ns  (= RON × C;  5τ = 1.0 ns)
  Charge inj = −1.8 mV  (pedestal at switch-off)
  Droop rate = 0.12 mV/µs  (hold-mode leakage)

Routing resistors  [actual PDK values, not ideal shorts]:
  R_Rdaca    = 0.95 Ω   (column → column_out,  l=30n/w=1u)
  R_Rvddc    = 1.12 Ω   (vddc → vddc_out,      l=30n/w=850n)
  R_gndc     = 0.76 Ω   (gndc → gndc_out,       l=30n/w=1.25u)
  R_vcm      = 1.58 Ω   (vcm → vcm_out,         l=30n/w=600n)
  RC_ladder  = 5.0 ps/stage × 111 stages = 555 ps total column delay
═══════════════════════════════════════════════════════════════════
```

---

## Phase 5 — Designer Equation Review (human checkpoint 2)

Present equation table. Designer validates each parameter and flags nuances before any RNM code is written.

```
PIXEL_HH EQUATION REVIEW SESSION
────────────────────────────────────────────────────────────────────
Parameter          Extracted value     Designer sign-off
────────────────────────────────────────────────────────────────────
gain_SF            0.9982              □ OK  □ Correct to ___
VSF_OFF            0.623 V             □ OK  □ Correct to ___
VSF_OFF model      quadratic           □ Simplify to constant
                                       □ Keep quadratic
tau (S/H)          0.20 ns             □ OK vs. ph_smp spec
Charge injection   −1.8 mV             □ Absorb into VSF_OFF
                                       □ Model explicitly (varies with col)
R_Rdaca            0.95 Ω              □ Negligible (ideal short OK)
                                       □ Use finite-R model
RC_ladder          555 ps total        □ Negligible  □ Model as LPF pole
────────────────────────────────────────────────────────────────────

OPEN NUANCES (designer free text):
□ VSF_OFF at extremes of column swing (body effect, DIBL)?
□ Known settling limitation from supply bounce on vddr?
□ Left/right half mismatch (vapix vs. vbpix)?
□ Startup / power-on behavior needed in RNM?
□ Diag path loading effect on vpix?
────────────────────────────────────────────────────────────────────
Designer signature: ___________________  Date: __________
```

---

## Phase 6 — RNM Code Generation and Validation Overlay

### Equation table → RNM parameter block (direct mapping)

```
gain_SF  = 0.9982  →  parameter real GAIN_SF  = 0.9982;
VSF_OFF  = 0.623   →  parameter real VSF_OFF  = 0.623;
ROUT     = 892     →  parameter real ROUT     = 892.0;
R_Rdaca  = 0.95    →  parameter real R_RDACA  = 0.95;
```

### Validation overlay

Run identical stimuli against Spectre (golden) and RNM (candidate), compute error per node per PVT corner:

```
               Spectre (transistor)  vs.  RNM (behavioral)
vpix error ───────────────────────────────────────────────
          ┌─────────────────┐
  budget  │  designer D2    │  e.g. < 5 mV
──────────┤                 ├──────────────────────────────
  actual  │  max |ΔV|       │  → PASS / FAIL per corner
          └─────────────────┘
```

---

## Applicability and Limitations

### Applicable (flow runs as-is)

| Block type | Examples |
|---|---|
| Sampling / S-H | Pixel readout, T/H, ADC input, SC stage |
| Continuous-time buffer | Source follower, common-source with resistive load |
| Reference / bias | Bandgap, current mirror, resistor-ladder DAC |
| Level shifter | Logic-level to analog-rail translation |
| Switch / mux | Transmission gate, analog mux, sample switch |

### Requires modification

| Condition | Mitigation |
|---|---|
| Strongly nonlinear (exponential, crossover) | Auto-escalate fit order; piecewise model |
| Feedback-dependent output impedance | Characterize with actual load connected |
| Multi-cycle accumulated state | Add state variables; exercise multi-cycle stimulus |
| Oscillator / autonomous timing | Model output frequency vs. control (Hz/V), not V-transfer |
| Technology-specific primitives (ESD, bipolar) | Direct I-V sweep as black-box; no OP extraction |

### Not suitable (flag before simulation investment)

| Condition | Reason |
|---|---|
| PLL / DLL closed-loop | Behavior is loop-dependent, not open-loop characterizable |
| Strongly distributed RC (many stages) | Transfer function is an infinite-order ladder |
| Mixed-domain (optical, thermal, RF) | Signal domain outside EEnet V/I scope |

---

## Artifacts Produced by This Flow

| File | Phase | Contents |
|---|---|---|
| `topology_map.txt` | 1 | Device classification, sub-block boundaries, stimulus category |
| `questionnaire.md` | 2 | Designer questionnaire auto-filled from topology map |
| `tb1_sf.vams` … `tb4_res.sps` | 3 | Spectre testbenches (auto-generated) |
| `pixel_hh_extract.py` | 4 | Curve-fitting post-processor |
| `equation_table.txt` | 4 | Extracted parameters + confidence bounds per corner |
| `review_session.md` | 5 | Designer sign-off document |
| `verilog.sv` (in OA functional view) | 6 | RNM model with extracted parameters |
| `validation_overlay.png/csv` | 6 | Spectre vs. RNM error plot per corner |

---

## Key Principles

1. **Spectre is the golden reference** — never replaced; always the extraction engine.
2. **One equation per testbench** — isolation prevents parameter correlation.
3. **Resistors are actual impedances** — characterized from PDK via TB4; not ideal shorts.
4. **Two human checkpoints** — Phase 2 (before simulation) and Phase 5 (before code). Everything between them is automated.
5. **Fail fast** — Phase 1+2 determine suitability before any simulation budget is spent.
6. **Error budget drives model order** — linear model first; escalate only if residual exceeds designer's D2 budget.
