#!/bin/bash
# The Draft MCP server end to end, over real stdio, in a throwaway vault: every read tool, then
# proposals for formatting, block changes, create, rename and move, each reviewed in the running app
# (accept, one Undo, reject, stale revision, invalid), plus persistence and an index rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Draft.app/Contents/MacOS/Draft
[ -x "$APP" ] || scripts/build-app.sh
swift build -q --product DraftMCP >&2
WORK=$(mktemp -d)
DRAFT_DATA_DIR="$WORK/vault" DRAFT_OUT="$WORK" DRAFT_AUTOMATION=agent-seed "$APP" >/dev/null 2>&1
python3 -I - "$PWD" "$WORK" <<'PY'
import json, subprocess, sys, hashlib, os, shutil
repo, work = sys.argv[1], sys.argv[2]
vault = work + "/vault"
app = repo + "/build/Draft.app/Contents/MacOS/Draft"
checks = {}
def ok(name, cond, detail=""):
    checks[name] = bool(cond)
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else "  " + str(detail)[:300]))

class MCP:
    def __init__(self, name="mcp-test"):
        self.p = subprocess.Popen([repo + "/.build/debug/DraftMCP", "--vault", vault], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        self.n = 0
        self.rpc("initialize", {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": name, "version": "1"}})
    def rpc(self, method, params):
        self.n += 1
        self.p.stdin.write(json.dumps({"jsonrpc": "2.0", "id": self.n, "method": method, "params": params}) + "\n"); self.p.stdin.flush()
        return json.loads(self.p.stdout.readline())
    def tool(self, name, /, **args):
        r = self.rpc("tools/call", {"name": name, "arguments": args})["result"]
        text = r["content"][0]["text"]
        if r.get("isError"): return {"error": text}
        try: return json.loads(text)
        except ValueError: return text
    def close(self): self.p.stdin.close(); self.p.wait(timeout=5)

def review(decision="accept", undo=False, shot=None, revoke=False):
    env = dict(os.environ, DRAFT_DATA_DIR=vault, DRAFT_OUT=work, DRAFT_AUTOMATION="agent-review", DRAFT_AGENT_DECISION=decision)
    if revoke: env["DRAFT_AGENT_REVOKE"] = "1"
    if undo: env["DRAFT_AGENT_UNDO"] = "1"
    if shot: env["DRAFT_AGENT_SHOT"] = shot
    subprocess.run([app], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=90)
    return json.load(open(work + "/agent-review.json"))

def filehash(doc): return hashlib.sha256(open(f"{vault}/docs/{doc}.json", "rb").read()).hexdigest()
def content(doc): return m.tool("draft_read_document", document_id=doc)  # what the note says, ignoring save times

m = MCP()
tools = [t["name"] for t in m.rpc("tools/list", {})["result"]["tools"]]
print("tools:", ", ".join(tools))
ok("tools listed", len(tools) == 18, tools)
spaces = m.tool("draft_list_spaces"); ok("1 list spaces", len(spaces) == 2, spaces)
docs = m.tool("draft_list_documents"); note = next(d for d in docs if d["title"] == "MCP test note"); ok("2 list documents", note, docs)
hits = m.tool("draft_search", query="zebra-quartz"); ok("3 search", hits and hits[0]["document_id"] == note["id"], hits)
st = m.tool("draft_read_structure", document_id=note["id"]); blocks = st["blocks"]; ok("4 read structure", st["revision"] and len(blocks) >= 6, st)
first = next(b for b in blocks if "zebra-quartz" in b["text"])
blk = m.tool("draft_read_block", document_id=note["id"], block_id=first["id"]); ok("5 read block", "zebra-quartz" in blk, blk)
guide = m.tool("draft_formatting_guide"); ok("6 formatting guide", "recipe_make_it_look_better" in guide and "wave" in guide["separator_styles"], list(guide))
folders = m.tool("draft_list_folders"); archive = next(f for f in folders if f["name"] == "Archive"); ok("list folders", archive)
original = m.tool("draft_read_document", document_id=note["id"])
before = filehash(note["id"])
p = m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Emphasise the code word",
           edits=[{"action": "bold", "block_id": first["id"], "text": "zebra-quartz"}, {"action": "highlight", "block_id": first["id"], "text": "zebra-quartz", "value": "#fff3a3"}])
ok("7 propose formatting", p.get("status") == "pending", p)
ok("8 note unchanged before approval", filehash(note["id"]) == before)
r = review("accept", undo=True, shot="mcp-review-formatting")
ok("9-10 review shown and accepted", r["status"] == "accepted", r)
ok("11 change saved", "bold" in r["afterMarks"] and "highlight" in r["afterMarks"], r["afterMarks"])
ok("12 index updated", "zebra-quartz" in r["afterIndex"], r["afterIndex"])
ok("13 one Undo restores", "bold" not in r["undoneMarks"] and r["undoneText"] == r["afterText"] and m.tool("draft_read_document", document_id=note["id"]) == original, r)
ok("backup made", int(r["backups"]) >= 1, r["backups"])

# Styling through reviewed proposals: a text effect, a block effect, then a custom backdrop.
st = m.tool("draft_read_structure", document_id=note["id"]); first = st["blocks"][0]; original = content(note["id"])
ok("guide lists effects", [e["value"] for e in guide["text_effects"]][:2] == ["accent", "gradient"] and any(b["value"] == "glass" for b in guide["block_effects"]), guide.get("text_effects"))
p = m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Make the code word stand out",
           edits=[{"action": "text_effect", "block_id": first["id"], "text": "zebra-quartz", "value": "gradient"}, {"action": "decoration", "block_id": first["id"], "value": "glass"}])
r = review("accept", undo=True, shot="mcp-review-effects")
ok("effects applied", r["status"] == "accepted" and "effect" in r["afterMarks"] and r["afterDecorations"] == "glass", r)
ok("effects one Undo", "effect" not in r["undoneMarks"] and r["undoneDecorations"] == "" and content(note["id"]) == original, r)
st = m.tool("draft_read_structure", document_id=note["id"])
harsh = m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Harsh", edits=[{"action": "document_backdrop", "block_id": note["id"], "value": json.dumps({"stops": [{"color": "#000000", "at": 0}, {"color": "#ffffff", "at": 1}]})}])
ok("harsh backdrop refused", "4.5:1" in str(harsh.get("error", "")), harsh)
p = m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Soft blue backdrop",
           edits=[{"action": "document_backdrop", "block_id": note["id"], "value": json.dumps({"stops": [{"color": "#e3ecfa", "at": 0}, {"color": "#c9d7f2", "at": 0.6}, {"color": "#b8c7ea", "at": 1}], "radial": True, "focusX": 0.2, "focusY": 0.1})}])
