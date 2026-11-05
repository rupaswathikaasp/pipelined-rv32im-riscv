#!/bin/bash
# Run Genus INTERACTIVELY so it stays open at the end (to look at the schematic).
# Usage: scripts/genus_gui.sh <design> [period_ns]
#   then at the genus prompt type:   gui_show      (and 'exit' when done)
source "$(dirname "$0")/../config.sh"
D=${1:?usage: genus_gui.sh <design> [period_ns]}; P=${2:-10}
export DESIGN=$D CLK_PERIOD=$P KEEP_OPEN=1
export OUTDIR=$PROJ_DIR/results/$D/syn_${NODE}_${CORNER}_${P}ns
mkdir -p $OUTDIR; cd $OUTDIR
genus -f $PROJ_DIR/scripts/genus_syn.tcl -log $OUTDIR/genus_gui.log -overwrite
