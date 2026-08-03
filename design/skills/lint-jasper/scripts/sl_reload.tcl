
# THis is not yet working 
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
set root_dir "${::env(ROOT_DIR)}"
set ip_name "${::env(IP_NAME)}"

set waiver_file "${top_mod}.sl.waivers"
set waiver_file_dir "${root_dir}design/${ip_name}/waivers/"
if { [ file exists ${waiver_file_dir}${waiver_file} ] } {
    puts "Using waiver file ${waiver_file_dir}${waiver_file} "
    set waiver_cmd "check_superlint -configure -save_rule_file ${waiver_file_dir}${waiver_file} -force "
} else { 
    set waiver_cmd ""
}


eval "check_superlint -restore -file ${top_mod}.sl.db"
# Not sure is this is needed or right to force the override. 
# eval "${waiver_cmd}"