r = review("accept", undo=True, shot="mcp-review-style")
ok("backdrop applied", r["status"] == "accepted" and r["afterBackdrop"] == "#e3ecfa,#c9d7f2,#b8c7ea", r)
ok("backdrop one Undo", r["undoneBackdrop"] == "" and content(note["id"]) == original, r)

st = m.tool("draft_read_structure", document_id=note["id"]); before = filehash(note["id"])
p = m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Reword", edits=[{"action": "replace_text", "block_id": first["id"], "text": "Rejected words", "expected_text": first["text"]}])
r = review("reject")
ok("14 reject leaves note unchanged", r["status"] == "rejected" and filehash(note["id"]) == before and m.tool("draft_request_status", request_id=p["request_id"])["status"] == "rejected", r)

# Stale: two proposals from the same revision; the first one applied makes the second stale.
st = m.tool("draft_read_structure", document_id=note["id"]); last = next(b for b in st["blocks"] if b["text"] == "Plain closing line")
a = m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Italic", edits=[{"action": "italic", "block_id": last["id"], "text": "closing"}])
b = m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Strike", edits=[{"action": "strike", "block_id": last["id"], "text": "closing"}])
review("accept"); after_a = filehash(note["id"]); r = review("accept")
ok("15 stale revision refused at apply", r["status"] == "stale" and filehash(note["id"]) == after_a and "changed" in r["result"], r)
old = m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Late", edits=[{"action": "bold", "block_id": last["id"], "text": "closing"}])
ok("15 stale revision refused at proposal", "error" in old and "changed" in old["error"], old)

st = m.tool("draft_read_structure", document_id=note["id"])
bad = m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Bad", edits=[{"action": "explode", "block_id": last["id"]}])
ok("16 invalid action refused by the server", "error" in bad, bad)
before = filehash(note["id"])
m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Bold a missing phrase", edits=[{"action": "bold", "block_id": last["id"], "text": "not there"}])
r = review("accept")
ok("16 invalid edit fails in Draft without changes", r["status"] == "failed" and filehash(note["id"]) == before, r)
image = next(b for b in st["blocks"] if b["type"] == "image")
m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Remove image", edits=[{"action": "delete_block", "block_id": image["id"]}])
r = review("accept"); ok("attachments can't be deleted", r["status"] == "failed" and "image" in r["afterTypes"], r)
for kind in ["file", "table", "pageCard"]:
    st = m.tool("draft_read_structure", document_id=note["id"]); b = next(x for x in st["blocks"] if x["type"] == kind)
    m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction=f"Remove {kind}", edits=[{"action": "delete_block", "block_id": b["id"]}])
    r = review("accept"); ok(f"{kind} can't be deleted", r["status"] == "failed" and kind in r["afterTypes"], r)
st = m.tool("draft_read_structure", document_id=note["id"])
m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Rewrite everything", edits=[{"action": "replace_document", "block_id": note["id"], "text": "# Fresh\nOnly text"}])
r = review("accept"); ok("whole-note replacement refused with attachments", r["status"] == "failed" and all(k in r["afterTypes"] for k in ["image", "file", "table", "pageCard"]) and "link" in r["afterMarks"], r)

