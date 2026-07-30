# MSIC UVM Coverage Exclusions
#
# DESIGN NOTE: IMC 25.09 'exclude -toggle PATH' fails with *E,MSGPTH for every
# path format (UCIS Java layer prepends '/' to inst arg, making the first path
# component empty). The correct approach is load -refinement with a pre-built
# .vRefine file whose <rules> carry the UCIS entityName directly.
#
# To add new exclusions:
#   1. Find the UCIS entityName: msic_top/<sub_inst_path>/<signal>
#      (root is 'msic_top' because xrun uses -covdut msic_top)
#   2. Add a <rule> entry to coverage.vRefine.
#   3. For a whole scope (e.g. ARM model), use a CCF file with
#      deselect_coverage -toggle -instance /path  and add it to XRUN_FLAGS.

set _excl_dir [file dirname [info script]]
load -refinement ${_excl_dir}/coverage.vRefine
unset _excl_dir
