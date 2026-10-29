# =============================================================================
# run_one.tcl - single testbench regression (filelist driven / Vivado Xsim)
#
# Usage (run from the project root, e.g. D:\work\tests\ddr):
#   vivado -mode batch -source scripts/run_one.tcl -tclargs tb_ddr5_cmd_arbiter
#   vivado -mode batch -source scripts/run_one.tcl          ;# default: tb_ddr5_reset_sync
#
# Notes:
#   - does NOT create/open a Vivado project, it reuses the compiled library
#     ./xsim.dir/xil_defaultlib produced by start.tcl
#   - if that library is missing, it compiles once from scripts/sim_filelist.f
#   - only the requested testbench is re-elaborated and re-simulated
# =============================================================================

proc die {msg {code 1}} {
    puts "\[ERROR\] $msg"
    if {[catch {exit -code $code}]} { exit $code }
}

# ---------------------------------------------------------------------------
# 0. locate project root
# ---------------------------------------------------------------------------
set script_dir [file dirname [info script]]
set prj_root   [file normalize [file join $script_dir ".."]]
if {[catch {cd $prj_root} err]} {
    die "cannot change directory to project root $prj_root : $err"
}

set report_dir [file normalize [file join $prj_root "reports"]]
set cov_dir    [file normalize [file join $prj_root "cov_db"]]
set filelist   [file normalize [file join $prj_root "scripts" "sim_filelist.f"]]
set incdir     [file normalize [file join $prj_root "src"]]
set lib_name   "xil_defaultlib"

# ---------------------------------------------------------------------------
# 1. parse arguments
# ---------------------------------------------------------------------------
set tb_name [lindex $argv 0]
if {$tb_name eq ""} { set tb_name "tb_ddr5_reset_sync" }

set tb_file [file join $prj_root "test" "${tb_name}.sv"]
if {![file exists $tb_file]} {
    set available {}
    foreach f [glob -nocomplain -directory [file join $prj_root "test"] "tb_*.sv"] {
        lappend available [file rootname [file tail $f]]
    }
    puts "\[ERROR\] testbench source not found: $tb_file"
    puts "        available: $available"
    die "invalid testbench name"
}

puts "============================================================"
puts " DDR5 Controller IP - single testbench"
puts " testbench    : $tb_name"
puts " project root : [pwd]"
puts "============================================================"

# ---------------------------------------------------------------------------
# 2. environment check
# ---------------------------------------------------------------------------
if {![info exists ::env(XILINX_VIVADO)]} {
    die "XILINX_VIVADO is not set. Launch via vivado.bat or source <Vivado>/settings64.bat first."
}
set glbl_v [file join $::env(XILINX_VIVADO) "data" "verilog" "src" "glbl.v"]
if {![file exists $glbl_v]} {
    die "glbl.v not found: $glbl_v"
}
if {![file exists $filelist]} {
    die "sim filelist not found: $filelist"
}
file mkdir $report_dir
file mkdir $cov_dir

# ---------------------------------------------------------------------------
# 3. reuse (or build) the compiled library
# ---------------------------------------------------------------------------
set lib_dir [file join $prj_root "xsim.dir" $lib_name]
if {![file exists $lib_dir]} {
    puts "\[INFO\] compiled library $lib_dir not found, compiling from filelist ..."
    set compile_log [file join $report_dir "xvlog_compile.log"]
    set xvlog_cmd [list xvlog -sv -work $lib_name -i $incdir -f $filelist]
    if {[catch {exec {*}$xvlog_cmd > $compile_log 2>@1} err]} {
        puts "        xvlog: $err"
        puts "        see $compile_log"
        die "xvlog failed"
    }
    set glbl_cmd [list xvlog -work $lib_name $glbl_v]
    if {[catch {exec {*}$glbl_cmd >> $compile_log 2>@1} err]} {
        puts "        xvlog: $err"
        puts "        see $compile_log"
        die "glbl.v compile failed"
    }
    puts "\[INFO\] compile done ($compile_log)"
} else {
    puts "\[INFO\] reusing compiled library: $lib_dir"
}

# ---------------------------------------------------------------------------
# 4. elaborate + simulate
# ---------------------------------------------------------------------------
set snap     ${tb_name}_behav
set snap_dir [file join $prj_root "xsim.dir" $snap]
set elab_log [file join $report_dir "${tb_name}_elaborate.log"]
set sim_log  [file join $report_dir "${tb_name}_simulate.log"]
set out_log  [file join $report_dir "${tb_name}_xsim_stdout.log"]

if {[file exists $snap_dir]} { catch {file delete -force $snap_dir} }
catch {file delete -force $sim_log}

puts "\[1/2\] xelab -> snapshot $snap ..."
set xelab_cmd [list xelab --debug typical --relax --mt 2 \
    -L $lib_name -L uvm -L unisims_ver -L unimacro_ver -L secureip \
    --snapshot $snap $lib_name.$tb_name $lib_name.glbl]
if {[catch {exec {*}$xelab_cmd > $elab_log 2>@1} err]} {
    puts "        xelab FAILED: $err"
    puts "        see $elab_log"
    die "xelab failed"
}
puts "        OK"

puts "\[2/2\] xsim ..."
set env(SIM_TB) $tb_name
set xsim_cmd [list xsim $snap \
    -tclbatch [file join $prj_root "scripts" "xsim_run.tcl"] \
    -cov_db_dir $cov_dir -cov_db_name $tb_name \
    -log $sim_log]
if {[catch {exec {*}$xsim_cmd > $out_log 2>@1} err]} {
    puts "        xsim FAILED: $err"
    puts "        see $sim_log / $out_log"
    die "xsim failed"
}

# ---------------------------------------------------------------------------
# 5. verdict from the log (xsim may exit 0 even when a test fails)
# ---------------------------------------------------------------------------
set failed 0
if {[file exists $sim_log]} {
    set fh [open $sim_log r]
    set content [read $fh]
    close $fh
    foreach pat {"SOME TESTS FAILED" "\[ERROR\]" "FATAL_ERROR"} {
        if {[string first $pat $content] >= 0} { set failed 1 ; break }
    }
} else {
    puts "\[WARN\] simulation log not found: $sim_log"
    set failed 1
}

puts "============================================================"
if {$failed} {
    puts " RESULT: FAILED - $tb_name"
    puts " log   : $sim_log"
    puts "============================================================"
    if {[catch {exit -code 1}]} { exit 1 }
}
puts " RESULT: SUCCESS - $tb_name"
puts " log   : $sim_log"
puts " covdb : [file join $cov_dir xsim.covdb $tb_name]"
puts "============================================================"
if {[catch {exit -code 0}]} { exit 0 }
