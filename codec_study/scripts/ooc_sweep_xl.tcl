# -----------------------------------------------------------------------------
# Out-of-context synthesis + place & route of the XOR-limited pipelined decoders (ecc_dec_xl, CFG 0..6)
# on the XC7Z010-1 (Zybo Z7-10). Results -> reports/ooc_results_xl.csv   (then: python reports/fill_table_xl.py)
#
# Run in the "Vivado 2025.2 Tcl Shell" (not in the GUI with your project open):
#     cd C:/Users/asus/Documents/RTL_project/p12_final/p12_final/codec_study
#     vivado -mode batch -source scripts/ooc_sweep_xl.tcl
#
# Same method as ooc_sweep.tcl: all ports registered, clock constrained at 5 ns, then
#   fmax = 1000 / (5 - WNS),   slack at 50 MHz = 20 - (5 - WNS).
# Columns: cfg, luts, ffs, logic_levels, path_ns, wns_ns, fmax_mhz, slack50_ns, srls
#   srls = shift-register primitives (SRL16E/SRLC32E): Vivado turns long delay chains into these; they are
#          counted in neither the LUT nor the FF column. reports/util_xl_cfgN.txt has the exact LUT-as-shift-register numbers.
# -----------------------------------------------------------------------------
set root   [file normalize [file dirname [info script]]/..]
set part   xc7z010clg400-1
set period 5.000
set srcs   {ecc_pkg ecc_xl_pkg ecc_corr_cmp ecc_dec_xl ecc_xl_ooc_wrap}
set ncfg   7

file mkdir $root/reports
set csv [open $root/reports/ooc_results_xl.csv w]
puts $csv "cfg,luts,ffs,logic_levels,path_ns,wns_ns,fmax_mhz,slack50_ns,srls"

for {set cfg 0} {$cfg < $ncfg} {incr cfg} {
    catch {close_project}
    create_project -in_memory -part $part
    foreach f $srcs { read_verilog -sv $root/rtl/ecc/$f.sv }

    synth_design -top ecc_dec_xl_ooc -part $part -mode out_of_context -generic CFG=$cfg

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
    puts $csv "$cfg,$luts,$ffs,$lvl,$dly,$wns,$fmax,$s50,$srls"
    flush $csv
    puts "=== xl CFG=$cfg : LUT=$luts FF=$ffs SRL=$srls levels=$lvl path=$dly ns fmax=$fmax MHz slack@50MHz=$s50 ns"
    report_timing -max_paths 1 -file $root/reports/timing_xl_cfg$cfg.txt
    report_utilization -file $root/reports/util_xl_cfg$cfg.txt
}
close $csv
catch {close_project}
puts "Results written to $root/reports/ooc_results_xl.csv"