# Block operations, links, tags, tasks and formatting in one proposal; one Undo reverses all of it.
st = m.tool("draft_read_structure", document_id=note["id"]); by = {b["text"]: b for b in st["blocks"]}
task = next(b for b in st["blocks"] if b["text"] == "water the beds")
p = m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Tidy the note", edits=[
    {"action": "insert_blocks", "block_id": first["id"], "position": "after", "text": "## Next steps\n- [ ] order compost #shopping"},
    {"action": "append", "block_id": note["id"], "text": "Summary: plant in **April**."},
    {"action": "move_block", "block_id": by["Plain closing line"]["id"], "target": first["id"], "position": "before"},
    {"action": "delete_block", "block_id": by["See the guide"]["id"]},
    {"action": "task_checked", "block_id": task["id"], "value": "true"},
    {"action": "link", "block_id": first["id"], "text": "Planning", "value": "https://example.com/plan"},
    {"action": "heading", "block_id": first["id"], "value": "title"},
    {"action": "insert_separator", "block_id": task["id"], "value": "wave"},
    {"action": "block_kind", "block_id": by["Plain closing line"]["id"], "value": "callout"},
])
r = review("accept", undo=True, shot="mcp-review-blocks")
t = r["afterTypes"].split(",")
ok("insert, append, move, delete applied", r["status"] == "accepted" and "Next steps" in r["afterText"] and "Summary: plant in April." in r["afterText"] and "See the guide" not in r["afterText"] and r["afterText"].startswith("Plain closing line"), r)
ok("links, tags, tasks", "link:https://example.com/plan" in r["afterMarks"] and "#shopping" in r["afterText"] and "true" in r["afterTasks"], r)
ok("images, files, table and nested page kept", all(x in t for x in ["image", "file", "table", "pageCard"]) and "horizontalRule" in t and "callout" in t, t)
ok("block proposal is one Undo", r["undoneText"] == m.tool("draft_read_document", document_id=note["id"]) or "Next steps" not in r["undoneText"] and "See the guide" in r["undoneText"], r)

# Create: reviewed, fresh ids, folder, index; reject; stale; Undo; persistence.
md = "## Packing\n- [ ] tent\n- [x] stove\n\nMeet at the **station** #trip"
c = m.tool("draft_propose_create_document", title="Trip plan", markdown=md, folder_id=archive["id"], instruction="Create a trip note")
ok("create proposal queued", c.get("status") == "pending" and not any(d["title"] == "Trip plan" for d in m.tool("draft_list_documents")), c)
r = review("accept", shot="mcp-review-create")
new = r["documentId"]
ok("create accepted into the folder", r["status"] == "accepted" and r["afterTitle"] == "Trip plan" and r["afterFolder"] == archive["id"] and "station" in r["afterText"], r)
ok("created note indexed", "station" in r["afterIndex"], r["afterIndex"])
ids = [b["id"] for b in m.tool("draft_read_structure", document_id=new)["blocks"]]
ok("created note has fresh unique ids", len(ids) == len(set(ids)) and all(i not in [b["id"] for b in st["blocks"]] for i in ids), ids)
m.tool("draft_propose_create_document", title="Rejected note", instruction="Should not exist")
r = review("reject"); ok("create rejected", r["status"] == "rejected" and not any(d["title"] == "Rejected note" for d in m.tool("draft_list_documents")), r)
m.tool("draft_propose_create_document", title="Undo me", markdown="Temporary", instruction="Create then undo")
r = review("accept", undo=True); ok("create undone in one step", r["status"] == "accepted" and r["undoneDeleted"] == "yes", r)
m.tool("draft_propose_create_document", title="Stale note", folder_id=archive["id"], instruction="Library changes first")
subprocess.run([app], env=dict(os.environ, DRAFT_DATA_DIR=vault, DRAFT_OUT=work + "/reseed", DRAFT_AUTOMATION="agent-seed"), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=120) if os.makedirs(work + "/reseed", exist_ok=True) is None else None
r = review("accept"); ok("create stale after folders changed", r["status"] == "stale", r)

# Rename and move, each one Undo.
st = m.tool("draft_read_structure", document_id=new)
m.tool("draft_propose_rename_document", document_id=new, expected_revision=st["revision"], title="Autumn trip", instruction="Rename")
r = review("accept", undo=True); ok("rename and undo", r["afterTitle"] == "Autumn trip" and r["undoneTitle"] == "Trip plan", r)
work_space = next(s for s in m.tool("draft_list_spaces") if s["name"] == "Work")
st = m.tool("draft_read_structure", document_id=note["id"])
m.tool("draft_propose_move_document", document_id=note["id"], expected_revision=st["revision"], folder_id=archive["id"], instruction="File it")
r = review("accept", undo=True); ok("move to folder and undo", r["afterFolder"] == archive["id"] and r["undoneFolder"] == "unsorted", r)
st = m.tool("draft_read_structure", document_id=new)
m.tool("draft_propose_move_document", document_id=new, expected_revision=st["revision"], space_id=work_space["id"], instruction="Move to Work")
r = review("accept"); ok("move to another Space", r["afterSpace"] == work_space["id"] and any(d["title"] == "Trip plan" for d in m.tool("draft_list_documents", space_id=work_space["id"])), r)

