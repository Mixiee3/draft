#!/bin/bash
# Codex/MCP edit proposals in throwaway vaults: accept with saved result, kept block ids and one undo;
# style proposal; reject; stale revision; links, tags, tasks and nested pages survive a targeted edit.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
WORK=$(mktemp -d)
for s in agent-edit agent-integrity; do DRAFT_DATA_DIR="$WORK/$s" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=$s "$APP" >/dev/null 2>&1; done
python3 -I - "$WORK" <<'PY'
import json, sys
e = json.load(open(sys.argv[1] + "/agent-edit-result.json")); i = json.load(open(sys.argv[1] + "/agent-integrity-result.json"))
print(json.dumps({"edit": e, "integrity": i}, indent=1, sort_keys=True))
assert e["status"] == "accepted" and e["idsKept"] == "yes" and e["undo"] == "yes" and e["styleApplied"] == "yes" and e["styleUndo"] == "yes", e
assert i["rejectStatus"] == "rejected" and i["rejectUnchanged"] == "yes", i
assert i["staleStatus"] == "stale" and i["staleUnchanged"] == "yes", i
for k in ["changed", "tagKept", "taskKept", "linkKept", "cardBefore", "cardKept", "childKept", "indexHasEdit", "undoRestores"]: assert i[k] == "yes", (k, i)
assert int(i["backups"]) >= 1, i
print("AGENT TEST PASSED")
PY
