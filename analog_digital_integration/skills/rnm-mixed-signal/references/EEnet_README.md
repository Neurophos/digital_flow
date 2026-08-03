# anatop full-chip RNM (Cadence `EE_pkg::EEnet`)

Real-number model of `msic_a0/anatop` that runs **entirely in the digital event
kernel — no Spectre / no analog solver**. Analog nets use Cadence's native
electrical nettype `EE_pkg::EEnet` (V/I/R, Kirchhoff resolution); digital stays `logic`.

## Files
| file | role |
|------|------|
| `EE_pkg.sv` (in `dmsLib`) | Cadence native electrical nettype `EEnet` |
| `<cell>/functional/verilog.sv` (in OA) | 6 behavioral RNM leaves (dac_dark, thermal, tst_intf, bias_array_vh, pixel_hh, row_drv) |
| `col_driver.sv`, `pixel.sv` | extra behavioral leaves (substituted into the netlist) |
| `rnmgen2.py` | netlist transformer: per-net type inference + retype `wire`→`EEnet` + de-electrify (R→short) + external-module substitution |
| `netlist_ee.sv` | generated full-chip RNM top (anatop/array_vh/column) |
| `tb_anatop.sv` | top-level testbench (thermal, col_driver, dac_dark paths) |
| `Makefile` | build / sim / waves / coverage |

## Quick start
```bash
module load cadence/xcelium/25.09.001     # required for every target below
make            # or: make help          # list targets
make sim        # compile + run the testbench  -> ALL PASS
make waves      # sim + waveform dump          -> simvision waves.shm
make cov        # sim with coverage            -> cov_work/  (imc to view)
make clean
```

## Full regeneration from Virtuoso (when the schematic/config changes)
```bash
startPrj msic msic_a0                      # project env (gives runams + libs)
make netlist                               # runams -> anatop_nl/netlist/netlist.vams
make rnm                                   # rnmgen2 -> netlist_ee.sv
make sim
```

## Flow
```
runams (structure)  ->  rnmgen2.py (type-infer + retype + de-electrify + substitute)  ->  xrun (RNM)
```
`rnmgen2.py` seeds exact port types from the leaf `.sv` views, infers each net's
type bidirectionally (a net is `EEnet` iff it touches an `EEnet` port and no logic
port), declares implicit nets, turns foundry resistors into ideal shorts, and drops
netlist modules provided as external `.sv` leaves (e.g. `col_driver`).

## Notes
- `EEnet` analog ports must be type-consistent across leaves (e.g. sampling phases are
  `logic`; `ibg`/`iti` trim are `logic`; bias currents/voltages are `EEnet`).
- `EEnet` drivers: voltage `'{V:v, I:0.0, R:r}` (R=0 => ideal); current `'{V:`wrealZState,
  I:i, R:`wrealZState}`; hi-Z all `wrealZState`. Read voltage with `.V`.
- SPEC-TODO parameters in the leaf models are placeholders; replace with datasheet values.
