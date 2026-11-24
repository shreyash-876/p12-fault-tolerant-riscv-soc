# Program the Zybo Z7-10 over JTAG (USB cable on the PROG/UART micro-USB port):  vivado -mode batch -source scripts/program_board.tcl
set root [file normalize [file dirname [info script]]/..]
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7z010*] 0]
current_hw_device $dev
set_property PROGRAM.FILE $root/p12_zybo.bit $dev
program_hw_devices $dev
puts "programmed $dev"
