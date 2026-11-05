#!/bin/bash
# Builds results/summary.csv from reports. Parsing is best-effort: open one report and confirm the columns once.
source "$(dirname "$0")/../config.sh"
CSV=$PROJ_DIR/results/summary.csv
echo "design,period_ns,area_um2,cells,leak_W,dyn_total_W(vectorless),slack_ns,fmax_MHz,sim_cycles,exec_time_us" > $CSV
for D in $DESIGNS; do
  CYC=$(grep -o "cycles=[0-9]*" $PROJ_DIR/results/$D/sim/perf.txt 2>/dev/null | head -1 | cut -d= -f2)
  for R in $PROJ_DIR/results/$D/syn_${NODE}_${CORNER}_*ns; do
    [ -d $R ] || continue
    P=$(basename $R | sed 's/.*_\([0-9.]*\)ns/\1/')
    AREA=$(awk -v t=$TOP '$1==t {print $(NF-1); exit}' $R/rpt/area.rpt)         # Total Area column
    CELLS=$(awk -v t=$TOP '$1==t {print $3; exit}' $R/rpt/area.rpt)
    RPT=$R/rpt/power_vcd.rpt; [ -f $RPT ] || RPT=$R/rpt/power_vectorless.rpt
    LEAK=$(awk '$1=="Total"{print $2; exit}' $RPT)
    TOT=$(awk '$1=="Total"{print $5; exit}' $RPT)
    SL=$(grep -m1 -E "Slack:=" $R/rpt/timing.rpt | awk '{print $NF}')
    FMAX=$(awk -v p=$P -v s=${SL:-0} 'BEGIN{printf "%.1f", 1000/(p-s)}')
    EXEC=$(awk -v c=${CYC:-0} -v p=$P -v s=${SL:-0} 'BEGIN{printf "%.2f", c*(p-s)/1000}')   # at achievable period
    echo "$D,$P,$AREA,$CELLS,$LEAK,$TOT,$SL,$FMAX,$CYC,$EXEC" >> $CSV
  done
done
column -s, -t $CSV
