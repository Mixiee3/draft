#!/usr/bin/env python3
"""Merges translation batches into Localization/Localizable.xcstrings.

Each batch (Localization/batches/*.json, applied in name order, so 99-short-labels.json wins) maps an English key to either [czech, german] or, for counts,
{"cs": {"one":…, "few":…, "other":…}, "de": {"one":…, "other":…}, "en": {"one":…, "other":…}}
(plural forms keyed on the key's single %lld). Format specifiers must match the key's."""
import json, glob, re, sys
p = "Localization/Localizable.xcstrings"
c = json.load(open(p))
spec = re.compile(r"%(?:\d+\$)?(?:lld|@|d|ld|f|\.\df)")
def check(key, value):
    a = sorted(re.sub(r"\d+\$", "", s) for s in spec.findall(key)); b = sorted(re.sub(r"\d+\$", "", s) for s in spec.findall(value))
    if a != b: sys.exit(f"format mismatch: {key!r} -> {value!r}")
def unit(v): return {"stringUnit": {"state": "translated", "value": v}}
n = 0
for f in sorted(glob.glob("Localization/batches/*.json")):
    for key, t in json.load(open(f)).items():
        if key not in c["strings"]: c["strings"][key] = {"extractionState": "manual"}  # runtime key (loc())
        loc = c["strings"][key].setdefault("localizations", {})
        if isinstance(t, list):
            for lang, v in zip(["cs", "de"], t): check(key, v); loc[lang] = unit(v)
        else:
            for lang, forms in t.items():
                for v in forms.values(): check(key, v)
                loc[lang] = {"variations": {"plural": {k: unit(v) for k, v in forms.items()}}}
        n += 1
json.dump(c, open(p, "w"), ensure_ascii=False, indent=2, sort_keys=True)
print(f"merged {n} strings")
