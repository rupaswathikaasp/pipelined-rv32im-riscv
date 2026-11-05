#!/bin/bash
# Usage:  scripts/syn.sh <design> [period_ns ...]
#   scripts/syn.sh nonpipelined 10          one quick run
#   scripts/syn.sh pipelined 10 7 5 4 3     clock sweep
#   scripts/syn.sh all                      both designs, periods from config.sh
# (No VAR=value prefixes needed, so it works from csh too.)
source "$(dirname "$0")/../config.sh"
D=${1:-all}; shift
PL="$*"; [ -z "$PL" ] && PL="$PERIODS"
[ "$D" = all ] && D="$DESIGNS"
which genus >/dev/null 2>&1 || { echo "ERROR: genus not found - load the Cadence setup first"; exit 1; }
[ -f "$LIB_FILE" ] || { echo "ERROR: library not found: $LIB_FILE (run scripts/check_env.sh)"; exit 1; }
for d in $D; do for P in $PL; do
  export DESIGN=$d CLK_PERIOD=$P
  export OUTDIR=$PROJ_DIR/results/$d/syn_${NODE}_${CORNER}_${P}ns
  mkdir -p $OUTDIR; cd $OUTDIR
  echo ">>> Genus: $d  $NODE/$CORNER  period=${P}ns   (log: $OUTDIR/genus.log)"
  genus -f $PROJ_DIR/scripts/genus_syn.tcl -log $OUTDIR/genus.log -overwrite > $OUTDIR/genus.stdout 2>&1
  if [ -s $OUTDIR/out/${TOP}_netlist.v ]; then
     echo "    done.  area/power/timing: $OUTDIR/rpt"
     grep -m1 -i "slack" $OUTDIR/rpt/timing.rpt | sed 's/^/    /'
  else echo "    FAILED - first errors:"; grep -m5 -E "Error|ERROR" $OUTDIR/genus.log | sed 's/^/    /'; fi
done; done
