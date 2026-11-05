#!/bin/bash
# Usage:  scripts/sim.sh <nonpipelined|pipelined>
# Builds tcm.bin, simulates, prints the 10 test lines + cycle count,
# writes results/<design>/sim/dut.vcd (used later for power).
source "$(dirname "$0")/../config.sh"
D=$1; [ -z "$D" ] && { echo "usage: $0 <nonpipelined|pipelined>"; exit 1; }
which $SIM >/dev/null 2>&1 || { echo "ERROR: '$SIM' not found. Load the Cadence setup in this terminal (or: SIM=irun $0 $D)"; exit 1; }
W=$PROJ_DIR/results/$D/sim; rm -rf $W; mkdir -p $W/build; cd $W

# program image: objcopy if available, else the python converter
if which $OBJCOPY >/dev/null 2>&1; then $OBJCOPY $PROJ_DIR/tb/test.elf -O binary build/tcm.bin
else python3 $PROJ_DIR/scripts/elf2bin.py $PROJ_DIR/tb/test.elf build/tcm.bin; fi
[ -s build/tcm.bin ] || { echo "ERROR: tcm.bin was not created"; exit 1; }

cat > probe.tcl <<TCL
database -open vcddb -vcd -into dut.vcd -default
probe -create tb_top.u_dut -all -depth all -database vcddb
run
exit
TCL
SRC="$PROJ_DIR/rtl/$D/*.v $PROJ_DIR/tb/tb_top.v $PROJ_DIR/tb/tcm_mem.v $PROJ_DIR/tb/tcm_mem_ram.v"
case $SIM in
  xrun)      xrun -64bit -access +rwc -timescale 1ns/1ps -define TRACE=0 -define verilog_sim -incdir $PROJ_DIR/rtl/$D $SRC \
                  +tcm=$W/build/tcm.bin -top tb_top -input probe.tcl -log sim.log > /dev/null 2>&1 ;;
  irun)      irun -access +rwc -timescale 1ns/1ps -define TRACE=0 -define verilog_sim -incdir $PROJ_DIR/rtl/$D $SRC \
                  +tcm=$W/build/tcm.bin -top tb_top -input probe.tcl -log sim.log > /dev/null 2>&1 ;;
  ncverilog) ncverilog +access+rwc +define+TRACE=0 +define+verilog_sim +incdir+$PROJ_DIR/rtl/$D $SRC +nctimescale+1ns/1ps +tcm=$W/build/tcm.bin -l sim.log > /dev/null 2>&1 ;;
  iverilog)  iverilog -g2005 -DTRACE=0 -Dverilog_sim -I$PROJ_DIR/rtl/$D -o s.out $SRC && vvp s.out +tcm=$W/build/tcm.bin > sim.log 2>&1 ;;
esac
[ -s sim.log ] || { echo "ERROR: no sim.log - simulator failed to start"; exit 1; }
grep -E "\*E|ERROR|TIMEOUT|error:" sim.log | head -5
grep -E "^[0-9]+\. " sim.log | sort -u -n | tee tests.txt
N=$(sort -u tests.txt | wc -l)
FT=$(grep -E 'finish.*(at time|called at) [0-9]+' sim.log | sed -nE 's/.*(at time|called at) ([0-9]+).*/\2/p' | tail -1)
# testbench clock = 10 ns, reset released at 45 ns
if [ -n "$FT" ]; then CYC=$(( (FT-45)/10 )); echo "PERF cycles=$CYC" | tee perf.txt
else echo "WARNING: simulation did not reach \$finish - look at $W/sim.log"; fi
echo "tests passed: $N / 10      log: $W/sim.log      waveform: $W/dut.vcd"
