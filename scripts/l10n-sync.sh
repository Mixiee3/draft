#!/bin/bash
# Keeps Localization/Localizable.xcstrings in step with the code: the compiler lists every localizable
# literal (Text, Button, LocalizedStringKey, String(localized:), toast, ...), xcstringstool merges them
# (translations kept), then runtime keys the compiler can't see are added: loc("…"), editor command
# titles and Settings section titles. Prints how many strings each language still needs.
set -euo pipefail
cd "$(dirname "$0")/.."
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
swift build -c release --product Draft -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$T" >/dev/null 2>&1
xcrun xcstringstool sync Localization/Localizable.xcstrings --stringsdata "$T"/*.stringsdata >/dev/null
python3 -I - <<'PY'
import json, re, glob
p = "Localization/Localizable.xcstrings"
c = json.load(open(p))
keys = set()
for f in glob.glob("Sources/**/*.swift", recursive=True):
    s = open(f).read()
    keys |= set(re.findall(r'\bloc\("((?:[^"\\]|\\.)+)"\)', s))
    keys |= set(re.findall(r'EditorCommand\("[^"]+", "((?:[^"\\]|\\.)+)"', s))
    if f.endswith("SettingsView.swift"):
        m = re.search(r'static let all: \[.*?\] = \[(.*?)\n    \]', s, re.S)
        if m: keys |= set(re.findall(r'\("[a-z]+", "([^"]+)"', m.group(1)))
keys |= {"Untitled"}
added = 0
for k in sorted(keys):
    k = k.replace('\\"', '"')
    if k not in c["strings"]: c["strings"][k] = {"extractionState": "manual"}; added += 1
    elif c["strings"][k].get("extractionState") == "stale": c["strings"][k]["extractionState"] = "manual"
json.dump(c, open(p, "w"), ensure_ascii=False, indent=2, sort_keys=True)
live = {k: v for k, v in c["strings"].items() if v.get("extractionState") != "stale" and k.strip() and not re.fullmatch(r"[%@lld\s.,:·/()\-–—0-9#•…+×]*", k)}
print(f"{len(live)} strings ({added} runtime keys added)")
for lang in ["cs", "de"]:
    todo = [k for k, v in live.items() if v.get("localizations", {}).get(lang, {}).get("stringUnit", {}).get("state") != "translated" and "variations" not in v.get("localizations", {}).get(lang, {})]
    print(f"{lang}: {len(live) - len(todo)} translated, {len(todo)} to do")
PY
