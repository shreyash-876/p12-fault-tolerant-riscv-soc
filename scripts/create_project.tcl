# -----------------------------------------------------------------------------
# P12 - create the Vivado project (run from anywhere):
#     vivado -mode batch -source scripts/create_project.tcl        or, in the Tcl console:  source scripts/create_project.tcl
# Part xc7z010clg400-1 (Zybo Z7-10). Nothing in this script has been run in Vivado by the author of the RTL:
# if a command fails, send the error line.
#
# The ITCM is initialised from ONE file, <repo>/vivado_fw/firmware.hex. proc set_firmware copies the program you want
# there:   set_firmware fw_board_demo   (the board demo, default)   fw_ecc_log   fw_irq_stress   fw_csr   fw_ecc_demo   fw_memtest
# Re-run synthesis after changing it (the program is baked into the bitstream); for simulation just re-launch.
# -----------------------------------------------------------------------------
set root  [file normalize [file dirname [info script]]/..]
set fwdir $root/vivado_fw
file mkdir $fwdir
proc set_firmware {name} {
    global root fwdir
    file copy -force $root/fw/$name/firmware.hex $fwdir/firmware.hex
    puts "ITCM image: fw/$name/firmware.hex"
}
set_firmware fw_board_demo

create_project p12 $root/vivado -part xc7z010clg400-1 -force

# ---- RTL (the package must be compiled first) ----
add_files -norecurse $root/rtl/mem/mem_pkg.sv
add_files [glob $root/rtl/core/*.sv]
add_files [glob $root/rtl/ecc/*.sv]
add_files [list $root/rtl/mem/bram_sp.sv $root/rtl/mem/axil_frontend.sv $root/rtl/mem/mem_ctrl.sv \
                $root/rtl/mem/mem_ctrl_ecc.sv $root/rtl/mem/mem_arbiter.sv $root/rtl/mem/ecc_scrubber.sv \
                $root/rtl/mem/ecc_injector.sv $root/rtl/mem/ecc_regs.sv $root/rtl/mem/mem_subsystem.sv \
                $root/rtl/bus/axil_decoder.sv]
add_files [glob $root/rtl/periph/*.sv]
add_files [list $root/rtl/soc/itcm.sv $root/rtl/soc/soc_top.sv $root/rtl/fpga/zybo_top.sv]
set_property file_type SystemVerilog [get_files *.sv]
set_property top zybo_top [current_fileset]

# ---- program image (read by $readmemh("firmware.hex") in itcm.sv) ----
add_files -norecurse $fwdir/firmware.hex
set_property file_type {Memory Initialization Files} [get_files firmware.hex]

# ---- constraints ----
add_files -fileset constrs_1 $root/constr/zybo_z7_10.xdc

# ---- simulation: all testbenches are in sim_1; pick the top (and the matching firmware) in the table of INTEGRATION.md ----
add_files -fileset sim_1 [glob $root/tb/*.sv]
add_files -fileset sim_1 -norecurse $fwdir/firmware.hex
set_property file_type SystemVerilog [get_files -of_objects [get_filesets sim_1] *.sv]
set_property top tb_regs [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

# keep the mark_debug nets through synthesis so "Set Up Debug" (ILA) can find them
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY rebuilt [get_runs synth_1]
puts "Project created in $root/vivado"