# Tables: cells, rows and columns by id; preview; one Undo; all or nothing; permission; persistence.
def table_block():
    st = m.tool("draft_read_structure", document_id=note["id"]); return st, next(b for b in st["blocks"] if b["type"] == "table")
st, tb = table_block()
ok("structure lists table rows and cell ids", tb.get("rows") and tb["rows"][1]["cells"][0]["text"] == "Beans" and all(c["id"] for r in tb["rows"] for c in r["cells"]), tb)
hdr, beans = tb["rows"][0], tb["rows"][1]
p = m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Tidy the table", edits=[
    {"action": "table_set_cell", "block_id": tb["id"], "target": beans["cells"][0]["id"], "text": "**Broad beans**", "expected_text": "Beans"},
    {"action": "table_insert_row", "block_id": tb["id"], "target": beans["id"], "position": "after", "text": "Kale | 5"},
    {"action": "table_insert_column", "block_id": tb["id"], "target": hdr["cells"][1]["id"], "position": "after", "text": "Notes | early | late"},
    {"action": "table_move_column", "block_id": tb["id"], "target": hdr["cells"][1]["id"], "value": hdr["cells"][0]["id"], "position": "before"}])
r = review("accept", undo=True, shot="mcp-review-table")
ok("table edits applied", r["status"] == "accepted" and r["afterTable"] == "Bed|Crop|Notes / 3|Broad beans|early / 5|Kale|late", r.get("afterTable"))
ok("table proposal is one Undo", r["undoneTable"] == "Crop|Bed / Beans|3", r.get("undoneTable"))
ok("links, image, file and nested page kept through table edits", "link" in r["afterMarks"] and all(k in r["afterTypes"] for k in ["image", "file", "pageCard"]), r)
st, tb = table_block(); before_t = content(note["id"])
m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Conflicting", edits=[
    {"action": "table_set_cell", "block_id": tb["id"], "target": tb["rows"][1]["cells"][1]["id"], "text": "9"},
    {"action": "table_delete_row", "block_id": tb["id"], "target": tb["rows"][1]["id"]},
    {"action": "table_move_row", "block_id": tb["id"], "target": tb["rows"][1]["id"], "value": tb["rows"][0]["id"]}])
r = review("accept"); ok("table proposal all or nothing", r["status"] == "failed" and content(note["id"]) == before_t, r)
m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Stale cell", edits=[
    {"action": "table_set_cell", "block_id": tb["id"], "target": tb["rows"][1]["cells"][0]["id"], "text": "x", "expected_text": "Carrots"}])
r = review("accept"); ok("changed cell refused", r["status"] == "failed" and "changed" in r["result"], r)
newbie = MCP("newcomer"); r = newbie.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Delete row", edits=[
    {"action": "table_delete_row", "block_id": tb["id"], "target": tb["rows"][1]["id"]}]); newbie.close()
ok("deleting a table row needs Destructive", "error" in r and "destructive" in r["error"], r)
m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Bed numbers", edits=[
    {"action": "table_set_cell", "block_id": tb["id"], "target": tb["rows"][1]["cells"][1]["id"], "text": "7", "expected_text": "3"}])
r = review("accept"); ok("table cell saved", r["status"] == "accepted" and r["afterTable"] == "Crop|Bed / Beans|7", r.get("afterTable"))
table_note = note["id"]

# Collections: items (pages), fields, views; preview; one Undo; all or nothing; permission; persistence.
books = next(d for d in m.tool("draft_list_documents") if d["title"] == "Reading list")
def collection():
    st = m.tool("draft_read_structure", document_id=books["id"]); b = next(x for x in st["blocks"] if x["type"] == "collection")
    return st, b, m.tool("draft_read_collection", document_id=books["id"], block_id=b["id"])
st, cb, col = collection()
ok("read collection", [i["title"] for i in col["items"]] == ["Atlas", "Zen", "Ulysses"] and {f["name"] for f in col["fields"]} >= {"Status", "Date", "Tags"} and {v["type"] for v in col["views"]} == {"table", "gallery", "kanban"}, col)
items = {i["title"]: i["id"] for i in col["items"]}; table_view = next(v["id"] for v in col["views"] if v["type"] == "table")
ids_before = sorted(items.values())
p = m.tool("draft_propose_note_edits", document_id=books["id"], expected_revision=st["revision"], instruction="Organise the books", edits=[
    {"action": "collection_add_field", "block_id": cb["id"], "text": "Pages", "value": "number"},
    {"action": "collection_add_item", "block_id": cb["id"], "text": "Dune", "value": '{"Status": "Doing", "Pages": 412}'},
    {"action": "collection_update_item", "block_id": cb["id"], "target": items["Atlas"], "value": '{"Pages": "120", "Status": "Done"}'},
    {"action": "collection_move_item", "block_id": cb["id"], "target": items["Ulysses"], "value": items["Atlas"], "position": "before"},
    {"action": "collection_set_view", "block_id": cb["id"], "target": table_view, "value": '{"sort": [{"field": "Pages", "ascending": false}], "filters": [{"field": "Status", "op": "isNot", "value": "To do"}]}'}])
