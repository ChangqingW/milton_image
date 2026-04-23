#!/usr/bin/env bash
# Build the image on a machine where you have root.
#
# Option A — Apptainer with root (recommended):
#   sudo apptainer build image.sif image.def
#
# Option B — Docker then convert with Apptainer on HPC:
#
# This script implements Option A for convenience.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
OUT=$SCRIPT_DIR/milton.sif

if [[ $EUID -ne 0 ]]; then
    echo "Re-running with sudo..."
    exec sudo "$0" "$@"
fi

apptainer build "$OUT" "$SCRIPT_DIR/milton.def"
echo "Built: $OUT"
