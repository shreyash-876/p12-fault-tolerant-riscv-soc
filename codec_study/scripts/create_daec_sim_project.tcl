# -----------------------------------------------------------------------------
# Vivado project for simulating the SEC-DED-DAEC codec (tb_daec_codec).
# Works from the Vivado Tcl Shell or the Tcl console:
#   cd C:/Users/asus/Documents/RTL_project/p12_final/p12_final/codec_study_1
#   source scripts/create_daec_sim_project.tcl
#   launch_simulation
# The last line of the log must read:   PASS: <number> checks, 0 errors
# -----------------------------------------------------------------------------
set root [file normalize [file dirname [info script]]/..]
create_project p12_daec $root/vivado_daec -part xc7z010clg400-1 -force

add_files [list $root/rtl/ecc/daec_pkg.sv $root/rtl/ecc/daec_enc_flat.sv $root/rtl/ecc/daec_enc_cse.sv \
                $root/rtl/ecc/daec_enc_tree.sv $root/rtl/ecc/daec_corr_cmp.sv $root/rtl/ecc/daec_enc.sv \
                $root/rtl/ecc/daec_dec.sv $root/rtl/ecc/daec_ooc_wrap.sv]
set_property file_type SystemVerilog [get_files *.sv]
set_property top daec_dec_ooc [current_fileset]

add_files -fileset sim_1 -norecurse $root/tb/tb_daec_codec.sv
add_files -fileset sim_1 -norecurse $root/tb/vectors/daec_vectors.hex
set_property file_type SystemVerilog [get_files tb_daec_codec.sv]
set_property file_type {Memory Initialization Files} [get_files daec_vectors.hex]
set_property top tb_daec_codec [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
update_compile_order -fileset sim_1
puts "DAEC simulation project created. Now run:  launch_simulation"
