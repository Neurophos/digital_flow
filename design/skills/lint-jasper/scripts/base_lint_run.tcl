
if { [info exists ::env(COMMON_DIR)] } {
    set def_file "${::env(COMMON_DIR)}../scripts/lint/lcsuperlint.def"
    puts  "Using def file from ${def_file}  "
} else {
    puts "ERROR - COMMON_DIR env var not set !"
    exit()
}
if { [ info exists ::env(TOP_MODULE)] } {
    set top_mod "${::env(TOP_MODULE)}"
    puts  "Running lint for TOP_MODULE = ${top_mod}"
} else {
    puts "ERROR - TOP_MODULE env var not set !"
    exit()
}
set lc_bbox   "nc_*" 
if { [info exists my_bboxes ] } {
    set bb_cmd  " -bbox_m \"${my_bboxes} ${lc_bbox}\""
} else {
    set bb_cmd "bbox_m \"${lc_bbox}\""
}
if { ![info exists my_resets ] } {
    set my_resets "-analyze"
}
if { ![info exists my_clks ] } {
    set my_clks "-infer"
}
set root_dir "${::env(ROOT_DIR)}"
set ip_name "${::env(IP_NAME)}"

set waiver_file "${top_mod}.sl.waivers"
set waiver_file_dir "${root_dir}design/${ip_name}/waivers/"
if { [ file exists ${waiver_file_dir}${waiver_file} ] } {
    puts "Using waiver file ${waiver_file_dir}${waiver_file} "
    set waiver_cmd "check_superlint -waiver -import -file_name ${waiver_file_dir}${waiver_file} "
} else { 
    set waiver_cmd ""
}

# -------------------------------------------------------
# General settings 
# -------------------------------------------------------
# Enable the inline pragma waivers 
set_superlint_enable_rtl_inline_waiver true 

# -------------------------------------------------------
# Suppress annoying worthless elaboration messages that come
#   form parameters in the open titan reg package 
# -------------------------------------------------------
# set_message_suppression -warning {VERI-2418}

# Init & setup 
# -------------------------------------------------------
check_superlint -init
eval "check_superlint -configure -load_rule_file ${def_file} "
eval "${waiver_cmd}"
# Disable Formal and DFT
config_rtlds -rule -disable -category {AUTO_FORMAL_FSM_DEADLOCK_LIVELOCK AUTO_FORMAL_FSM_REACHABILITY AUTO_FORMAL_SIGNALS }
config_rtlds -rule -disable -domain {DFT}
# -------------------------------------------------------
# Read in the design 
# -------------------------------------------------------
puts "Analyzing"
eval "analyze -sv -f ${top_mod}.f  +define+NI_BEHAVIORAL +define+SIMULATION " 
# -------------------------------------------------------
# Elaborate the design 
# -------------------------------------------------------
puts "Elaborating "
# elaborate -top ${top_mod} -bbox_m ${my_bboxes}
# eval "elaborate -top ${top_mod} $bb_cmd +define+NI_BEHAVIORAL +define+SIMULATION -suppress_warning VERI-2418"
eval "elaborate -top ${top_mod} $bb_cmd +define+NI_BEHAVIORAL +define+SIMULATION "
# -------------------------------------------------------
# Set clocks and resets 
# -------------------------------------------------------
# Infer clocks (alternatively can explicitly declare them)
if {[string length ${my_clks} ] != 0} {
    eval "clock  ${my_clks}  "
} 

if {[string length ${my_resets} ] != 0} {
    eval "reset  ${my_resets}  "
}
# -------------------------------------------------------
#$ Run it ! 
# -------------------------------------------------------
puts "Running superlint"
check_superlint -extract 
# -------------------------------------------------------
# Save the results and write report 
# -------------------------------------------------------
check_superlint -save -file ${top_mod}.sl.db
check_superlint -report -detailed -file ${top_mod}.sl_report.txt -force
get_design_info -list multiple_driven
# -------------------------------------------------------
# All done
# -------------------------------------------------------
exit
