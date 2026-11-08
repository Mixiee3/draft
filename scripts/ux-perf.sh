#!/bin/bash
# Interaction timings (tabs, Spaces, library, scrolling, panels) and idle CPU/GPU with a document open.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
WORK=$(mktemp -d)
DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=ux-perf "$APP" >/dev/null 2>&1
DRAFT_DATA_DIR="$WORK/idle" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=idle DRAFT_IDLE_SECONDS=26 "$APP" >/dev/null 2>&1 &
PID=$!
sleep 8
CPU=(); GPU=()
for i in $(seq 1 15); do
  CPU+=("$(ps -p $PID -o %cpu= | tr -d ' ')")
  GPU+=("$(ioreg -r -d 1 -w 0 -c IOAccelerator | grep -o '"Device Utilization %"=[0-9]*' | head -1 | cut -d= -f2)")
  sleep 1
done
wait $PID || true
python3 -I - "$WORK/ux-perf.json" "${CPU[*]}" "${GPU[*]}" <<'PY'
import json, sys, statistics
r = json.load(open(sys.argv[1]))
cpu = [float(x) for x in sys.argv[2].split()]; gpu = [float(x) for x in sys.argv[3].split() if x]
r["idleCpuPercent"] = {"mean": round(statistics.mean(cpu), 1), "max": max(cpu)}
r["idleGpuPercentSystem"] = {"mean": round(statistics.mean(gpu), 1) if gpu else None, "max": max(gpu) if gpu else None}
print(json.dumps(r, indent=1, sort_keys=True))
budget = {"tabSwitchMs": 50, "spaceSwitchMs": 150, "docScrollMs": 16.7}
over = [k for k, b in budget.items() if r[k]["p95"] > b]
for name, v in r["panelOpenMs"].items():
    if v > 100: over.append("panelOpenMs." + name)
if r["idleCpuPercent"]["mean"] > 2: over.append("idleCpuPercent")
print("UX PERF " + ("PASSED" if not over else "OVER BUDGET: " + ", ".join(over)))
PY
