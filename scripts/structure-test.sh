#!/bin/bash
# Tables and collections end to end, plus a 1,000-item collection's open time and scrolling.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
WORK=$(mktemp -d)
DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=structure-write "$APP" >/dev/null 2>&1
DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=structure-read "$APP" >/dev/null 2>&1
python3 -I - "$WORK" <<'PY'
import json, sys
w = json.load(open(sys.argv[1] + "/structure-write.json")); r = json.load(open(sys.argv[1] + "/structure-read.json"))
print(json.dumps({"write": w, "read": r}, indent=1, sort_keys=True))
assert w["items"] == "3" and w["itemsArePages"] == "yes", w
assert w["sorted"] == "Dune,Zen,Atlas" and w["sum"] == "832", w
assert w["dragChanged"] == "1" and w["dragUndone"] == "yes", w
assert w["csvImported"] == "3" and w["csvRoundTrip"] == "yes", w
assert w["screen"] == "collection", w
assert int(w["openMs"]) < 1000, ("1,000 items open in under 1 s", w["openMs"])
assert float(w["scrollP95Ms"]) < 16.7, ("60 fps scrolling", w["scrollP95Ms"])
assert r["items"] == "3" and r["firstItemSame"] == "yes" and r["opensAsPage"] == "yes" and r["table"] == "yes", r
print("STRUCTURE TEST PASSED (1,000 items: open %s ms, scroll p95 %s ms)" % (w["openMs"], w["scrollP95Ms"]))
PY