ok("collection proposal queued", p.get("status") == "pending", p)
r = review("accept", undo=True, shot="mcp-review-collection")
ok("collection changes applied", r["status"] == "accepted" and r["afterCollection"].startswith("Ulysses|Done") and "Dune|Doing|||412" in r["afterCollection"] and "Atlas|Done|||120" in r["afterCollection"] and "Table:table:1s1f" in r["afterCollection"], r.get("afterCollection"))
ok("collection proposal is one Undo (item page gone too)", r["undoneCollection"].startswith("Atlas|To do") and "Dune" not in r["undoneCollection"] and "Pages" not in r["undoneCollection"] and int(r["undoneTrashed"]) == int(r["afterTrashed"]) + 1, r)
st, cb, col = collection()
before_c = m.tool("draft_read_collection", document_id=books["id"], block_id=cb["id"])
m.tool("draft_propose_note_edits", document_id=books["id"], expected_revision=st["revision"], instruction="One bad value", edits=[
    {"action": "collection_add_item", "block_id": cb["id"], "text": "Kafka"},
    {"action": "collection_update_item", "block_id": cb["id"], "target": items["Zen"], "value": '{"Status": "Someday"}'}])
r = review("accept")
ok("collection all or nothing (no page created)", r["status"] == "failed" and "option" in r["result"] and m.tool("draft_read_collection", document_id=books["id"], block_id=cb["id"]) == before_c and not any(d["title"] == "Kafka" for d in m.tool("draft_list_documents")), r)
m.tool("draft_propose_note_edits", document_id=books["id"], expected_revision=st["revision"], instruction="Rejected", edits=[{"action": "collection_add_item", "block_id": cb["id"], "text": "Rejected book"}])
r = review("reject"); ok("rejected collection proposal changes nothing", r["status"] == "rejected" and m.tool("draft_read_collection", document_id=books["id"], block_id=cb["id"]) == before_c, r)
newbie = MCP("newcomer"); r = newbie.tool("draft_propose_note_edits", document_id=books["id"], expected_revision=st["revision"], instruction="Delete", edits=[
    {"action": "collection_delete_item", "block_id": cb["id"], "target": items["Zen"]}]); newbie.close()
ok("deleting an item needs Destructive", "error" in r and "destructive" in r["error"], r)
m.tool("draft_propose_note_edits", document_id=books["id"], expected_revision=st["revision"], instruction="Done with Zen", edits=[{"action": "collection_delete_item", "block_id": cb["id"], "target": items["Zen"]}])
m.tool("draft_propose_note_edits", document_id=books["id"], expected_revision=st["revision"], instruction="Same revision", edits=[{"action": "collection_add_item", "block_id": cb["id"], "text": "Late"}])
r = review("accept", undo=True)
ok("deleted item's page goes to Recently Deleted; Undo restores", r["status"] == "accepted" and "Zen" not in r["afterCollection"] and "Zen" in r["undoneCollection"] and int(r["afterTrashed"]) == int(r["undoneTrashed"]) + 1, r)
r = review("accept"); ok("collection proposal stale after another change", r["status"] == "stale", r)
st, cb, col = collection()
m.tool("draft_propose_note_edits", document_id=books["id"], expected_revision=st["revision"], instruction="Keep", edits=[{"action": "collection_add_item", "block_id": cb["id"], "text": "Middlemarch", "value": '{"Status": "To do", "Date": "2026-12-01"}'}])
r = review("accept"); ok("item added and kept", r["status"] == "accepted" and "Middlemarch|To do|2026-12-01" in r["afterCollection"], r.get("afterCollection"))
p_first = next(b for b in m.tool("draft_read_structure", document_id=books["id"])["blocks"] if b["type"] == "paragraph")
m.tool("draft_propose_note_edits", document_id=books["id"], expected_revision=m.tool("draft_read_structure", document_id=books["id"])["revision"], instruction="Another list", edits=[
    {"action": "collection_create", "block_id": p_first["id"], "text": "Films", "position": "after"}])
r = review("accept"); ok("new collection created in the note", r["status"] == "accepted" and r["afterTypes"].count("collection") == 2, r.get("afterTypes"))
books_ids = sorted(i["id"] for i in m.tool("draft_read_collection", document_id=books["id"], block_id=cb["id"])["items"])

