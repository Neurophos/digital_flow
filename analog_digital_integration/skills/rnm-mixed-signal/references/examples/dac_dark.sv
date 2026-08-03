// SystemVerilog (Cadence native EE_pkg::EEnet) for "msic_a0", "dac_dark" "functional"
// PILOT: use the tool-provided electrical nettype (V/I/R, Kirchhoff resolution,
// conflict->X) from EE_pkg in dmsLib. Single global identity => multi-leaf safe.
// Restore logic shell from verilog.v.logic.bak / master.tag.bak if needed.
import EE_pkg::*;

module dac_dark ( vdacd1, vdacd2, diaga, diagb, gnda, gndc, vdd, vddc, vddh,
vddr, dacd1_data_bit, dacd2_data_bit, ibg, iti, pu_dac, pu_drv, tst_en, tst_sel,
vcm );
  output EEnet vdacd1, vdacd2;                 // DAC outputs (voltage, R=ROUT)
  inout  EEnet diaga, diagb;                   // diagnostic taps
  inout  EEnet gnda, gndc, vdd, vddc, vddh, vddr;
  input  EEnet vcm;                            // common-mode ref (analog)
  input        ibg, iti;                       // bias trim bits (digital), shared 3-bit bus
  input  [7:0] dacd1_data_bit, dacd2_data_bit;
  input  [3:0] tst_sel;
  input        pu_dac, pu_drv, tst_en;

  parameter real VFS=1.0, VZERO=0.0, ROUT=50.0;   // SPEC-TODO
  localparam real VLSB = VFS/255.0;

  real o1, o2;
  assign o1 = vcm.V + VZERO + real'(dacd1_data_bit)*VLSB;
  assign o2 = vcm.V + VZERO + real'(dacd2_data_bit)*VLSB;
  wire on = pu_dac & pu_drv;
  // EEstruct driver: ideal-ish voltage source with output resistance ROUT; hi-Z when off
  assign vdacd1 = on ? '{V:o1, I:0.0, R:ROUT} : '{V:`wrealZState, I:`wrealZState, R:`wrealZState};
  assign vdacd2 = on ? '{V:o2, I:0.0, R:ROUT} : '{V:`wrealZState, I:`wrealZState, R:`wrealZState};
  assign diaga  = tst_en ? '{V:o1, I:0.0, R:ROUT} : '{V:`wrealZState, I:`wrealZState, R:`wrealZState};
  assign diagb  = tst_en ? '{V:o2, I:0.0, R:ROUT} : '{V:`wrealZState, I:`wrealZState, R:`wrealZState};
endmodule
