#!/bin/bash
# The Assistant quality benchmark: 30 fixed questions over original sample notes, answered offline by
# the default local model through the real Space retrieval; scored on expected facts and citations.
# Usage: scripts/assistant-quality.sh [models-dir]. Writes docs/assistant-quality/<model>.json.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
MODELS="${1:-$HOME/Library/Application Support/Draft/Models}"
if [ ! -f "$MODELS/LFM2.5-2.6B-QAD-Q4_0.gguf" ]; then echo "SKIPPED: no model in $MODELS"; exit 0; fi
WORK=$(mktemp -d)
DRAFT_MODELS_DIR="$MODELS" DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_QUALITY_FIXTURE="$PWD/Tests/Fixtures/assistant-quality.json" \
  DRAFT_AUTOMATION=assistant-quality sandbox-exec -p '(version 1)(allow default)(deny network*)' "$APP" >/dev/null 2>&1
mkdir -p docs/assistant-quality
python3 -I - "$WORK/assistant-quality.json" "docs/assistant-quality" <<'PY'
import json, sys, datetime
r = json.load(open(sys.argv[1]))
r["date"] = datetime.date.today().isoformat()
name = r["model"].replace(" ", "-").replace("/", "-")
json.dump(r, open(f"{sys.argv[2]}/{name}.json", "w"), indent=1, sort_keys=True, ensure_ascii=False)
for x in r["rows"]:
    if not x["pass"]: print("MISS:", x["q"], "->", x["answer"][:160].replace("\n", " "))
print("ASSISTANT QUALITY %d/%d = %.0f%% (%s)" % (r["passed"], r["questions"], r["score"] * 100, r["model"]))
sys.exit(0 if r["score"] >= 0.9 else 1)
PY
