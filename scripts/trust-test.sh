#!/bin/bash
# v0.8 Trust & Recovery: Version History, restore, check, repair, Undo, backups, migration, startup
# recovery, relaunch persistence and Safe Mode, on throwaway vaults. Screens in light, dark and narrow.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
W=${TRUST_OUT:-$(mktemp -d)}
mkdir -p "$W"
run() { DRAFT_DATA_DIR="$1" DRAFT_OUT="$W" DRAFT_AUTOMATION="$2" "$APP" >/dev/null 2>&1; }
V=$(mktemp -d); run "$V/vault" trust-shots; run "$V/vault" trust-read
D=$(mktemp -d); AUDIT_DARK=1 run "$D/vault" trust-shots
N=$(mktemp -d); AUDIT_NARROW=1 run "$N/vault" trust-shots
S=$(mktemp -d); cp -R "$V/vault" "$S/vault"
DRAFT_SAFE_MODE=1 run "$S/vault" safe-mode-check
python3 -I - "$W" <<'PY'
import json, sys, os
w = sys.argv[1]
fail = []
def need(cond, what):
    print(("PASS " if cond else "FAIL ") + what)
    if not cond: fail.append(what)
for p in ["", "dark-", "narrow-"]:
    r = json.load(open(os.path.join(w, p + "trust.json")))
    t = p or "light-"
    need(r["restore.text"] == "matches the version", t + "restore brings the version back")
    need(r["restore.undoOneStep"] and r["restore.redo"], t + "restore is one Undo step (and redo)")
    need(r["restore.beforeRestoreSaved"], t + "the current version is saved before a restore")
    need(r["restore.idsKept"] and r["restore.attachment"], t + "block ids, image and page card survive a restore")
    need(r["history.diffEdited"] == 1 and r["history.diffRemovedInVersion"] == 1, t + "diff: one edited, one not in the version")
    kinds = set(r["check.kinds"])
    need({"docMalformed", "docMissing", "docUnlisted", "blockIdDuplicate", "assetMissing", "parentMissing", "pageCardBroken", "linkBroken", "tempFile", "journalOpen"} <= kinds, t + "check finds every planted problem")
    need(r["repair.brokenRestored"] and r["repair.foundListed"] and r["repair.partialRolledBack"], t + "repair restores, lists and rolls back")
    need(r["repair.left"] == [], t + "no repairable problem left after repair: %s" % r["repair.left"])
    need(r["repair.undo"] and r["repair.again"], t + "repair Undo puts files back; repair again works")
    need(r["migration.ok"], t + "migration check passes on a current vault: %s" % r["migration.problems"][:2])
    need({"change", "version"} <= set(r["backups.kinds"]) and r["backups.health.unreadable"] == 0, t + "backups listed and healthy")
    need(r["startup.detected"] == ["journalOpen"], t + "an interrupted repair is caught at launch")
rr = json.load(open(os.path.join(w, "trust-read.json")))
need(rr["relaunch.restoredText"], "relaunch: the restored version is still there")
need("before-restore" in rr["relaunch.versions"] and "manual" in rr["relaunch.versions"], "relaunch: versions persist")
need(rr["relaunch.check.critical"] == 0, "relaunch: no critical problems")
need(rr.get("relaunch.undoRepair") is True, "relaunch: the repair can still be undone")
sm = json.load(open(os.path.join(w, "safe-mode.json")))
need(sm["safeMode"] and sm["unchanged"], "Safe Mode writes nothing")
assert not fail, fail
print("TRUST TEST PASSED")
PY
rm -rf "$V" "$S" "$D" "$N" # throwaway vaults; the screens and results in $W are kept
echo "screens: $W"
