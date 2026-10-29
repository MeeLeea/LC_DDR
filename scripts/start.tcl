# =============================================================================
# start.tcl - DDR5 Controller IP full regression (filelist driven / Vivado Xsim)
#
# Usage (run from the project root, e.g. D:\work\tests\ddr):
#   vivado -mode batch -source scripts/start.tcl
#   vivado -mode batch -source scripts/start.tcl -tclargs tb_ddr5_reset_sync
#   vivado -mode batch -source scripts/start.tcl -tclargs tb_ddr5_ctrl_core tb_ddr5_ui_axi4
#
# Flow:
#   1) parse scripts/sim_filelist.f (single source of truth, never invent files)
#   2) file-exists check for every entry, abort on missing files
#   3) xvlog -sv -work xil_defaultlib -i ./src -f scripts/sim_filelist.f
#   4) xvlog -work xil_defaultlib $XILINX_VIVADO/data/verilog/src/glbl.v
#   5) per testbench: xelab -> xsim (functional coverage db per tb in ./cov_db)
#   6) parse ./reports/<tb>_simulate.log for PASS/FAIL (xsim exit code is unreliable)
#   7) xcrg summary report into ./reports/coverage/
#
# Outputs:
#   ./reports/<tb>_simulate.log     simulation log per tb
#   ./reports/<tb>_elaborate.log    xelab log per tb
#   ./reports/xvlog_compile.log     compile log
#   ./reports/coverage/             xcrg html + text coverage report
#   ./cov_db/xsim.covdb/<tb>/       functional coverage db per tb
#   ./xsim.dir/                     compiled library + snapshots
# =============================================================================

proc die {msg {code 1}} {
    puts "\[ERROR\] $msg"
    if {[catch {exit -code $code}]} { exit $code }
}

# ---------------------------------------------------------------------------
# 0. locate project root (this script lives in <root>/scripts/)
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

puts "============================================================"
puts " DDR5 Controller IP - Xsim regression"
puts " project root : [pwd]"
puts " filelist     : $filelist"
puts "============================================================"

# ---------------------------------------------------------------------------
# 1. environment check
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
# 2. parse + validate filelist (tolerates CRLF, comments and a UTF-8 BOM)
# ---------------------------------------------------------------------------
proc read_text {path} {
    set fh [open $path r]
    fconfigure $fh -translation binary
    set data [read $fh]
    close $fh
    if {[string range $data 0 2] eq "\xEF\xBB\xBF"} {
        set data [string range $data 3 end]
    }
    return $data
}

set src_files {}
foreach line [split [read_text $filelist] "\n"] {
    set l [string trim $line]
    if {$l eq ""} { continue }
    if {[string index $l 0] eq "#"} { continue }
    if {[string range $l 0 1] eq "//"} { continue }
    if {[string index $l 0] eq "+"} { continue }
    lappend src_files [file normalize $l]
}

set missing {}
foreach f $src_files {
    if {![file exists $f]} { lappend missing $f }
}
if {[llength $missing] > 0} {
    puts "\[ERROR\] files listed in sim_filelist.f but missing on disk:"
    foreach m $missing { puts "        - $m" }
    die "fix the missing sources and re-run (the filelist must not be edited on the fly)"
}
puts "\[INFO\] filelist OK: [llength $src_files] files"

# ---------------------------------------------------------------------------
# 3. derive the testbench list from test/tb_*.sv entries of the filelist
# ---------------------------------------------------------------------------
set all_tbs {}
foreach f $src_files {
    if {![regexp {(^|[\\/])test[\\/]tb_[^\\/]+\.sv$} $f]} { continue }
    set mod ""
    foreach line [split [read_text $f] "\n"] {
        if {[regexp {^[ \t]*module[ \t]+([A-Za-z_][A-Za-z0-9_$]*)} $line -> m]} {
            set mod $m
            break
        }
    }
    if {$mod eq ""} {
        puts "\[WARN\] no module declaration found in $f, skipped"
        continue
    }
    lappend all_tbs $mod
}
if {[llength $all_tbs] == 0} {
    die "no testbench (test/tb_*.sv) found in sim_filelist.f"
}

set targets {}
foreach arg $argv {
    if {[lsearch -exact $all_tbs $arg] < 0} {
        puts "\[ERROR\] unknown testbench: $arg"
        puts "        available: $all_tbs"
        die "invalid -tclargs"
    }
    lappend targets $arg
}
if {[llength $targets] == 0} { set targets $all_tbs }

puts "\[INFO\] testbenches to run: [llength $targets]"

