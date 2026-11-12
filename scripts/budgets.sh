#!/bin/bash
# Performance budgets for every build. Runs each measurement BUDGET_RUNS times (default 3) on
# throwaway vaults, judges every budget on the MEDIAN of the runs (one slow run is reported as noise,
# not a failure), records the machine and display conditions, appends the result to perf-history/
# and writes perf-history/LATEST.md. Exit 1 only when a median is over its documented budget.
# Needs a logged-in GUI session (the app draws); without one it says so and exits 0 (CI-safe).
set -euo pipefail
cd "$(dirname "$0")/.."
RUNS=${BUDGET_RUNS:-3}
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh >/dev/null
if ! pgrep -x WindowServer >/dev/null; then echo "No GUI session: app budgets skipped."; exit 0; fi
W=$(mktemp -d)
probe() { local name=$1 auto=$2; shift 2; local d; d=$(mktemp -d); env "$@" DRAFT_DATA_DIR="$d/vault" DRAFT_OUT="$W/$name" DRAFT_AUTOMATION="$auto" "$APP" >/dev/null 2>&1 || true; rm -rf "$d"; }
for i in $(seq 1 "$RUNS"); do
  mkdir -p "$W/run$i"
  for p in "perf10k perf DRAFT_PERF_BLOCKS=10000" "perf20k perf DRAFT_PERF_BLOCKS=20000" "ux ux-perf X=1" "structure structure-write X=1" "search search-perf X=1"; do
    set -- $p; mkdir -p "$W/run$i/$1"; probe "run$i/$1" "$2" "$3"
  done
  swift test --filter "RecoveryPerfTests|VersionDiffTests/testHistoryOfALargeNote|VaultCheckTests/testTwoThousand" 2>&1 | grep -E "recovery-perf|history 30|vault-check 2000" > "$W/run$i/unit.txt" || true
done
python3 -I - "$W" "$RUNS" <<'PY'
import json, os, sys, re, statistics, subprocess, datetime, platform, glob
w, runs = sys.argv[1], int(sys.argv[2])
def sh(cmd):
    try: return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30).stdout.strip()
    except Exception: return ""
def ua(key):
    v = sh(f"defaults read com.apple.universalaccess {key} 2>/dev/null")
    return {"1": True, "0": False}.get(v, "unknown")
disp = []
try:
    for g in json.loads(sh("system_profiler SPDisplaysDataType -json")).get("SPDisplaysDataType", []):
        for d in g.get("spdisplays_ndrvs", []):
            disp.append({"name": d.get("_name"), "resolution": d.get("_spdisplays_resolution") or d.get("spdisplays_resolution"), "retina": d.get("spdisplays_retina") or d.get("_spdisplays_pixels"), "main": d.get("spdisplays_main") == "spdisplays_yes"})
except Exception: pass
machine = {"model": sh("sysctl -n hw.model"), "chip": sh("sysctl -n machdep.cpu.brand_string"), "macOS": sh("sw_vers -productVersion"),
           "memoryGB": round(int(sh("sysctl -n hw.memsize") or 0) / 2**30), "lowPowerMode": "lowpowermode 1" in sh("pmset -g").replace("  ", " ").replace("lowpowermode         1", "lowpowermode 1"),
           "onBattery": "Battery Power" in sh("pmset -g batt"), "thermal": sh("pmset -g therm | tail -1"), "displays": disp,
           "reduceMotion": ua("reduceMotion"), "increaseContrast": ua("increaseContrast"), "reduceTransparency": ua("reduceTransparency"),
           "commit": sh("git rev-parse --short HEAD"), "build": "release"}
# metric -> (budget ms, getter)
def p95(d, k): return d[k]["p95"] if isinstance(d.get(k), dict) else d.get(k)
B = {
 "10k keystroke p95": (33, "perf10k", lambda d: p95(d, "keystrokeMs")), "10k Return p95": (33, "perf10k", lambda d: p95(d, "returnMs")),
 "10k open": (2500, "perf10k", lambda d: d.get("openMs")), "10k scroll step p95": (16.7, "perf10k", lambda d: p95(d, "scrollMs")),
 "10k toggle": (200, "perf10k", lambda d: d.get("toggleMs")), "10k block move p95": (100, "perf10k", lambda d: p95(d, "moveMs")),
 "search (library)": (500, "perf10k", lambda d: d.get("searchMs")), "link/tag index rebuild": (3000, "perf10k", lambda d: d.get("indexRebuildMs")),
 "20k keystroke p95": (33, "perf20k", lambda d: p95(d, "keystrokeMs")), "20k Return p95": (33, "perf20k", lambda d: p95(d, "returnMs")),
 "20k scroll step p95": (16.7, "perf20k", lambda d: p95(d, "scrollMs")), "20k open": (5000, "perf20k", lambda d: d.get("openMs")),
 "20k toggle (known limit)": (None, "perf20k", lambda d: d.get("toggleMs")),
 "tab switch p95": (50, "ux", lambda d: p95(d, "tabSwitchMs")), "Space switch p95": (100, "ux", lambda d: p95(d, "spaceSwitchMs")),
 "2,000-block doc scroll p95": (16.7, "ux", lambda d: p95(d, "docScrollMs")), "doc open from library": (250, "ux", lambda d: d.get("docOpenFromLibraryMs")),
 "1,000-item collection open": (1000, "structure", lambda d: float(d["openMs"]) if "openMs" in d else None),
 "1,000-item collection scroll p95": (16.7, "structure", lambda d: float(d["scrollP95Ms"]) if "scrollP95Ms" in d else None),
 "search index rebuild (10k blocks)": (3000, "search", lambda d: d.get("rebuildMs")), "search query p95": (500, "search", lambda d: p95(d, "queryMs")),
}
for p in ["format", "style", "info", "share", "assistant", "recovery"]:
    B[f"panel {p} (warm)"] = (100, "ux", lambda d, p=p: d.get("panelOpenMs", {}).get(p))
    B[f"panel {p} (first open)"] = (None, "ux", lambda d, p=p: d.get("panelOpenColdMs", {}).get(p))
