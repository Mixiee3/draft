#!/usr/bin/env python3
"""Static accessibility audit of Draft's SwiftUI sources (no permissions needed).

Reports:
- icon-only buttons (a Button whose label is just an Image) without .accessibilityLabel or .help nearby;
- .onTapGesture controls without an accessibility trait or label (VoiceOver can't activate them as buttons);
- animations not routed through Motion.* (which respects Reduce Motion) or a reduceMotion check.
Exit 1 when anything is found. Usage: python3 scripts/a11y-static.py
"""
import re, glob, sys
problems = []
for f in sorted(glob.glob("Sources/Draft/*.swift")):
    if "/Automation" in f: continue
    lines = open(f).read().split("\n")
    for i, l in enumerate(lines):
        window = "\n".join(lines[i:i + 8])
        # Button { ... } label: { Image(systemName: ...) } with nothing else in the label
        if re.search(r"Button\s*(\([^)]*\))?\s*\{[^}]*\}\s*label:\s*\{\s*Image\(systemName:[^}]*\}\s*$", l) or re.search(r"label:\s*\{\s*Image\(systemName: [^)]*\)[^}]*\}\s*$", l):
            if not re.search(r"accessibilityLabel|\.help\(", window): problems.append(f"{f}:{i+1}: icon-only button without a name")
        if ".onTapGesture" in l and "count: 2" not in l:
            ctx = "\n".join(lines[max(0, i - 6):i + 4])
            if not re.search(r"accessibilityAddTraits\(|accessibilityLabel|accessibilityAction|accessibilityHidden", ctx):
                problems.append(f"{f}:{i+1}: tap gesture without a button trait or label")
        if re.search(r"withAnimation\((?!Motion|nil|reduce|model\.library\.settings\.reduceMotion)", l) or re.search(r"\.animation\(\.(spring|easeInOut|easeOut|easeIn|linear|bouncy|smooth)", l):
            ctx = "\n".join(lines[max(0, i - 3):i + 2])
            if "reduceMotion" not in ctx and "accessibilityReduceMotion" not in ctx:
                problems.append(f"{f}:{i+1}: animation not routed through Motion (ignores Reduce Motion)")
print("\n".join(problems) or "no static accessibility problems found")
print(f"{len(problems)} problems")
sys.exit(1 if problems else 0)
