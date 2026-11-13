#!/bin/bash
# Localization and layout check: the real app in English, Czech and German at 720x640, 960x720 and
# 1440x900 (plus dark at 960x720), main screens captured and read back with on-device text
# recognition. Fails if English shows in Czech/German or a translated label is cut off with "…".
# Screens stay in $L10N_OUT (default: a temp folder); throwaway vaults are deleted.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
O=${L10N_OUT:-$(mktemp -d)}
mkdir -p "$O"
run() { local V; V=$(mktemp -d); env "${@:3}" DRAFT_DATA_DIR="$V/vault" DRAFT_OUT="$O" DRAFT_AUTOMATION=l10n-shots "$APP" -AppleLanguages "($1)" >/dev/null 2>&1 || true; rm -rf "${V:?}"; }
for lang in en cs de; do
  for size in 720x640 960x720 1440x900; do run "$lang" "$size" AUDIT_SIZE="$size"; done
  run "$lang" dark AUDIT_SIZE=960x720 AUDIT_DARK=1
done
python3 -I - "$O" <<'PY'
import json, glob, sys, os
fail = []
for f in sorted(glob.glob(os.path.join(sys.argv[1], "*-l10n.json"))):
    r = json.load(open(f)); name = os.path.basename(f)[:-10]
    eng = {k: v for k, v in r["english"].items() if v} if r["language"] != "en" else {}
    clip = {k: v for k, v in r["clipped"].items() if v}
    print(f"{name:28} English shown: {sum(map(len, eng.values())):3}  clipped: {sum(map(len, clip.values())):3}")
    for k, v in list(eng.items()) + list(clip.items()): print(f"    {k}: {v[:6]}")
    if eng or clip: fail.append(name)
print("L10N CHECK " + ("PASSED" if not fail else "FAILED: " + ", ".join(fail)))
print("screens:", sys.argv[1])
sys.exit(1 if fail else 0)
PY
