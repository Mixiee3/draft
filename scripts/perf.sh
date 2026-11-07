#!/bin/bash
# Opens a 10,000-block document in Draft and measures editing; fails if a budget is exceeded.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
W=$(mktemp -d)
DRAFT_DATA_DIR="$W/vault" DRAFT_OUT="$W" DRAFT_AUTOMATION=perf "$APP" >/dev/null 2>&1
cat "$W/perf.json"
python3 -I - "$W/perf.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
# keystroke p95 and toggle are bounded by TextKit 1 contiguous relayout below the edit (see ROADMAP v0.8)
budget = {"keystrokeMs.p50": 16, "keystrokeMs.p95": 40, "returnMs.p95": 33, "moveMs.p95": 100, "toggleMs": 200, "saveMs": 500, "openMs": 2500, "searchMs": 500, "indexRebuildMs": 3000}
fail = []
for k, limit in budget.items():
    v = r
    for part in k.split("."): v = v[part]
    print(f"{k:18} {v:8.1f} ms  (budget {limit})")
    if v > limit: fail.append(k)
assert r["blocks"] >= 10000, r
assert r["searchHits"] == 1, "text past the index limit must be searchable"
assert not fail, f"over budget: {fail}"
print("PERF PASSED")
PY
