#!/bin/bash
# End-to-end persistence check: launch Draft on a temporary vault, write through the real
# editor, quit (the quit path must flush), relaunch, and verify the content came back.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
WORK=$(mktemp -d)
echo "vault: $WORK/vault"
DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=smoke-write "$APP" >/dev/null 2>&1
DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=smoke-read "$APP" >/dev/null 2>&1
cat "$WORK/smoke-result.json"
python3 -I - "$WORK/smoke-result.json" <<'PY'
import json, sys
r = json.load(open(sys.argv[1]))
assert r.get("title") == "Smoke test document", r
assert "Persisted heading" in r["text"] and "survives a restart" in r["text"], r
assert r["bold"] == "yes", r
assert r["style"] == "ember", r
assert r["blocks"].startswith("heading,paragraph,taskList"), r
assert r["tabOpen"] == "yes", r
assert r["trashed"] == "Trash me", r
assert "Trash me" not in r["listed"], r
assert int(r["backups"]) >= 1, r
print("SMOKE TEST PASSED")
PY
