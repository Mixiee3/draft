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
    def tool(self, name, **args):
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

m = MCP()
tools = [t["name"] for t in m.rpc("tools/list", {})["result"]["tools"]]
print("tools:", ", ".join(tools))
ok("tools listed", len(tools) == 14, tools)
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
ok("index rebuilt from files finds new text", any(h["document_id"] == new for h in m.tool("draft_search", query="station", space_id=work_space["id"])))
m.close()
failed = [k for k, v in checks.items() if not v]
print(f"\n{len(checks) - len(failed)}/{len(checks)} checks passed; screens in {work}")
print("MCP TEST " + ("PASSED" if not failed else "FAILED: " + ", ".join(failed)))
sys.exit(1 if failed else 0)
PY
