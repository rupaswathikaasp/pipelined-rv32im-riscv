#!/bin/bash
# Run this first.  Tells you what is missing before any long run starts.
source "$(dirname "$0")/../config.sh"
ok(){ echo "  OK   $1"; }; bad(){ echo "  MISSING  $1"; }
echo "Tools:"; for t in genus innovus $SIM python3; do which $t >/dev/null 2>&1 && ok "$t -> $(which $t)" || bad "$t  (load the Cadence setup first, e.g. open a new terminal / source the lab setup file)"; done
echo "Library files:"
[ -f "$LIB_FILE" ] && ok "LIB_FILE=$LIB_FILE" || bad "LIB_FILE=$LIB_FILE"
[ -n "$LEF_FILES" ] && ok "LEF_FILES=$LEF_FILES" || bad "no LEF files found"
[ -n "$CAPTBL" ] && ok "CAPTBL=$CAPTBL" || bad "no captable found"
echo "Innovus details (auto-detected):  SITE=$SITE  RING_H=$RING_H  RING_V=$RING_V  STRIPE_V=$STRIPE_V"
echo "RTL:"; for d in $DESIGNS; do n=$(ls $PROJ_DIR/rtl/$d/*.v 2>/dev/null | wc -l); echo "  $d: $n .v files"; done
