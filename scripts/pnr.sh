#!/bin/bash
# Usage:  scripts/pnr.sh <design> [period_ns]      (run syn.sh for that period first)
# Innovus runs in the BACKGROUND with nohup, so a closed/crashed terminal
# does not kill it.  Watch it with:  tail -f <pnr dir>/innovus.log
source "$(dirname "$0")/../config.sh"
D=${1:?usage: pnr.sh <design> [period_ns]}; P=${2:-$PNR_PERIOD}
which innovus >/dev/null 2>&1 || { echo "ERROR: innovus not found - load the Cadence setup first"; exit 1; }
export DESIGN=$D
export SYNDIR=$PROJ_DIR/results/$D/syn_${NODE}_${CORNER}_${P}ns
export PNRDIR=$PROJ_DIR/results/$D/pnr_${NODE}_${CORNER}_${P}ns
[ -f $SYNDIR/out/${TOP}_netlist.v ] || { echo "No netlist at $SYNDIR - run: scripts/syn.sh $D $P"; exit 1; }
mkdir -p $PNRDIR; cd $PNRDIR
echo ">>> Innovus: $D  period=${P}ns   log: $PNRDIR/innovus.log"
nohup innovus -nowin -file $PROJ_DIR/scripts/innovus_pnr.tcl -log $PNRDIR/innovus.log > $PNRDIR/innovus.stdout 2>&1 &
echo "    started in background (pid $!).  Watch:  tail -f $PNRDIR/innovus.log"
echo "    when finished, reports are in $PNRDIR/rpt"
