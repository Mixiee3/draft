#!/bin/bash
# Drags a block with mouse events sent through Draft's window (mouse down on the handle,
# dragged, up), then checks undo/redo and a relaunch preserve order, text, marks, checkboxes and ids.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
W=$(mktemp -d)
for mode in drag-write drag-read; do DRAFT_DATA_DIR="$W/vault" DRAFT_OUT="$W" DRAFT_AUTOMATION=$mode "$APP" >/dev/null 2>&1; done
python3 -I - "$W/drag-result.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1])); r.pop("afterDrag")
print(json.dumps(r, indent=1))
assert r["order"] == "Bravo,Charlie,Delta,Alpha,Echo", r
assert all(r[k] == "yes" for k in ("idsPreserved", "undoRestored", "redoMatchesDrag", "relaunchMatchesDrag")), r
print("DRAG TEST PASSED")
PY