# Images and files: checked when proposed and at Apply, copied only on Apply, one Undo removes them.
import struct, zlib
def png(path, w=64, h=40):
    raw = b"".join(b"\x00" + bytes((x * 4 + w) % 256 for x in range(w * 3)) for _ in range(h))
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    open(path, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0)) + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))
files = work + "/files"; os.makedirs(files, exist_ok=True)
png(files + "/garden-plan.png"); open(files + "/seeds.pdf", "wb").write(b"%PDF-1.4\n% sample\n" + b"x" * 2000)
open(files + "/run.sh", "w").write("echo hi"); open(files + "/huge.png", "wb").truncate(26 * 1024 * 1024)
def assets(): return len(os.listdir(vault + "/assets")) if os.path.isdir(vault + "/assets") else 0
st = m.tool("draft_read_structure", document_id=note["id"]); anchor = next(b for b in st["blocks"] if b["type"] == "paragraph" and b["text"])
def propose_asset(action, path, text="", client=None, rev=None):
    t = (client or m).tool("draft_propose_note_edits", document_id=note["id"], expected_revision=rev or m.tool("draft_read_structure", document_id=note["id"])["revision"], instruction=f"Add {os.path.basename(path)}",
        edits=[{"action": action, "block_id": anchor["id"], "value": path, "text": text, "position": "after"}])
    return t
ok("unsupported type refused", "error" in propose_asset("insert_file", files + "/run.sh"))
ok("oversized image refused", "MB" in propose_asset("insert_image", files + "/huge.png").get("error", ""))
ok("missing file refused", "no file" in propose_asset("insert_image", files + "/nope.png").get("error", ""))
blocked = MCP("blocked"); ok("client without permission refused", "error" in propose_asset("insert_image", files + "/garden-plan.png", client=blocked)); blocked.close()
a0 = assets()
p = propose_asset("insert_image", files + "/garden-plan.png", "Bed plan for spring")
ok("image proposal queued, nothing copied", p.get("status") == "pending" and assets() == a0, p)
r = review("later"); ok("Later copies nothing", assets() == a0 and r["hiddenAfterLater"] == "yes", r)
r = review("reject"); ok("Reject copies nothing", r["status"] == "rejected" and assets() == a0, r)
propose_asset("insert_image", files + "/garden-plan.png", "Bed plan for spring")
r = review("accept", undo=True, shot="mcp-review-image")
ok("image inserted and copied", r["status"] == "accepted" and int(r["afterAssets"]) == a0 + 1 and r["afterTypes"].split(",").count("image") == 2, (r["status"], r["result"], r["afterAssets"], r["afterTypes"]))
ok("one Undo removes the block and the copy", int(r.get("undoneAssets", -1)) == a0 and r["undoneTypes"].split(",").count("image") == 1, r)
propose_asset("insert_image", files + "/garden-plan.png")
png(files + "/garden-plan.png", w=65)  # the file changes after it was proposed
r = review("accept"); ok("file changed after proposal is refused, nothing copied", r["status"] == "failed" and "changed" in r["result"] and assets() == a0, r)
old_rev = m.tool("draft_read_structure", document_id=note["id"])["revision"]
m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=old_rev, instruction="first", edits=[{"action": "italic", "block_id": anchor["id"], "text": anchor["text"].split()[0]}]); propose_asset("insert_file", files + "/seeds.pdf", rev=old_rev)
r = review("accept"); r = review("accept")
ok("stale revision refused, nothing copied", r["status"] == "stale" and assets() == a0, r)
propose_asset("insert_file", files + "/seeds.pdf")
r = review("accept", shot="mcp-review-file")
ok("file inserted with its name and size", r["status"] == "accepted" and "file" in r["afterTypes"] and int(r["afterAssets"]) == a0 + 1, r)
ok("links, table, image, nested page kept", "link" in r["afterMarks"] and all(k in r["afterTypes"] for k in ["table", "image", "pageCard"]), r)
pdf_asset_block = [b for b in m.tool("draft_read_structure", document_id=note["id"])["blocks"] if b["type"] == "file" and b["attrs"].get("name") == "seeds.pdf"]
ok("structure shows the attached file", len(pdf_asset_block) == 1 and pdf_asset_block[0]["attrs"].get("size") == os.path.getsize(files + "/seeds.pdf"), pdf_asset_block)

# Folders: reviewed, full path, duplicates and bad names refused, stale, reject, one Undo.
note_before = filehash(note["id"])
r = m.tool("draft_propose_create_folder", name="Projects", instruction="A home for projects")
ok("folder proposal queued", r.get("status") == "pending" and not any(f["name"] == "Projects" for f in m.tool("draft_list_folders")), r)
r = review("accept", shot="mcp-review-folder")
projects = r.get("folderId")
ok("folder created at its path", r["status"] == "accepted" and r.get("folderPath", "").endswith("› Projects") and filehash(note["id"]) == note_before, r)
r = m.tool("draft_propose_create_folder", name="2026", parent_folder_id=projects, instruction="Year folder")
r = review("accept", undo=True)
ok("nested folder shows its path and one Undo removes it", r["status"] == "accepted" and r.get("folderPath", "").endswith("› Projects › 2026") and r.get("folderAfterUndo") == "removed", r)
ok("duplicate folder name refused", "already exists" in m.tool("draft_propose_create_folder", name="projects", instruction="dup").get("error", ""))
ok("invalid folder names refused", all("error" in m.tool("draft_propose_create_folder", name=n, instruction="bad") for n in ["a/b", "..", " "]))
ok("missing parent refused", "error" in m.tool("draft_propose_create_folder", name="X", parent_folder_id="f_missing", instruction="bad"))
m.tool("draft_propose_create_folder", name="Alpha", instruction="first"); m.tool("draft_propose_create_folder", name="Beta", instruction="second")
review("accept"); r = review("accept")
ok("second folder from the same revision is stale", r["status"] == "stale", r)
m.tool("draft_propose_create_folder", name="Rejected folder", instruction="no")
r = review("reject"); ok("rejected folder not created", r["status"] == "rejected" and not any(f["name"] == "Rejected folder" for f in m.tool("draft_list_folders")), r)

