# =============================================================================
# xsim_run.tcl - xsim batch sub-script (invoked through: xsim -tclbatch)
#
# Callers: scripts/start.tcl / scripts/run_one.tcl
#   xsim <snapshot> -tclbatch scripts/xsim_run.tcl \
#        -cov_db_dir ./cov_db -cov_db_name <tb> -log ./reports/<tb>_simulate.log
#
# Notes:
#   - the functional coverage db is selected by the xsim options
#     -cov_db_dir / -cov_db_name and written to ./cov_db/xsim.covdb/<tb>/ at exit
#   - this file only runs the simulation to completion and exits, so that batch
#     mode never stops at an interactive prompt
#   - testbenches with $dumpfile/$dumpvars produce VCD waveforms;
#     for WDB waveforms uncomment log_wave below and pass -wdb <file>.wdb to xsim
# =============================================================================

if {[info exists ::env(SIM_TB)]} {
    puts "\[xsim\] running testbench: $::env(SIM_TB)"
} else {
    puts "\[xsim\] running testbench: (SIM_TB not set)"
}

# uncomment for WDB waveforms (also pass -wdb to xsim)
# log_wave -recursive /*

run all
exit
