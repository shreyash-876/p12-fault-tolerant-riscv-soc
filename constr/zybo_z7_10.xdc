## P12 Stage 1 - Zybo Z7-10 (xc7z010clg400-1)
## Pin numbers follow Digilent's Zybo-Z7 master XDC. Check them against the
## copy for your board revision before the first bitstream.

## 125 MHz system clock
set_property -dict { PACKAGE_PIN K17 IOSTANDARD LVCMOS33 } [get_ports sysclk]
create_clock -name sysclk -period 8.000 [get_ports sysclk]

## Switches
set_property -dict { PACKAGE_PIN G15 IOSTANDARD LVCMOS33 } [get_ports {sw[0]}]
set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {sw[2]}]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS33 } [get_ports {sw[3]}]

## Buttons (BTN3 = reset)
set_property -dict { PACKAGE_PIN K18 IOSTANDARD LVCMOS33 } [get_ports {btn[0]}]
set_property -dict { PACKAGE_PIN P16 IOSTANDARD LVCMOS33 } [get_ports {btn[1]}]
set_property -dict { PACKAGE_PIN K19 IOSTANDARD LVCMOS33 } [get_ports {btn[2]}]
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports {btn[3]}]

## LEDs
set_property -dict { PACKAGE_PIN M14 IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN M15 IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN G14 IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN D18 IOSTANDARD LVCMOS33 } [get_ports {led[3]}]

## UART TX on Pmod JE pin 1. Connect it to the RECEIVE pin of a 3.3 V USB-serial
## adapter (and adapter GND to JE pin 5). If you use a Pmod USBUART plugged into
## JE, move uart_tx to whichever JE pin is that module's receive input.
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports uart_tx]

## Asynchronous board I/O: no timing relationship to the 50 MHz clock
set_false_path -from [get_ports {sw[*] btn[*]}]
set_false_path -to   [get_ports {led[*] uart_tx}]
