# Synthesis + implementation + bitstream, with the reports that matter.
#     vivado -mode batch -source scripts/build_bitstream.tcl
# (Not run in Vivado by the author of the RTL. Needs the board's JTAG only for scripts/program_board.tcl.)
source [file normalize [file dirname [info script]]/create_project.tcl]
launch_runs synth_1 -jobs 4
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] ne "100%"} { error "synthesis failed - see vivado/p12.runs/synth_1/runme.log" }
open_run synth_1
report_utilization -file $root/vivado/util_synth.rpt
check_timing -file $root/vivado/check_timing_synth.rpt
report_drc -file $root/vivado/drc_synth.rpt
close_design
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] ne "100%"} { error "implementation failed - see vivado/p12.runs/impl_1/runme.log" }
open_run impl_1
report_utilization    -file $root/vivado/util_impl.rpt
report_timing_summary -file $root/vivado/timing_impl.rpt -max_paths 10
report_clock_utilization -file $root/vivado/clock_util.rpt
set wns [get_property STATS.WNS [get_runs impl_1]]
set whs [get_property STATS.WHS [get_runs impl_1]]
puts "WNS (setup slack) = $wns ns   WHS (hold slack) = $whs ns"
file copy -force [glob $root/vivado/p12.runs/impl_1/*.bit] $root/p12_zybo.bit
puts "bitstream: $root/p12_zybo.bit"
if {$wns < 0} { puts "WARNING: timing not met at 50 MHz - open vivado/timing_impl.rpt (see INTEGRATION.md, 'If timing fails')" }
