# Draft AI integration handoff

## Status on 8 November 2026 (v0.7 MCP operations)

- Merged into `main`. Codex runs `~/Documents/Draft/scripts/draft-mcp.sh`; Claude Code has the same
  server registered for this project (`~/.claude.json`, project `/Users/danielpekarek/Documents/Draft`,
  server `draft`) and its CLI reports it connected.
- DraftMCP 0.2.0 tools (14): `draft_list_spaces`, `draft_list_documents`, `draft_list_folders`,
  `draft_search`, `draft_read_document`, `draft_read_structure`, `draft_read_block`,
  `draft_document_revision`, `draft_formatting_guide`, `draft_propose_note_edits`,
  `draft_propose_create_document`, `draft_propose_rename_document`, `draft_propose_move_document`,
  `draft_request_status`.
- Every change is a reviewed proposal: the server only writes `agent-requests/`. Draft applies it
  after the user clicks Apply, rechecks the revision, saves with a backup, updates the index and makes
  it one Undo step (note edits in the note's undo; create/rename/move in Edit › Undo Agent Change and
  the toast). Reject, stale and refused edits leave everything unchanged.
- Checks: `scripts/mcp-test.sh` (39 checks over real stdio in a throwaway vault),
  `scripts/agent-test.sh`, unit tests (`AgentBlockOpsTests`, `AgentLibraryProposalTests`).
- Not yet: folder creation, deleting whole notes, multi-note proposals, tables and collections,
  inserting images or files (existing ones are always kept), and a genuine Codex app-server mode.

The original handoff follows.


This branch adds an optional OpenAI API provider to Draft's existing Assistant and a local MCP bridge through which Codex can read notes and propose changes. It was built from `main` while the v0.6 UI polish branch had uncommitted changes. Merge the polish work first, then resolve UI conflicts against this branch. The user's vault and the existing polish checkout were not edited.

## Implemented

- Assistant provider selector: local model remains the default; OpenAI is optional.
- API key stored in the macOS Keychain, never in `library.json` or the vault. Model ID is editable, initially `gpt-6.1-sol`.
- OpenAI Responses API streaming with `store: false`; the user reviews the exact selected context and prior turns before each request. Selection, Document and Space retrieval, source cards, Stop, and Insert/Replace preview reuse the existing flow. Local and cloud histories are separate per Space.
- A `DraftMCP` stdio executable exposes `draft_list_spaces`, `draft_list_documents`, `draft_search`, `draft_read_document`, `draft_read_block`, and `draft_read_structure`. It reads current-schema vault files directly without migration or writes. Trashed documents and templates are excluded.
- Codex can call `draft_propose_note_edits` with the revision returned by `draft_read_structure`. A proposal may replace an entire text note with Markdown or target blocks for text, headings, quote/callout/code blocks, lists, per-block font and color, alignment, focus/block decoration, bold, italic, underline, strike, inline code, text color and highlight. It can insert or restyle Draft's line, strong, dotted, three-dot, wave and tape separators and page breaks. A standalone proposal can apply a built-in or saved document style. `draft_formatting_guide` gives the agent available built-in styles, effects and restrained design rules; it should read this before a general "make this note look better" request. `draft_request_status` reports whether Draft accepted the proposal. A pending proposal only writes `agent-requests/<id>.json`, never a document. Draft presents a review sheet; accepting rechecks the revision and applies through the AppKit editor with one Undo step. It preserves IDs for targeted edits and reuses IDs where possible in whole-note replacement. Links, images and other attachments in an existing note are protected: whole-note replacement refuses notes with attachment blocks; Codex must use targeted edits there. A save failure is reported as failed, never accepted. Markdown export cannot carry separator appearance; Draft's lossless JSON and styled exports can.
- The external process never writes note JSON directly. Draft's running app performs every accepted edit, saves backups and updates the index. If the app is closed, the proposal waits until it opens.

## Setup after merge

Build with `swift build --product DraftMCP`. Run `scripts/draft-mcp.sh` as a local stdio MCP server. The script writes build output only to stderr. A Codex configuration can point its command to the absolute path of this script. No global Codex config was modified by this branch. The app must be running for the review sheet to appear, though Codex can queue a proposal while it is closed.

The OpenAI option currently uses a user-supplied API key and the Responses API. It does **not** use the user's ChatGPT subscription or scrape Codex credentials. Sign in with ChatGPT for open-source apps and a Codex app-server driver are separate future work; re-check eligibility and current official docs before implementing them. Do not present this branch as a full Codex agent inside Draft.

## Checks and remaining work for Claude

Unit tests cover provider-separated histories, old-settings defaults, SSE parsing, request privacy fields, read-only vault access, trash filtering, proposal validation, block edits, whole-note replacement and undo. An app automation run in a throwaway vault accepted a queued proposal, saved the change, kept block IDs and undid it in one step. A separate stdio MCP probe read the structure, queued a proposal and confirmed the document bytes were unchanged until acceptance; the app then accepted that external proposal. A real OpenAI request was not made; it requires a user-owned key and explicit opt-in. The cloud panel and proposal review need visual review and polish after the v0.6 branch is merged.

Next steps:

1. Merge against the finished v0.6 UI work. Reconcile the Assistant, Settings, design-system and model changes rather than overwriting either branch.
2. Test the cloud mode with a throwaway vault and a real user-supplied key, including streaming, cancellation, error states, source cards, preview and undo. Check light/dark and narrow/floating layouts.
3. Polish the proposed edit review: show a clear before/after diff for every block operation, handle long whole-note replacements gracefully, and make the accepted change visible in the editor. Keep approval explicit.
4. Expand the same app-mediated proposal system to create notes, rename, move, append/insert/delete/reorder blocks, set document styles and manage links, tags and tasks. Use the same stale-revision check, review and one-step undo. Never write vault JSON directly from MCP. Add targeted tests for links, assets, nested pages and multi-document changes.
5. Add a genuine Codex app-server mode only after implementing a supported authentication flow, streaming protocol, cancellation, and explicit approval handling. Keep it distinct from OpenAI API chat in the UI.
6. Update roadmap, parity and privacy copy to describe the optional network path precisely. Keep the repo private until the user chooses otherwise.

Current reference docs: [Responses streaming](https://developers.openai.com/api/docs/guides/streaming-responses), [Codex app-server](https://developers.openai.com/siwc/token-sharing-open-source/codex-app-server), [Sign in with ChatGPT for open-source apps](https://developers.openai.com/siwc/quickstart).
