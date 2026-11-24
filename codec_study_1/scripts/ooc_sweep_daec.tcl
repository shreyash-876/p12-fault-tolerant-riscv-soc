# -----------------------------------------------------------------------------
# Out-of-context synthesis + place & route of the SEC-DED-DAEC codec (paper code) on the XC7Z010-1 (Zybo Z7-10),
# for the delay/area table "baseline vs paper code". Same method as ooc_sweep.tcl: all ports registered,
# clock constrained at 5 ns, fmax = 1000 / (5 - WNS), slack at 50 MHz = 20 - (5 - WNS).
#
# Run in the "Vivado 2025.2 Tcl Shell" (not in the GUI with your project open):
#     cd C:/Users/asus/Documents/RTL_project/p12_final/p12_final/codec_study_1
#     source scripts/ooc_sweep_daec.tcl
# Results -> reports/ooc_results_daec.csv, reports/timing_daec_*.txt, reports/util_daec_*.txt
# Columns: kind, impl, pipe, luts, ffs, srls, logic_levels, path_ns, wns_ns, fmax_mhz, slack50_ns
# -----------------------------------------------------------------------------
set root   [file normalize [file dirname [info script]]/..]
set part   xc7z010clg400-1
set period 5.000
set srcs   {daec_pkg daec_enc_flat daec_enc_cse daec_enc_tree daec_corr_cmp daec_enc daec_dec daec_ooc_wrap}

# kind IMPL PIPE
set configs {
    {enc 0 0} {enc 1 0} {enc 2 0} {enc 3 0}
    {dec 0 0} {dec 1 0} {dec 2 0} {dec 3 0}
    {dec 2 1}
}

file mkdir $root/reports
set csv [open $root/reports/ooc_results_daec.csv w]
puts $csv "kind,impl,pipe,luts,ffs,srls,logic_levels,path_ns,wns_ns,fmax_mhz,slack50_ns"

foreach cfg $configs {
    lassign $cfg kind impl pipe
    catch {close_project}
    create_project -in_memory -part $part
    foreach f $srcs { read_verilog -sv $root/rtl/ecc/$f.sv }

    set args [list -top [expr {$kind eq "enc" ? "daec_enc_ooc" : "daec_dec_ooc"}] \
                   -part $part -mode out_of_context -generic IMPL=$impl]
    if {$kind eq "dec"} { lappend args -generic PIPE=$pipe }
    synth_design {*}$args

    create_clock -period $period -name clk [get_ports clk]
    opt_design
    place_design
    route_design

    set luts [llength [get_cells -hier -filter {REF_NAME =~ LUT*}]]
    set ffs  [llength [get_cells -hier -filter {REF_NAME =~ FD*}]]
    set srls [llength [get_cells -hier -filter {REF_NAME =~ SRL*}]]
    set path [get_timing_paths -max_paths 1 -nworst 1 -setup]
    set wns  [get_property SLACK $path]
    set lvl  [get_property LOGIC_LEVELS $path]
    set dly  [get_property DATAPATH_DELAY $path]
    set fmax [format %.1f [expr {1000.0 / ($period - $wns)}]]
    set s50  [format %.3f [expr {20.0 - ($period - $wns)}]]
    puts $csv "$kind,$impl,$pipe,$luts,$ffs,$srls,$lvl,$dly,$wns,$fmax,$s50"
    flush $csv
    puts "=== daec $kind IMPL=$impl PIPE=$pipe : LUT=$luts FF=$ffs SRL=$srls levels=$lvl path=$dly ns fmax=$fmax MHz slack@50MHz=$s50 ns"
    report_timing -max_paths 1 -file $root/reports/timing_daec_${kind}_impl${impl}_pipe${pipe}.txt
    report_utilization -file $root/reports/util_daec_${kind}_impl${impl}_pipe${pipe}.txt
}
close $csv
catch {close_project}
puts "Results written to $root/reports/ooc_results_daec.csv"
