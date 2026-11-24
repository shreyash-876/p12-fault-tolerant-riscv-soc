# -----------------------------------------------------------------------------
# Vivado project for simulating the XOR-limited pipelined decoders (tb_ecc_xl).
# Works from the Vivado Tcl Shell or the Tcl console - no command-line setup needed.
#
#   cd C:/Users/asus/Documents/RTL_project/p12_final/p12_final/codec_study_1
#   source scripts/create_xl_sim_project.tcl
#   launch_simulation
#   run all
#   close_sim
#
# The testbench prints its result lines in the simulation log; the last line must be
#   PASS: 5438398 checks, 0 errors
# The project is created in <codec folder>/vivado_xl (separate from the earlier codec project).
# -----------------------------------------------------------------------------
set root [file normalize [file dirname [info script]]/..]
create_project p12_xl $root/vivado_xl -part xc7z010clg400-1 -force

add_files [list $root/rtl/ecc/ecc_pkg.sv $root/rtl/ecc/ecc_xl_pkg.sv \
                $root/rtl/ecc/ecc_corr_cmp.sv $root/rtl/ecc/ecc_dec_xl.sv]
set_property file_type SystemVerilog [get_files *.sv]
set_property top ecc_dec_xl [current_fileset]

add_files -fileset sim_1 -norecurse $root/tb/tb_ecc_xl.sv
add_files -fileset sim_1 -norecurse $root/tb/vectors/ecc_vectors.hex
set_property file_type SystemVerilog [get_files tb_ecc_xl.sv]
set_property file_type {Memory Initialization Files} [get_files ecc_vectors.hex]
set_property top tb_ecc_xl [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1
puts "XL simulation project created. Now run:  launch_simulation"