# ---------------------------------------------------------------------------
# 4. compile (xvlog: SystemVerilog mode, into xil_defaultlib)
# ---------------------------------------------------------------------------
set compile_log [file join $report_dir "xvlog_compile.log"]
puts "\n\[1/3\] compiling RTL + TB ..."
set xvlog_cmd [list xvlog -sv -work $lib_name -i $incdir -f $filelist]
if {[catch {exec {*}$xvlog_cmd > $compile_log 2>@1} err]} {
    puts "        xvlog: $err"
    puts "        see $compile_log"
    die "xvlog failed"
}
puts "        OK ($compile_log)"

puts "\[2/3\] compiling glbl.v ..."
set glbl_cmd [list xvlog -work $lib_name $glbl_v]
if {[catch {exec {*}$glbl_cmd >> $compile_log 2>@1} err]} {
    puts "        xvlog: $err"
    puts "        see $compile_log"
    die "glbl.v compile failed"
}
puts "        OK"

# ---------------------------------------------------------------------------
# 5. per-testbench elaborate + simulate
# ---------------------------------------------------------------------------
proc log_has_failure {logfile} {
    if {![file exists $logfile]} { return 1 }
    set fh [open $logfile r]
    set content [read $fh]
    close $fh
    foreach pat {"SOME TESTS FAILED" "\[ERROR\]" "FATAL_ERROR"} {
        if {[string first $pat $content] >= 0} { return 1 }
    }
    return 0
}

puts "\n\[3/3\] elaborate + simulate ..."
set n_pass 0
set n_fail 0
set failed_tbs {}
set env(SIM_TB) ""

foreach tb $targets {
    set snap     ${tb}_behav
    set snap_dir [file join $prj_root "xsim.dir" $snap]
    set elab_log [file join $report_dir "${tb}_elaborate.log"]
    set sim_log  [file join $report_dir "${tb}_simulate.log"]
    set out_log  [file join $report_dir "${tb}_xsim_stdout.log"]

    # remove stale snapshot first (avoids Windows file locks in the linker)
    if {[file exists $snap_dir]} { catch {file delete -force $snap_dir} }
    catch {file delete -force $sim_log}

    puts "\n--- $tb ---"
    set xelab_cmd [list xelab --debug typical --relax --mt 2 \
        -L $lib_name -L uvm -L unisims_ver -L unimacro_ver -L secureip \
        --snapshot $snap $lib_name.$tb $lib_name.glbl]
    if {[catch {exec {*}$xelab_cmd > $elab_log 2>@1} err]} {
        puts "    xelab FAILED: $err"
        puts "    see $elab_log"
        incr n_fail
        lappend failed_tbs $tb
        continue
    }

    set env(SIM_TB) $tb
    set xsim_cmd [list xsim $snap \
        -tclbatch [file join $prj_root "scripts" "xsim_run.tcl"] \
        -cov_db_dir $cov_dir -cov_db_name $tb \
        -log $sim_log]
    if {[catch {exec {*}$xsim_cmd > $out_log 2>@1} err]} {
        puts "    xsim FAILED: $err"
        puts "    see $sim_log / $out_log"
        incr n_fail
        lappend failed_tbs $tb
        continue
    }

    if {[log_has_failure $sim_log]} {
        puts "    FAILED (log contains SOME TESTS FAILED / \[ERROR\])"
        incr n_fail
        lappend failed_tbs $tb
    } else {
        puts "    PASS"
        incr n_pass
    }
}

# ---------------------------------------------------------------------------
# 6. coverage summary (xcrg, warnings only)
# ---------------------------------------------------------------------------
set covdb_dir [file join $cov_dir "xsim.covdb"]
if {[file exists $covdb_dir]} {
    set cov_report [file join $report_dir "coverage"]
    file mkdir $cov_report
    set xcrg_cmd [list xcrg -report_format all -dir $covdb_dir -report_dir $cov_report]
    if {[catch {exec {*}$xcrg_cmd > [file join $report_dir "xcrg.log"] 2>@1} err]} {
        puts "\[WARN\] coverage report failed (test verdict unaffected): $err"
    } else {
        puts "\[INFO\] coverage report: $cov_report"
    }
} else {
    puts "\[WARN\] no coverage db at $covdb_dir, skip coverage report"
}

# ---------------------------------------------------------------------------
# 7. summary
# ---------------------------------------------------------------------------
puts "\n============================================================"
puts " RESULT: PASS = $n_pass / [llength $targets], FAIL = $n_fail"
if {$n_fail > 0} {
    puts " failed: $failed_tbs"
    puts " logs  : $report_dir"
}
puts "============================================================"

if {$n_fail > 0} {
    if {[catch {exit -code 1}]} { exit 1 }
}
if {[catch {exit -code 0}]} { exit 0 }
