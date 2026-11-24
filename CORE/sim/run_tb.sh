#!/bin/bash
# Smoke test of archie_main.v with Icarus Verilog (iverilog -g2012).
# Loads a 6-word test program as "ROM", lets the Amber CPU run it and checks
# that it writes and reads back RAM through the Wishbone->Avalon bridge.
# Run from CORE/sim:  ./run_tb.sh
set -e
cd "$(dirname "$0")/.."
R=Archie_MiSTer/rtl
T=$(mktemp -d)
# fdc1772.sv uses "always begin" without an event list (Quartus-ism); make it @* for iverilog
sed 's/^always begin/always @* begin/' $R/fdc/fdc1772.sv > $T/fdc1772.sv
FILES="$(ls $R/amber/a23_*.v | grep -v -E 'config_defines|localparams|functions|decompile|barrel_shift_fpga') \
  $R/vidc/*.v $R/fdc/floppy.v $T/fdc1772.sv $R/EEPROM_24C0x.sv $R/podule_ide.sv $R/ide.v $R/latches.v \
  $R/ioc_irq.v $R/ioc.v $R/memc_translator.v $R/memc.v $R/archimedes_top.v rtl/xilinx_rams.v rtl/archie_main.v"
iverilog -g2012 -I $R/amber -s tb -o $T/tb.vvp sim/tb_archie_main.v sim/cpu_export_stub.v $FILES
cd rtl && vvp -n $T/tb.vvp | grep -v "^VCD" | tail -5
