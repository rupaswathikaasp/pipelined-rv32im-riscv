# Hold ECO: find hold-violating endpoints in final2 and add a delay buffer on each pin
set OUT $::env(PNRDIR)
restoreDesign $OUT/out/final2.enc.dat $::env(TOP)
setAnalysisMode -analysisType onChipVariation -cppr both
report_timing -early -max_paths 100 -unique > $OUT/rpt/hold_paths.txt
set fh [open $OUT/rpt/hold_paths.txt r]; set data [read $fh]; close $fh
set ep ""; set pins {}
foreach line [split $data "\n"] {
  if {[regexp {^Endpoint:\s+(\S+)} $line m e]} { set ep $e }
  if {[regexp {Slack Time\s+(-[0-9.]+)} $line m s] && $ep != ""} { lappend pins $ep; set ep "" }
}
puts "HOLDFIX: [llength $pins] violating endpoints: $pins"
setEcoMode -refinePlace true
set n 0
foreach p $pins {
  incr n
  if {[catch {ecoAddRepeater -term $p -cell BUFX2 -name hfix_buf_$n} err]} { puts "HOLDFIX ERROR on $p : $err" }
}
catch { ecoRoute }
report_timing        > $OUT/rpt/final3_setup.rpt
report_timing -early > $OUT/rpt/final3_hold.rpt
summaryReport -noHtml -outfile $OUT/rpt/final3_summary.rpt
report_power -outfile $OUT/rpt/final3_power.rpt
verify_drc          -report $OUT/rpt/drc3.rpt
verifyConnectivity  -type all -report $OUT/rpt/conn3.rpt
saveDesign $OUT/out/final3.enc
exit
