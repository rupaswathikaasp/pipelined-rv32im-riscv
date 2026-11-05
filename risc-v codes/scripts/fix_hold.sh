#!/bin/bash
# Usage: scripts/fix_hold.sh <design> [period_ns]   (run after pnr.sh has produced final2.enc)
source "$(dirname "$0")/../config.sh"
D=${1:?usage: fix_hold.sh <design> [period]}; P=${2:-$PNR_PERIOD}
export DESIGN=$D
export SYNDIR=$PROJ_DIR/results/$D/syn_${NODE}_${CORNER}_${P}ns
export PNRDIR=$PROJ_DIR/results/$D/pnr_${NODE}_${CORNER}_${P}ns
cd $PNRDIR
nohup innovus -nowin -file $PROJ_DIR/scripts/fix_hold.tcl -log $PNRDIR/fixh.log > $PNRDIR/fixh.stdout 2>&1 &
echo "started; watch: tail -f $PNRDIR/fixh.log*"
