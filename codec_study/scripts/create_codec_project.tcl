# -----------------------------------------------------------------------------
# P12 Stage 2 codec - Vivado project for simulation and exploration.
#   cd <path>/p12_stage2_codec ; source scripts/create_codec_project.tcl
# Run model/gen.py first (generated RTL and vectors must exist).
# -----------------------------------------------------------------------------
set root [file normalize [file dirname [info script]]/..]
create_project p12_codec $root/vivado -part xc7z010clg400-1 -force

add_files -norecurse $root/rtl/ecc/ecc_pkg.sv
add_files [list $root/rtl/ecc/ecc_enc_flat.sv $root/rtl/ecc/ecc_enc_cse.sv $root/rtl/ecc/ecc_enc_tree.sv \
                $root/rtl/ecc/ecc_corr_cmp.sv $root/rtl/ecc/ecc_corr_espresso.sv \
                $root/rtl/ecc/ecc_enc.sv $root/rtl/ecc/ecc_dec.sv $root/rtl/ecc/ecc_ooc_wrap.sv]
set_property file_type SystemVerilog [get_files *.sv]
set_property top ecc_dec_ooc [current_fileset]

add_files -fileset sim_1 -norecurse $root/tb/tb_ecc_codec.sv
add_files -fileset sim_1 -norecurse $root/tb/vectors/ecc_vectors.hex
set_property file_type SystemVerilog [get_files tb_ecc_codec.sv]
set_property file_type {Memory Initialization Files} [get_files ecc_vectors.hex]
set_property top tb_ecc_codec [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]
puts "Codec project created. Run Behavioral Simulation (top tb_ecc_codec)."
