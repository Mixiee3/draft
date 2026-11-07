#!/bin/bash
# Style studio and export end to end: saved styles across relaunch, fallback on delete, undo,
# block fonts, cards, separators, styled HTML/PDF/PNG and an offline site whose links resolve.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
WORK=$(mktemp -d)
V="$WORK/vault"
DRAFT_DATA_DIR="$V" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=style-write "$APP" >/dev/null 2>&1
DRAFT_DATA_DIR="$V" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=style-read "$APP" >/dev/null 2>&1
python3 -I - "$WORK" <<'PY'
import json, os, re, sys, html, urllib.parse
w = json.load(open(sys.argv[1] + "/style-write.json")); r = json.load(open(sys.argv[1] + "/style-read.json"))
print(json.dumps({"write": w, "read": r}, indent=1, sort_keys=True))
for k in ("styleUndo", "styleRedo", "contrastFix", "sameLook", "contentUntouched", "deleteFallback", "consistent", "onlineDefaultsOff"):
    assert w[k] == "yes", (k, w[k])
assert w["networkRequests"] == "0" and w["networkRequestsAfter"] == "0" and w["searchWhenOff"] == "refused", w
assert int(w["pdfPages"]) >= 2 and w["pdfText"] == "yes", "page break gives a second page; text is real text"
assert r["userStyles"] == "Studio" and r["sameLook"] == "yes", r
assert r["blockFont"] == "mono" and r["card"] == "feature,icon" and r["tapeDiffers"] == "yes" and r["gradient"] == "40.0", r
styled = open(w["export.html"] + "/" + [f for f in os.listdir(w["export.html"]) if f.endswith(".html")][0]).read()
plain_dir = w["export.plainHtml"]; plain = open(plain_dir + "/" + [f for f in os.listdir(plain_dir) if f.endswith(".html")][0]).read()
assert "linear-gradient(130deg, #112233, #ddeeff)" in styled and "#fffef0" in styled and "#fffef0" not in plain, "use style toggle"
assert "font-family:ui-monospace" in styled and "card feature" in styled and styled.count("--r:") == 2
site = w["export.site"]; files = 0; refs = 0
for root, _, names in os.walk(site):
    for n in names:
        if not n.endswith(".html"): continue
        files += 1
        text = open(os.path.join(root, n)).read()
        assert "<script" not in text and "src='http" not in text, n
        for m in re.finditer(r"(?:href|src)='([^']+)'", text):
            ref = html.unescape(m.group(1)).split("#")[0]
            if ref.startswith(("http://", "https://")) or not ref: continue
            p = os.path.join(root, urllib.parse.unquote(ref))
            assert os.path.exists(p), (n, ref)
            refs += 1
assert files >= 4 and refs >= 4, (files, refs)
print("STYLE TEST PASSED (site: %d pages, %d local links all resolve; PDF %s pages)" % (files, refs, w["pdfPages"]))
PY
