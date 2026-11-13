#!/bin/bash
# The release gate: every suite, on throwaway vaults, one after another (keeps memory low). A release
# ships only when this prints RELEASE CHECK PASSED. Budgets fail only on a consistent miss (median of 3).
#   scripts/release-check.sh [dist/<version>-<build>]   → with a release folder, also verify its signature,
#                                                         notarization state and archive.
# Logs: build/release-check/<suite>.log
set -uo pipefail
cd "$(dirname "$0")/.."
L=build/release-check; rm -rf "$L"; mkdir -p "$L"
JOBS=2 scripts/build-app.sh >"$L/build.log" 2>&1 || { echo "FAIL build (see $L/build.log)"; exit 1; }
results=(); fail=0
gate() { local name=$1; shift; local t0=$SECONDS
  if "$@" >"$L/$name.log" 2>&1; then results+=("PASS $name ($((SECONDS - t0)) s)"); else results+=("FAIL $name ($((SECONDS - t0)) s, $L/$name.log)"); fail=1; fi
  echo "${results[${#results[@]}-1]}"; }
gate unit-tests        swift test -j 2
gate smoke             scripts/smoke.sh
gate mcp               scripts/mcp-test.sh
gate agent             scripts/agent-test.sh
gate assistant-offline scripts/assistant-test.sh
gate nav               scripts/nav-test.sh
gate links             scripts/links-test.sh
gate style-export      scripts/style-test.sh
gate structure         scripts/structure-test.sh
gate workflow          scripts/workflow-test.sh
gate drag              scripts/drag-test.sh
gate trust-recovery    scripts/trust-test.sh        # migration, repair, restore, Safe Mode writes nothing
gate fault-injection   scripts/fault-test.sh
gate updater           scripts/update-test.sh
gate accessibility     python3 -I scripts/a11y-static.py
gate localization      scripts/l10n-check.sh
gate perf              scripts/perf.sh
gate ux-perf           scripts/ux-perf.sh
gate budgets           scripts/budgets.sh
[ -n "${1:-}" ] && gate release-archive scripts/verify-release.sh "$1/Draft.app" "$(ls "$1"/Draft-*.zip | head -1)"
printf '%s\n' "${results[@]}" > "$L/summary.txt"
[ $fail = 0 ] && echo "RELEASE CHECK PASSED" || echo "RELEASE CHECK FAILED"
exit $fail
