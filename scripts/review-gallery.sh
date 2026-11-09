#!/bin/bash
# Review sheet captures in a throwaway vault: text replacement, bold/highlight, block formatting,
# separators, block moves, rename and create, in light and dark at normal and narrow width, plus
# Return and Escape pressed as real key events. Writes PNGs and review JSON to the printed folder.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
swift build -q --product DraftMCP >&2
WORK=$(mktemp -d)
DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=agent-seed "$APP" >/dev/null 2>&1
python3 -I - "$PWD" "$WORK" <<'PY'
import json, subprocess, sys, os, hashlib
repo, work = sys.argv[1], sys.argv[2]; vault = work + "/vault"; app = repo + "/build/Draft.app/Contents/MacOS/Draft"
p = subprocess.Popen([repo + "/.build/debug/DraftMCP", "--vault", vault], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True); n = [0]
def rpc(m, a): n[0] += 1; p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": n[0], "method": m, "params": a}) + "\n"); p.stdin.flush(); return json.loads(p.stdout.readline())
def tool(name, **a):
    r = rpc("tools/call", {"name": name, "arguments": a})["result"]; t = r["content"][0]["text"]
    return {"error": t} if r.get("isError") else json.loads(t)
rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "gallery", "version": "1"}})
note = next(d for d in tool("draft_list_documents") if d["title"] == "MCP test note")
def review(shot, theme, narrow=False, key=None, decision="reject", undo=False):
    env = dict(os.environ, DRAFT_DATA_DIR=vault, DRAFT_OUT=work, DRAFT_AUTOMATION="agent-review", DRAFT_AGENT_DECISION=decision, DRAFT_AGENT_THEME=theme, DRAFT_AGENT_SHOT=shot)
    if narrow: env["DRAFT_AGENT_NARROW"] = "1"
    if key: env["DRAFT_AGENT_KEY"] = key
    if undo: env["DRAFT_AGENT_UNDO"] = "1"
    subprocess.run([app], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=90)
    return json.load(open(work + "/agent-review.json"))
def edits():
    st = tool("draft_read_structure", document_id=note["id"]); b = {x["text"]: x for x in st["blocks"]}
    first = next(x for x in st["blocks"] if "zebra-quartz" in x["text"]); task = next(x for x in st["blocks"] if x["text"] == "water the beds")
    return st["revision"], {
        "text": [{"action": "replace_text", "block_id": first["id"], "expected_text": first["text"], "text": "Planning the **spring** beds #garden"}],
        "inline": [{"action": "bold", "block_id": first["id"], "text": "zebra-quartz"}, {"action": "highlight", "block_id": first["id"], "text": "zebra-quartz", "value": "#fff3a3"}],
        "block": [{"action": "heading", "block_id": first["id"], "value": "title"}, {"action": "block_kind", "block_id": b["Plain closing line"]["id"], "value": "callout"}, {"action": "decoration", "block_id": task["id"], "value": "focus"}, {"action": "block_color", "block_id": b["Plain closing line"]["id"], "value": "#fff4d6"}],
        "separator": [{"action": "insert_separator", "block_id": task["id"], "value": "wave"}, {"action": "insert_separator", "block_id": first["id"], "value": "tape"}],
        "move": [{"action": "move_block", "block_id": b["Plain closing line"]["id"], "target": first["id"], "position": "before"}],
        "table": (lambda tb: [{"action": "table_set_cell", "block_id": tb["id"], "target": tb["rows"][1]["cells"][0]["id"], "text": "**Broad beans**", "expected_text": "Beans"},
                              {"action": "table_insert_row", "block_id": tb["id"], "target": tb["rows"][1]["id"], "position": "after", "text": "Kale | 5"}])(next(x for x in st["blocks"] if x["type"] == "table")),
    }
results = {}
for kind in ["text", "inline", "block", "separator", "move", "rename", "table", "collection", "image"]:
    for theme, narrow in [("light", False), ("dark", True)]:
        rev, e = edits()
        if kind == "rename": tool("draft_propose_rename_document", document_id=note["id"], expected_revision=rev, title="Spring planning", instruction="A clearer title")
        elif kind == "image":
            import struct, zlib
            w, h = 120, 80
            raw = b"".join(b"\x00" + bytes((x * 2 + y) % 256 for x in range(w * 3)) for y in range(h))
            ch = lambda t, d: struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
            path = work + "/study-sketch.png"
            open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + ch(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + ch(b"IDAT", zlib.compress(raw)) + ch(b"IEND", b""))
            st = tool("draft_read_structure", document_id=note["id"]); anchor = next(x for x in st["blocks"] if "zebra-quartz" in x["text"])
            tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Add the study sketch", edits=[
                {"action": "insert_image", "block_id": anchor["id"], "value": path, "text": "Sketch of the spring beds"}])
        elif kind == "collection":
            books = next(d for d in tool("draft_list_documents") if d["title"] == "Reading list")
            bst = tool("draft_read_structure", document_id=books["id"]); cb = next(x for x in bst["blocks"] if x["type"] == "collection")
            col = tool("draft_read_collection", document_id=books["id"], block_id=cb["id"]); its = {i["title"]: i["id"] for i in col["items"]}
            tv = next(v["id"] for v in col["views"] if v["type"] == "table")
            tool("draft_propose_note_edits", document_id=books["id"], expected_revision=bst["revision"], instruction="Organise the reading list", edits=[
                {"action": "collection_add_item", "block_id": cb["id"], "text": "Dune", "value": '{"Status": "Doing"}'},
                {"action": "collection_update_item", "block_id": cb["id"], "target": its["Atlas"], "value": '{"Status": "Done"}'},
                {"action": "collection_set_view", "block_id": cb["id"], "target": tv, "value": '{"sort": [{"field": "Status", "ascending": true}], "filters": [{"field": "Status", "op": "isNot", "value": "To do"}]}'}])
        else: tool("draft_propose_note_edits", document_id=note["id"], expected_revision=rev, instruction=f"Review: {kind}", edits=e[kind])
        r = review(f"review-{kind}-{theme}{'-narrow' if narrow else ''}", theme, narrow)
        results[f"{kind}-{theme}"] = {k: r.get(k) for k in ["status", "sheetSize", "sheetInsideWindow"]}
before = hashlib.sha256(open(f"{vault}/docs/{note['id']}.json", "rb").read()).hexdigest()
rev, e = edits(); tool("draft_propose_note_edits", document_id=note["id"], expected_revision=rev, instruction="Escape rejects", edits=e["inline"])
r = review("review-escape", "light", key="escape")
results["escape"] = {"status": r["status"], "closed": r.get("sheetClosedByKey"), "unchanged": hashlib.sha256(open(f"{vault}/docs/{note['id']}.json", "rb").read()).hexdigest() == before}
rev, e = edits(); tool("draft_propose_note_edits", document_id=note["id"], expected_revision=rev, instruction="Return applies", edits=e["inline"] + e["separator"])
r = review("review-return", "dark", key="return", undo=True)
results["return"] = {"status": r["status"], "closed": r.get("sheetClosedByKey"), "applied": "bold" in r["afterMarks"] and "horizontalRule" in r["afterTypes"], "oneUndo": "bold" not in r["undoneMarks"] and "horizontalRule" not in r["undoneTypes"]}
print(json.dumps(results, indent=1)); print("folder:", work)
p.stdin.close()
PY
