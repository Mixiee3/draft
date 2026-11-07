#!/bin/bash
# Linked thinking end to end: write links, tags, tasks and daily notes through the real app,
# then relaunch, then delete index/ and relaunch again. Results must match, and rebuilding
# the index must not change any document file.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
WORK=$(mktemp -d)
V="$WORK/vault"
run() { DRAFT_DATA_DIR="$V" DRAFT_OUT="$WORK" DRAFT_AUTOMATION="$1" DRAFT_RESULT="${2:-}" "$APP" >/dev/null 2>&1; }
run links-write
run links-read links-relaunch.json
sum() { (cd "$V/docs" && shasum *.json | shasum); }
BEFORE=$(sum)
rm -rf "$V/index"
run links-read links-rebuilt.json
AFTER=$(sum)
[ -f "$V/index/index.json" ] && echo "index rebuilt: yes"
python3 -I - "$WORK" "$BEFORE" "$AFTER" <<'PY'
import json, sys
w = json.load(open(sys.argv[1] + "/links-write.json"))
a = json.load(open(sys.argv[1] + "/links-relaunch.json"))
b = json.load(open(sys.argv[1] + "/links-rebuilt.json"))
print(json.dumps({"write": w, "relaunch": a, "rebuilt": b}, indent=1, sort_keys=True))
assert w["pickerFirst"] == "Beta", w
assert w["backlinkMs"] != "timeout" and int(w["backlinkMs"]) < 1000, w["backlinkMs"]
assert w["chipAfterRename"] == "Beta renamed", w
assert w["nestedPage"] and w["blockRefDoc"] == w["nestedPage"], "block reference follows the grouped block"
assert w["blockRefText"].startswith("Goal: ship"), w
assert w["dailyUnique"] == "yes", w
assert w["futureTask"] == "Water plants" and w["futureBucket"] == "upcoming", w
assert w["printerDue"] and w["checkedInEditor"] == "yes" and w["checkedInFile"] == "yes" and w["completedListed"] == "yes", w
assert w["undoSteps"] == "one" and w["uncheckedAfterUndo"] == "yes", w
assert w["missingShown"] == "yes" and w["missingCleared"] == "yes", w
assert w["followed"] == "yes" and w["back"] == "yes" and w["forward"] == "yes", w
assert w["exportLink"] == "yes", w["exportLink"]
assert int(w["reminderPlan"]) >= 1, w
assert w["dueTimeInFile"] == "yes" and w["reminderAtTime"] == "yes" and w["dueUndone"] == "yes", w
assert w["dateStyleKeepsContent"] == "yes", w
assert w["dayTimer"] == "yes" and w["rollover"] == "yes", w
for r in (a, b):
    assert r["chip"] == "Beta renamed", r
    assert r["blockRefDoc"] == w["nestedPage"] and r["blockLocation"] == w["nestedPage"], r
    assert r["dailySame"] == "yes" and r["dailyCount"] == "1", r
    assert r["futureTask"] == "Water plants", r
    assert r["calendarFilters"] == "tasks,true", r
for k in ("backlinks", "tags", "buckets", "blockLocation"):
    assert a[k] == b[k], (k, a[k], b[k])
assert sys.argv[2] == sys.argv[3], "rebuilding the index changed a document file"
print("LINKS TEST PASSED (rebuild %ss)" % b["indexSeconds"])
PY
