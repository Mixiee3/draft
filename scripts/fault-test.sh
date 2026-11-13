#!/bin/bash
# Fault injection on a throwaway vault: Draft is killed with SIGKILL (no cleanup, like a crash or power
# loss for the process) while it types and saves every 20 ms, at a different moment each round. After
# each kill the next launch must notice the crash and find the vault intact (no critical problem, the
# note decodes). Then Safe Mode is checked to write nothing (scripts/trust-test.sh: safe-mode-check).
# Limits: SIGKILL stops the process, not the disk; it can't show what a power cut does to data the OS
# hasn't flushed (Draft relies on atomic rename for that). Out-of-space and permission errors are covered
# by unit tests that make a write fail, not here.
set -uo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || { echo "run scripts/build-app.sh first"; exit 1; }
T=$(mktemp -d); trap 'rm -rf "${T:?}"' EXIT
fail=0
for round in 1 2 3 4 5; do
  rm -f "$T/fault-ready.json" "$T/fault-read.json"
  DRAFT_DATA_DIR=$T/vault DRAFT_OUT=$T DRAFT_AUTOMATION=fault-write "$APP" >/dev/null 2>&1 & P=$!
  for _ in $(seq 1 150); do [ -f "$T/fault-ready.json" ] && break; sleep 0.1; done
  sleep "0.$((RANDOM % 9 + 1))$((RANDOM % 10))"; sleep $round
  kill -0 $P 2>/dev/null || { echo "FAIL round $round: Draft exited before the kill (crash?)"; fail=1; }
  kill -9 $P 2>/dev/null; wait $P 2>/dev/null
  DRAFT_DATA_DIR=$T/vault DRAFT_OUT=$T DRAFT_AUTOMATION=fault-read "$APP" >/dev/null 2>&1
  r=$(python3 -I -c "
import json; r=json.load(open('$T/fault-read.json'))
ok = r['crashNoticed'] and r['critical']==0 and r['docDecodes'] and r['temps']==0
print(('PASS' if ok else 'FAIL'), 'round $round: crash noticed=%s, critical=%d, note decodes=%s, words=%d, temp files=%d %s' % (r['crashNoticed'], r['critical'], r['docDecodes'], r['words'], r['temps'], r['issues'] if not ok else ''))")
  echo "$r"; [[ $r == PASS* ]] || fail=1
done
[ $fail = 0 ] && echo "FAULT TEST PASSED" || echo "FAULT TEST FAILED"
exit $fail
