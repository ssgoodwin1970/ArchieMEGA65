#!/bin/bash
# Build the bitstream for one board revision and turn it into a .cor file.
# Usage: ./tools/build.sh [r3|r4|r5|r6]     (default r3)
set -e
REV="${1:-r3}"
REVU=$(echo "$REV" | tr a-z A-Z)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source /home/user/Xilinx/Vivado/2023.2/settings64.sh
cd "$ROOT/CORE"
printf 'open_project CORE-%s.xpr\nreset_run synth_1\nlaunch_runs impl_1 -to_step write_bitstream -jobs 4\nwait_on_run impl_1\n' "$REVU" > /tmp/build.tcl
time vivado -mode batch -nojournal -nolog -source /tmp/build.tcl
echo
echo "=== Timing (WNS/WHS must not be negative) ==="
grep -A8 "Design Timing Summary" CORE-$REVU.runs/impl_1/*timing_summary_routed.rpt | tail -3
echo
"$ROOT/tools/make_cor.sh" "$REV"
echo "Built from: $(git -C "$ROOT" log --oneline -1)"