# Multi-note proposals: all or nothing, one Undo for every note.
child = next(d for d in m.tool("draft_list_documents") if d["title"] == "Seed list")
def revs(): return m.tool("draft_read_structure", document_id=note["id"]), m.tool("draft_read_structure", document_id=child["id"])
a_st, b_st = revs(); word = next(b for b in a_st["blocks"] if "zebra-quartz" in b["text"])
note_h, child_h, note_c = filehash(note["id"]), filehash(child["id"]), content(note["id"])
p = m.tool("draft_propose_multi_note_edits", instruction="Tidy both", notes=[
    {"document_id": note["id"], "expected_revision": a_st["revision"], "edits": [{"action": "bold", "block_id": word["id"], "text": "zebra-quartz"}]},
    {"document_id": child["id"], "expected_revision": b_st["revision"], "edits": [{"action": "append", "block_id": child["id"], "text": "Tomatoes and **beans**"}]}])
ok("multi-note proposal queued, notes unchanged", p.get("status") == "pending" and filehash(note["id"]) == note_h and filehash(child["id"]) == child_h, p)
r = review("accept", undo=True, shot="mcp-review-multi")
ok("multi-note applied to every note", r["status"] == "accepted" and "bold" in r[f"after:{note['id']}"] and "Tomatoes" in r[f"after:{child['id']}"], r)
ok("one Undo reverts every note", "bold" not in r[f"undone:{note['id']}"] and "Tomatoes" not in r[f"undone:{child['id']}"] and content(note["id"]) == note_c, r)
a_st, b_st = revs()
m.tool("draft_propose_multi_note_edits", instruction="Second part fails", notes=[
    {"document_id": note["id"], "expected_revision": a_st["revision"], "edits": [{"action": "bold", "block_id": word["id"], "text": "zebra-quartz"}]},
    {"document_id": child["id"], "expected_revision": b_st["revision"], "edits": [{"action": "bold", "block_id": b_st["blocks"][0]["id"], "text": "not in this note"}]}])
note_c = content(note["id"]); r = review("accept")
ok("all or nothing: a failing note leaves every note unchanged", r["status"] == "failed" and "None of the notes" in r["result"] and content(note["id"]) == note_c and "bold" not in r[f"after:{note['id']}"], r)
a_st, b_st = revs()
m.tool("draft_propose_note_edits", document_id=child["id"], expected_revision=b_st["revision"], instruction="Change first", edits=[{"action": "append", "block_id": child["id"], "text": "Peas"}])
m.tool("draft_propose_multi_note_edits", instruction="Stale", notes=[
    {"document_id": note["id"], "expected_revision": a_st["revision"], "edits": [{"action": "italic", "block_id": word["id"], "text": "zebra-quartz"}]},
    {"document_id": child["id"], "expected_revision": b_st["revision"], "edits": [{"action": "append", "block_id": child["id"], "text": "Late"}]}])
review("accept"); note_c = content(note["id"]); r = review("accept")
ok("multi-note stale if any note changed; nothing applied", r["status"] == "stale" and content(note["id"]) == note_c and "Late" not in r[f"after:{child['id']}"], r)
a_st, b_st = revs()
newbie = MCP("newcomer")
r = newbie.tool("draft_propose_multi_note_edits", instruction="Delete", notes=[
    {"document_id": note["id"], "expected_revision": a_st["revision"], "edits": [{"action": "delete_block", "block_id": word["id"]}]},
    {"document_id": child["id"], "expected_revision": b_st["revision"], "edits": [{"action": "append", "block_id": child["id"], "text": "x"}]}]); newbie.close()
ok("multi-note with a delete needs Destructive", "error" in r and "destructive" in r["error"], r)

