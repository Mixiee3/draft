#!/bin/bash
# Tab navigation with real clicks on the tab strip, in a throwaway vault: a document tab activates from
# a folder, All Docs, Settings, Calendar, Tasks, Recently Deleted, Quick Open, another document and a
# nested page, keeping unsaved text, caret and scroll, without duplicate tabs; title-bar buttons
# respond on non-document screens; a deleted note's tab shows a clear state.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
WORK=$(mktemp -d)
DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=nav-test "$APP" >/dev/null 2>&1
python3 -I - "$WORK/nav-test.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); print(json.dumps(r, indent=1, sort_keys=True))
for k in ["folder", "all", "settings", "calendar", "tasks", "trash", "quickopen", "otherdoc", "nested"]:
    assert r[k] == "ok", (k, r[k]); assert r[k + "Tabs"] == "same", (k, r[k + "Tabs"])
assert r["docTabs"] == "1" and r["textKept"] == "yes" and r["breadcrumb"] == "Unsorted", r
assert r["probePlusWorked"] == "yes" and r["probeCardWorked"].startswith("yes"), r
assert r["deletedTabState"] == "shown" and r["backAvailable"] == "yes", r
PY
# Window buttons stay inside the window, centred on the tab row, after resize, zoom, theme and
# focus changes and full screen; the empty title row drags and double-click zooms.
DRAFT_DATA_DIR="$WORK/vault2" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=chrome-test "$APP" >/dev/null 2>&1
python3 -I - "$WORK/chrome-test.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); print(json.dumps(r, indent=1, sort_keys=True))
for k in ["launch", "narrow", "resized", "dark", "light", "zoomed", "settings", "gallery", "inactive", "reactivated", "afterFullscreen", "afterFullscreenResize", "afterDoubleClick"]:
    assert r[k] == "ok", (k, r[k])
assert r["fullscreenEntered"] == "yes" and r["doubleClickZooms"] == "yes" and r["movable"] == "yes" and r["titleRowOwner"] == "V", r
print("NAV TEST PASSED")
PY