for s in ["versionHistory", "reviewSheet"]:
    B[f"sheet {s} render"] = (100, "ux", lambda d, s=s: d.get("sheetRenderMs", {}).get(s))
    B[f"sheet {s} on screen (incl. AppKit animation)"] = (None, "ux", lambda d, s=s: d.get("panelOpenMs", {}).get(s))
U = {"vault check 2,000 notes": (2000, r"vault check \(repair scan\).*?: (\d+) ms"), "Version History 30 versions, 2,000 blocks": (500, r"history 30 versions.*?(\d+) ms"),
     "migration check 2,000 notes": (5000, r"migration validator, 2,000 notes: (\d+) ms"), "migration schema 1→2, 2,000 notes": (5000, r"schema 1 → 2, 2,000 notes: (\d+) ms"),
     "library rebuild 2,000 notes": (3000, r"library rebuild dry run, 2,000 notes: (\d+) ms"), "repair plan": (2000, r"repair plan for every issue: (\d+) ms")}
samples = {k: [] for k in list(B) + list(U)}
for i in range(1, runs + 1):
    for k, (_, src, get) in B.items():
        f = glob.glob(f"{w}/run{i}/{src}/*.json")
        f = [x for x in f if os.path.basename(x).startswith(("perf", "ux-perf", "structure-write", "search-perf"))]
        if not f: continue
        try: v = get(json.load(open(f[0])))
        except Exception: v = None
        if v is not None: samples[k].append(float(v))
    txt = open(f"{w}/run{i}/unit.txt").read() if os.path.exists(f"{w}/run{i}/unit.txt") else ""
    for k, (_, rx) in U.items():
        m = re.search(rx, txt)
        if m: samples[k].append(float(m.group(1)))
budgets = {**{k: v[0] for k, v in B.items()}, **{k: v[0] for k, v in U.items()}}
hist = sorted(glob.glob("perf-history/*.json"))
prev = json.load(open(hist[-1]))["results"] if hist else {}
rows, fails = [], []
for k, xs in samples.items():
    b = budgets[k]
    if not xs: rows.append((k, "—", "", b, "MISSING")); fails.append(k + " (no data)") if b else None; continue
    med = statistics.median(xs)
    over = [x for x in xs if b and x > b]
    status = "info" if b is None else ("FAIL" if med > b else ("noise" if over else "pass"))
    if status == "FAIL": fails.append(k)
    trend = ""
    if k in prev and prev[k]["median"] and med > prev[k]["median"] * 1.5 and med - prev[k]["median"] > 10: trend = f"slower than last ({prev[k]['median']:.0f})"
    rows.append((k, f"{med:.1f}", " / ".join(f"{x:.0f}" for x in xs), b, status + (f" · {trend}" if trend else "")))
stamp = datetime.datetime.now().strftime("%Y-%m-%dT%H-%M-%S")
res = {k: {"median": float(r[1]) if r[1] != "—" else None, "runs": samples[k], "budget": r[3], "status": r[4]} for k, r in zip(samples, rows)}
json.dump({"date": stamp, "runs": runs, "machine": machine, "results": res}, open(f"perf-history/{stamp}.json", "w"), indent=1, sort_keys=True)
md = [f"# Performance budgets — {stamp}", "", f"Commit {machine['commit']} · {runs} runs · median judged · {machine['model']} ({machine['chip']}), macOS {machine['macOS']}, "
      f"{machine['memoryGB']} GB · low power {machine['lowPowerMode']} · battery {machine['onBattery']} · displays {', '.join(str(d.get('resolution')) for d in machine['displays']) or 'unknown'}",
      f"Reduce Motion {machine['reduceMotion']} · Increase Contrast {machine['increaseContrast']} · Reduce Transparency {machine['reduceTransparency']}", "",
      "| Check | Median ms | Runs | Budget | Result |", "|---|---|---|---|---|"]
md += [f"| {k} | {m} | {r} | {('< ' + str(b)) if b else '—'} | {s} |" for k, m, r, b, s in rows]
md += ["", "*pass*: every run under budget · *noise*: a run was over but the median is under · *FAIL*: the median is over · *info*: reported, no budget (known limits and AppKit animations)."]
open("perf-history/LATEST.md", "w").write("\n".join(md) + "\n")
print("\n".join(md))
print("\nBUDGETS " + ("PASSED" if not fails else "FAILED: " + ", ".join(fails)))
sys.exit(1 if fails else 0)
PY