# Delete whole notes: to Recently Deleted with nested pages, one Undo restores, needs Destructive.
st = m.tool("draft_read_structure", document_id=note["id"]); before_delete = content(note["id"])
newbie = MCP("newcomer"); r = newbie.tool("draft_propose_delete_document", document_id=note["id"], expected_revision=st["revision"], instruction="Delete"); newbie.close()
ok("delete needs the Destructive permission", "error" in r and "destructive" in r["error"], r)
m.tool("draft_propose_delete_document", document_id=note["id"], expected_revision=st["revision"], instruction="Clean up")
r = review("reject"); ok("rejected delete keeps the note", r["status"] == "rejected" and r["afterDeleted"] == "no", r)
trashed_before = None
m.tool("draft_propose_delete_document", document_id=note["id"], expected_revision=st["revision"], instruction="Clean up")
r = review("accept", undo=True, shot="mcp-review-delete")
ok("delete moves note and nested page to Recently Deleted", r["status"] == "accepted" and r["afterDeleted"] == "yes" and int(r["afterTrashed"]) >= 2 and "Recently Deleted" in r["result"], r)
ok("one Undo restores note and nested page", r["undoneDeleted"] == "no" and int(r["undoneTrashed"]) == int(r["afterTrashed"]) - 2 and content(note["id"]) == before_delete, r)
r = m.tool("draft_propose_delete_document", document_id=note["id"], expected_revision="0" * 64, instruction="Old")
ok("stale delete refused", "error" in r and "changed" in r["error"], r)

# Permissions: per client, checked by the server and again when applying.
blocked = MCP("blocked"); r = blocked.tool("draft_list_documents"); blocked.close()
ok("client without read permission refused", "error" in r and "Settings › Agents" in r["error"], r)
newcomer = MCP("newcomer"); st = newcomer.tool("draft_read_structure", document_id=note["id"])
plain = next(b for b in st["blocks"] if b["type"] == "paragraph" and b["text"])
r = newcomer.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Delete", edits=[{"action": "delete_block", "block_id": plain["id"]}])
ok("new client can't propose destructive changes", "error" in r and "destructive" in r["error"], r)
r = newcomer.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Italic", edits=[{"action": "italic", "block_id": plain["id"], "text": plain["text"].split()[0]}])
ok("new client can propose ordinary edits", r.get("status") == "pending", r); newcomer.close()
r = review("reject"); ok("proposal records its client", r.get("client") == "newcomer", r)
st = m.tool("draft_read_structure", document_id=note["id"]); plain = next(b for b in st["blocks"] if b["type"] == "paragraph" and b["text"]); before = filehash(note["id"])
m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Delete", edits=[{"action": "delete_block", "block_id": plain["id"]}])
r = review("accept", revoke=True, shot="mcp-review-destructive")
ok("permission revoked before Apply: not applied", r["status"] == "failed" and "allowed" in r["result"] and filehash(note["id"]) == before, r)
m.tool("draft_propose_note_edits", document_id=note["id"], expected_revision=st["revision"], instruction="Later", edits=[{"action": "italic", "block_id": plain["id"], "text": plain["text"].split()[0]}])
r = review("later")
ok("Later keeps it pending and out of the way", r["hiddenAfterLater"] == "yes" and r["notReshownByWatcher"] == "yes" and r["reshownOnRequest"] == "yes" and m.tool("draft_request_status", request_id=json.load(open(work + "/agent-review.json"))["requestId"])["status"] == "pending", r)
r = review("reject")
log = open(vault + "/agent-requests/activity.jsonl").read()
ok("activity log has tools and no note text", "draft_read_structure" in log and "zebra" not in log and "Planning" not in log, log[:200])

# Persistence across relaunch and an index rebuild from the files.
m.close()
shutil.rmtree(vault + "/index", ignore_errors=True)
pending = [f for f in os.listdir(vault + "/agent-requests") if f.startswith("request_") and json.load(open(vault + "/agent-requests/" + f))["status"] == "pending"]
ok("no proposal left pending", not pending, pending)
r = review("accept")  # a plain relaunch: nothing should be left to review
ok("relaunch with nothing pending", r.get("error") == "no pending proposal", r)
m = MCP()
ok("relaunch keeps created, renamed and moved notes", any(d["title"] == "Trip plan" for d in m.tool("draft_list_documents", space_id=work_space["id"])))
ok("table change persists after relaunch", next(b for b in m.tool("draft_read_structure", document_id=table_note)["blocks"] if b["type"] == "table")["rows"][1]["cells"][1]["text"] == "7")
ok("collection items and ids persist after relaunch", sorted(i["id"] for i in m.tool("draft_read_collection", document_id=books["id"], block_id=cb["id"])["items"]) == books_ids and set(ids_before) <= set(books_ids))
ok("attached file persists after relaunch", any(b["type"] == "file" and b["attrs"].get("name") == "seeds.pdf" for b in m.tool("draft_read_structure", document_id=note["id"])["blocks"]))
ok("index rebuilt from files finds new text", any(h["document_id"] == new for h in m.tool("draft_search", query="station", space_id=work_space["id"])))
m.close()
failed = [k for k, v in checks.items() if not v]
print(f"\n{len(checks) - len(failed)}/{len(checks)} checks passed; screens in {work}")
print("MCP TEST " + ("PASSED" if not failed else "FAILED: " + ", ".join(failed)))
sys.exit(1 if failed else 0)
PY
