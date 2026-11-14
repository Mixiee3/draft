#!/bin/bash
# Scenario checks that need no clicks, each on a throwaway vault: nested folders and moving a note into one
# (folders-check), Focus Mode, Present, spelling language and vault check (features-check).
# Not covered here, and needs a person: a real mouse drag onto a folder, reminder permission prompts,
# VoiceOver, Reduce Motion, keyboard layouts and input methods. See docs/FEATURE_PARITY.md.
set -uo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || { echo "run scripts/build-app.sh first"; exit 1; }
fail=0
for probe in folders-check features-check; do
  T=$(mktemp -d); mkdir -p "$T/out"
  DRAFT_DATA_DIR="$T/vault" DRAFT_OUT="$T/out" DRAFT_AUTOMATION=$probe "$APP" >/dev/null 2>&1
  python3 -I - "$T/out/$probe.json" "$probe" <<'PY' || fail=1
import json, sys
r = json.load(open(sys.argv[1])); name = sys.argv[2]
want = {
  "folders-check": {"docInSub": True, "subParentIsProjects": True, "rows": ["Getting Started@0", "Projects@0", "Draft@1"]},
  "features-check": {"focus.on": True, "focus.off": True, "present.opened": True, "spelling.set": True, "spelling.automaticAfterClear": True, "check.critical": 0},
}[name]
bad = [k for k, v in want.items() if r.get(k) != v]
for k, v in want.items():
    print(("PASS " if k not in bad else "FAIL ") + name + ": " + k + (" (" + str(r.get(k)) + ")" if k in bad else ""))
sys.exit(1 if bad else 0)
PY
  rm -rf "${T:?}"
done
[ $fail = 0 ] && echo "FEATURE SCENARIOS PASSED" || echo "FEATURE SCENARIOS FAILED"
exit $fail
