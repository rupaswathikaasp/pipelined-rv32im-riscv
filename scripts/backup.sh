#!/bin/bash
# Saves a compressed copy of the project (not the heavy Innovus databases).
source "$(dirname "$0")/../config.sh"
F=$HOME/riscv_backup_$(date +%F_%H%M).tgz
tar czf $F -C $(dirname $PROJ_DIR) --exclude='*.enc.dat' --exclude='worklib' --exclude='*.shm' $(basename $PROJ_DIR)
ls -lh $F; echo "Now e-mail / upload this file somewhere OUTSIDE the lab PC."
