#!/bin/bash
# Local Assistant end to end with networking denied to the whole app: Space answer with sources,
# preview + Replace + one undo, cancel, chat history per Space across a relaunch.
# Usage: scripts/assistant-test.sh [models-dir]   (default: ~/Library/Application Support/Draft/Models)
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
MODELS="${1:-$HOME/Library/Application Support/Draft/Models}"
if [ ! -f "$MODELS/LFM2.5-2.6B-QAD-Q4_0.gguf" ]; then echo "SKIPPED: no model in $MODELS (download it in Settings → Assistant)"; exit 0; fi
WORK=$(mktemp -d)
OFFLINE='(version 1)(allow default)(deny network*)'
DRAFT_MODELS_DIR="$MODELS" DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=assistant-write sandbox-exec -p "$OFFLINE" "$APP" >/dev/null 2>&1
DRAFT_MODELS_DIR="$MODELS" DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=assistant-read sandbox-exec -p "$OFFLINE" "$APP" >/dev/null 2>&1
python3 -I - "$WORK" <<'PY'
import json, sys
w = json.load(open(sys.argv[1] + "/assistant-write.json")); r = json.load(open(sys.argv[1] + "/assistant-read.json"))
print(json.dumps({"write": w, "read": r}, indent=1, sort_keys=True, ensure_ascii=False))
assert w["sourcesFromGarden"] == "yes" and w["jumpOpened"] == "yes", w
assert w["answerMentionsDate"] == "yes", ("grounded answer", w["spaceAnswer"])
assert w["previewCanReplace"] == "yes" and w["replaced"] == "yes" and w["oneUndoRestores"] == "yes", w
assert w["cancelRecorded"] == "yes" and float(w["cancelSeconds"]) < 3, w
assert r["messages"] == w["messages"] and r["sourcesKept"] == "yes" and r["otherSpaceEmpty"] == "yes", r
print("ASSISTANT TEST PASSED (offline; cancel %s s)" % w["cancelSeconds"])
PY
echo "screens: $WORK"
