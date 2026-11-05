# Driven by environment variables set in scripts/syn.sh
# Design names ending in _lp reuse the RTL of the base design but turn on
# Genus low-power options (clock gating) at high synthesis effort.
set D    $::env(DESIGN)
set OUT  $::env(OUTDIR)
set DB   [string map {_lp ""} $D]
set LP   [string match *_lp $D]
file mkdir $OUT/rpt $OUT/out
set_db init_lib_search_path [file dirname $::env(LIB_FILE)]
set_db init_hdl_search_path "$::env(PROJ_DIR)/rtl/$DB"
set_db library [file tail $::env(LIB_FILE)]

set files [glob $::env(PROJ_DIR)/rtl/$DB/*.v]
read_hdl -v2001 $files
elaborate $::env(TOP)
check_design -unresolved > $OUT/rpt/check_design.rpt
read_sdc $::env(PROJ_DIR)/constraints/riscv.sdc

if {$LP} { set eff high } else { set eff medium }
set_db syn_generic_effort $eff
set_db syn_map_effort     $eff
set_db syn_opt_effort     $eff
if {$LP} {
  catch { set_db lp_insert_clock_gating true }
  catch { set_db lp_insert_operand_isolation true }
}
syn_generic
syn_map
syn_opt

report_area      > $OUT/rpt/area.rpt
report_gates     > $OUT/rpt/gates.rpt
report_timing -max_paths 3 > $OUT/rpt/timing.rpt
report_power     > $OUT/rpt/power_vectorless.rpt
report_qor       > $OUT/rpt/qor.rpt
if {$LP} { catch { report_clock_gating > $OUT/rpt/clock_gating.rpt } }

set vcd $::env(PROJ_DIR)/results/$DB/sim/dut.vcd
if {[file exists $vcd]} {
  catch {
    read_stimulus -file $vcd -format vcd -dut_instance tb_top/u_dut
    report_power > $OUT/rpt/power_vcd.rpt
  }
}
write_hdl > $OUT/out/$::env(TOP)_netlist.v
write_sdc > $OUT/out/$::env(TOP).sdc
if {![info exists ::env(KEEP_OPEN)]} { exit }
