# -----------------------------------------------------------------------------
# Out-of-context synthesis + place & route of every codec variant on the XC7Z010-1 (Zybo Z7-10).
# Results -> reports/ooc_results.csv  (then: python reports/fill_table.py)
#
# Run it in the "Vivado 2025.2 Tcl Shell" (Start menu), NOT in the GUI with your project open
# (it creates its own in-memory projects and closes whatever project is open):
#     cd C:/Users/asus/Documents/RTL_project/p12_final/p12_final/codec_study
#     vivado -mode batch -source scripts/ooc_sweep.tcl
# Every input and output of the codec is registered (ecc_ooc_wrap.sv), so the timing is the
# register -> codec -> register path, as inside the memory controller.
#
# The clock is constrained TIGHT (PERIOD = 5 ns) so that Vivado really optimises the path; the
# speed of each variant is then read from the worst path:
#   path_ns      data path delay of the worst register-to-register path (logic + routing)
#   fmax_mhz     1000 / (PERIOD - WNS)
#   slack50_ns   slack this path would have at the real 50 MHz clock = 20 - (PERIOD - WNS)
# Columns: kind, IMPL, PIPE, KEEP (1 = hand XOR structure kept with ECC_KEEP), LUTs, FFs,
#          logic levels, path_ns, WNS at PERIOD, fmax, slack at 50 MHz.
# -----------------------------------------------------------------------------
set root   [file normalize [file dirname [info script]]/..]
set part   xc7z010clg400-1
set period 5.000
set srcs   {ecc_pkg ecc_enc_flat ecc_enc_cse ecc_enc_tree ecc_corr_cmp ecc_corr_espresso ecc_enc ecc_dec ecc_ooc_wrap}

# kind IMPL PIPE KEEP
set configs {
    {enc 0 0 0} {enc 1 0 0} {enc 2 0 0} {enc 3 0 0} {enc 2 0 1} {enc 3 0 1}
    {dec 0 0 0} {dec 1 0 0} {dec 2 0 0} {dec 3 0 0}
    {dec 2 0 1} {dec 3 0 1}
    {dec 2 1 0} {dec 3 1 0}
}

file mkdir $root/reports
set csv [open $root/reports/ooc_results.csv w]
puts $csv "kind,impl,pipe,keep,luts,ffs,logic_levels,path_ns,wns_ns,fmax_mhz,slack50_ns"

foreach cfg $configs {
    lassign $cfg kind impl pipe keep
    catch {close_project}
    create_project -in_memory -part $part
    foreach f $srcs { read_verilog -sv $root/rtl/ecc/$f.sv }

    set args [list -top [expr {$kind eq "enc" ? "ecc_enc_ooc" : "ecc_dec_ooc"}] \
                   -part $part -mode out_of_context -generic IMPL=$impl]
    if {$kind eq "dec"} { lappend args -generic PIPE=$pipe }
    if {$keep}          { lappend args -verilog_define ECC_KEEP }
    synth_design {*}$args

    create_clock -period $period -name clk [get_ports clk]
    opt_design
    place_design
    route_design

    set luts [llength [get_cells -hier -filter {REF_NAME =~ LUT*}]]
    set ffs  [llength [get_cells -hier -filter {REF_NAME =~ FD*}]]
    set path [get_timing_paths -max_paths 1 -nworst 1 -setup]
    set wns  [get_property SLACK $path]
    set lvl  [get_property LOGIC_LEVELS $path]
    set dly  [get_property DATAPATH_DELAY $path]
    set fmax [format %.1f [expr {1000.0 / ($period - $wns)}]]
    set s50  [format %.3f [expr {20.0 - ($period - $wns)}]]
    puts $csv "$kind,$impl,$pipe,$keep,$luts,$ffs,$lvl,$dly,$wns,$fmax,$s50"
    flush $csv
    puts "=== $kind IMPL=$impl PIPE=$pipe KEEP=$keep : LUT=$luts FF=$ffs levels=$lvl path=$dly ns fmax=$fmax MHz slack@50MHz=$s50 ns"
    # keep one timing report per variant for the slides
    report_timing -max_paths 1 -file $root/reports/timing_${kind}_impl${impl}_pipe${pipe}_keep${keep}.txt
}
close $csv
catch {close_project}
puts "Results written to $root/reports/ooc_results.csv"
