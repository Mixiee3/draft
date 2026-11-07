#!/bin/bash
# Templates, import of Draft's own export and a Markdown folder, and Spaces across a relaunch.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
WORK=$(mktemp -d)
DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=workflow-write "$APP" >/dev/null 2>&1
DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=workflow-read "$APP" >/dev/null 2>&1
python3 -I - "$WORK" <<'PY'
import json, sys
w = json.load(open(sys.argv[1] + "/workflow-write.json")); r = json.load(open(sys.argv[1] + "/workflow-read.json"))
print(json.dumps({"write": w, "read": r}, indent=1, sort_keys=True))
assert w["templateFreshIds"] == "yes" and w["templateStyle"] == "linen" and "Agenda" in w["templateText"], w
assert w["earlierUnchanged"] == "yes" and w["templatesHidden"] == "yes" and w["builtInTable"] == "yes", w
assert w["importedCount"] == "2" and w["importLinks"] == "yes" and w["importStyle"] == "yes" and w["importFolder"] == "Imports", w
assert int(w["markdownImported"]) >= 2 and int(w["markdownLinks"]) >= 1, w
assert w["unsavedKept"] == "yes" and "sideonly" not in w["homeTags"] and "sideonly" in w["sideTags"], w
assert w["homeHasSideDoc"] == "no" and w["sideDocs"] == "Side note" and w["sideTabHasDoc"] == "yes", w
assert r["spaces"] == "2" and r["activeSpace"] == "home" and r["templates"] == "1" and r["sideTabRestored"] == "yes" and "unsaved words" in r["sideText"], r
print("WORKFLOW TEST PASSED")
PY
