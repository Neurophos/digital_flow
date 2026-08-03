// ============================================================================
//  ee_roles.sv -- role add-on for Cadence EE_pkg::EEnet
//  Roles are LABELS over the SINGLE EEnet identity, two complementary forms:
//    1) typedef ALIASES  -> same type identity as EEnet (connect for free)
//    2) bindable CHECKERS -> role-specific assertions on .V (no new nettype)
//  Nothing here is a distinct nettype, so it cannot reintroduce TYCMPAT.
// ============================================================================
import EE_pkg::*;

package ee_roles_pkg;
  typedef enum {SIGNAL_V, SIGNAL_I, BIAS_V, BIAS_I, VDD, GND, REF_V, DIFF} ee_role_e;
endpackage

// ---- (1) NOTE: a nettype CANNOT be typedef'd (xmvlog *E,NTIINV: "nettype identifier
//      is invalid, a data type is expected"). So role "aliases" are impossible without
//      creating a DISTINCT (incompatible) nettype. Roles are therefore carried by NAME
//      + the bound checkers below -- not by type. Use plain `EEnet` everywhere.

// skip hi-Z / NaN-like wrealZState (undriven) so checkers don't false-fire
function automatic bit ee_isval(input real x); return (x==x) && (x>-1.0e30) && (x<1.0e30); endfunction

// ---- (2) bindable role checkers (read .V) ----
module chk_vdd #(parameter real VMIN=0.7, parameter real VMAX=3.6, parameter string NAME="vdd")
  (input EEnet n);
  always @(n.V) if (ee_isval(n.V))
    assert (n.V>=VMIN && n.V<=VMAX)
      else $error("[role VDD:%s] V=%0.4f out of [%0.3f,%0.3f]", NAME, n.V, VMIN, VMAX);
endmodule

module chk_gnd #(parameter real TOL=0.05, parameter string NAME="gnd") (input EEnet n);
  always @(n.V) if (ee_isval(n.V))
    assert (n.V>=-TOL && n.V<=TOL)
      else $error("[role GND:%s] V=%0.4f not ~0 (tol %0.3f)", NAME, n.V, TOL);
endmodule

module chk_bias #(parameter real VMIN=0.0, parameter real VMAX=3.6, parameter string NAME="bias")
  (input EEnet n);
  always @(n.V) if (ee_isval(n.V))
    assert (n.V>=VMIN && n.V<=VMAX)
      else $error("[role BIAS:%s] V=%0.4f outside window [%0.3f,%0.3f]", NAME, n.V, VMIN, VMAX);
endmodule

module chk_diff #(parameter real VCM_MIN=0.2, parameter real VCM_MAX=3.4, parameter string NAME="diff")
  (input EEnet p, input EEnet n);
  real vcm;
  always @(p.V or n.V) if (ee_isval(p.V) && ee_isval(n.V)) begin
    vcm = 0.5*(p.V + n.V);
    assert (vcm>=VCM_MIN && vcm<=VCM_MAX)
      else $error("[role DIFF:%s] Vcm=%0.4f out of [%0.3f,%0.3f]", NAME, vcm, VCM_MIN, VCM_MAX);
  end
endmodule

// ---- bus wrappers: bind a whole [N] EEnet array; reuse the scalar checkers ----
module chk_vdd_bus  #(parameter int N=1, parameter real VMIN=0.7, parameter real VMAX=3.6, parameter string NAME="vdd")
  (input EEnet n[N]);
  for (genvar i=0;i<N;i++) chk_vdd  #(.VMIN(VMIN),.VMAX(VMAX),.NAME(NAME)) u (.n(n[i]));
endmodule
module chk_gnd_bus  #(parameter int N=1, parameter real TOL=0.05, parameter string NAME="gnd")
  (input EEnet n[N]);
  for (genvar i=0;i<N;i++) chk_gnd  #(.TOL(TOL),.NAME(NAME)) u (.n(n[i]));
endmodule
module chk_bias_bus #(parameter int N=1, parameter real VMIN=0.0, parameter real VMAX=3.6, parameter string NAME="bias")
  (input EEnet n[N]);
  for (genvar i=0;i<N;i++) chk_bias #(.VMIN(VMIN),.VMAX(VMAX),.NAME(NAME)) u (.n(n[i]));
endmodule
