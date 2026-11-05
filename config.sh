#!/bin/bash
# =====================================================================
#  EDIT THIS FILE ONLY.  Everything else reads from here.
#  Works from bash or csh (all scripts start with #!/bin/bash).
# =====================================================================
export PROJ_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export TOP=riscv_core
export DESIGNS="nonpipelined pipelined"

export NODE=${NODE:-90nm}              # 180nm | 90nm | 45nm
export CORNER=${CORNER:-slow}          # slow | typical | fast
export PERIODS="${PERIODS:-7.2}"   # ns : clock sweep used by syn.sh
export PNR_PERIOD=${PNR_PERIOD:-7.2}     # ns : period used by pnr.sh

# ---- library files (auto-detected from the lab's 90nm folder) ----------
FOUNDRY=/home/install/FOUNDRY/digital/${NODE}/dig
export LIB_FILE="$FOUNDRY/lib/${CORNER}.lib"
export LEF_FILES="$FOUNDRY/lef/gsclib090_translated.lef $FOUNDRY/lef/gsclib090_macro.lef"
# captable: prefer a file whose name contains the corner, else the first one
export CAPTBL="$(ls $FOUNDRY/captable/* 2>/dev/null | grep -i "$CORNER" | head -1)"
[ -z "$CAPTBL" ] && export CAPTBL="$(ls $FOUNDRY/captable/* 2>/dev/null | head -1)"

# ---- Innovus details (auto-detected from the LEF; override below if your
#      earlier lab used different values) ---------------------------------
SITE=""; ROUTING_LAYERS=""
if [ -n "$LEF_FILES" ]; then
  SITE="gsclib090site"
  ROUTING_LAYERS="$(awk '/^LAYER/{n=$2} /TYPE[ \t]+ROUTING/{print n}' $LEF_FILES 2>/dev/null | tr '\n' ' ')"
fi
export SITE
read -r -a RL <<< "$ROUTING_LAYERS"
export RING_H=${RL[2]:-${RL[0]}} ; export RING_V=${RL[3]:-${RL[1]}} ; export STRIPE_V=${RL[3]:-${RL[1]}}
export PWR_NET=VDD ; export GND_NET=VSS
# Example override (uncomment and edit if your lab manual says so):
# export SITE=CoreSite; export RING_H=Metal3; export RING_V=Metal4; export STRIPE_V=Metal4

# ---- simulator ---------------------------------------------------------
# xrun (Xcelium)  |  irun | ncverilog  |  iverilog (open source, for testing)
export SIM=${SIM:-xrun}
export OBJCOPY=${OBJCOPY:-riscv32-unknown-elf-objcopy}
export RING_H=Metal9; export RING_V=Metal8; export STRIPE_V=Metal8
