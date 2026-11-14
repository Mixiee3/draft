# Draft AI integration handoff

## v0.10 groundwork (13 November 2026)

Nothing changed in the MCP tools or the proposal flow. New for agents to know: Settings › Privacy lists
MCP agents with their permissions; Report a Problem never includes note text, so agent bug reports
should quote the request id from Settings › Agents. `scripts/release-check.sh` runs `mcp-test` and
`agent-test` as release gates.

## Item 17: Codex app-server mode — research and architecture (12 November 2026)

**Status: blocked on eligibility, not implemented.** OpenAI documents both pieces now:

- *App-server* ([learn.chatgpt.com/docs/app-server](https://learn.chatgpt.com/docs/app-server)): JSON-RPC 2.0 over stdio
  (newline-delimited), `initialize` → `initialized` → `thread/start` / `thread/resume` → `turn/start`;
  progress as `item/started`, `item/agentMessage/delta`, `item/completed`, `turn/completed`;
  `turn/interrupt` cancels; the server asks the client for permissions (`item/permissions/requestApproval`).
  OpenAI asks new enterprise integrations to contact it to join a known-clients list.
- *Sign in with ChatGPT for open-source apps* ([developers.openai.com/siwc](https://developers.openai.com/siwc/quickstart)):
  authorize at `auth.openai.com` in the system browser with PKCE and a loopback redirect
  (`http://127.0.0.1:<port>/auth/callback`); the first sign-in uses `client_id=dynamic_agent_client` and
  returns an issued `oaiapp_…` client id; scopes `openid profile email offline_access resource.invoke
  chatgpt.tokens.use.direct`; the access token is handed to `codex app-server` as an environment variable
  (`ACCESS_TOKEN`, provider `openai_chatgpt_plan`, `wire_api = responses`). Plan usage is “available to all
  open-source partners and selected private clients”; commercial sign-in is a limited trial.

Draft is a private repository, so it is neither an open-source partner nor a selected client. Using the
open-source registration for it would misrepresent the app, so Draft does not do it.

**Architecture when eligible** (kept separate from the local model, the OpenAI API provider and MCP):

1. Settings › Assistant gains a third provider, “Codex (ChatGPT plan)”, off by default and labelled as
   sending notes to OpenAI.
2. Sign-in: a loopback listener on `127.0.0.1` (random port, fixed path), PKCE + state + nonce, system
   browser; tokens and the issued client id in the Keychain (never in the vault, never logged); refresh
   rotates the access and refresh token together.
3. A `CodexSession` actor starts `codex app-server --listen stdio://` as a child process with the token in its
   environment only, speaks JSON-RPC, streams deltas into the Assistant panel, maps `turn/interrupt` to
   Stop, and turns every server approval request into Draft's own review sheet (deny by default).
4. Note edits still go only through Draft's reviewed proposals (the MCP bridge), never from the child process.
5. Checks: sign-in cancelled, token expired and refreshed, child process crash, cancel < 500 ms, no
   credentials in vault files or logs (a test greps the vault).

## Effect colors (12 November 2026)

- `text_effect` values may carry the effect's own colors: `glow?color=#ff4fd8&intensity=0.7`,
  `outline?color=#3a5bd9`, `gradient?stops=#3a5bd9,#8b5cf6,#d6336c&angle=30`. The text color stays
  `text_color`. Fill colors are kept readable by Draft; malformed values are refused by the server.

## Item 16: long proposals (11 November 2026)

- The review sheet keeps a summary visible (changes, notes, removals, kinds) and groups changes by
  note (or block) or by kind in collapsible sections; long groups show 10 cards with “Show N more”.
  Removals are marked. Every change is still applied together, with one Undo; there is no per-card
  skip yet, so propose separate requests when parts should be decided separately.

## Item 15: richer agent actions (11 November 2026)

- 21 tools. New proposal tools: `draft_propose_rename_folder`, `draft_propose_create_style`,
  `draft_propose_daily_append`. New note-edit actions: `link_note` (value = another note's id; text =
  the phrase), `add_tag` / `remove_tag` (value = `#tag`), `task_due` (YYYY-MM-DD or none),
  `image_caption` / `image_alt` (text), and `text_effect` `spectrum:<palette>:<speed>:<direction>`.
- All go through the same review sheet (plain-language cards with before and after), stale-revision
  check, backup, index update, Reject / Later and one-step Undo. Link targets are checked by the
  server and again in Draft at Apply.
- To give several notes a saved style, use `document_style` with its `u_…` id in
  `draft_propose_multi_note_edits` (all or nothing).

## Styling through MCP (11 November 2026)

- 12 November: `draft_formatting_guide` also returns `effect_presets` (name, group, `text_effect_value`
  ready to pass to a `text_effect` action, including gradient stop positions, radial focus and Spectrum
  palette/speed/direction) and `block_presets` (decoration and tint). Agents should prefer a preset over
  inventing colors.

- `draft_formatting_guide` now returns `text_effects` and `block_effects` (value, name, where it
  fits) next to `background_styles`, plus restraint rules: at most one text effect per section, at
  most two block effects per note, never a highlight and an effect on the same words.
- New note-edit actions, all reviewed and undone in one step: `text_effect` on an exact phrase
  (`accent`, `gradient`, `glow`, `shadow`, `outline`, `lift`, `emboss`, or `none`); `decoration` now
  also takes `gradient`, `glass`, `glow`, `accent`; `document_backdrop` (standalone, `block_id` =
  document id) takes a JSON gradient — 2–8 `#RRGGBB` stops, positions/opacity/focus 0…1, angle
  0…360 — and is refused when its colours jump more than 4.5:1. It can never point at an image.
- The review sheet shows the note's look before and after for `document_style` and
  `document_backdrop`. Saved styles apply with `document_style` and their `u_…` id.
- Effect colours come from the note's style and are always readable (≥ 4.5:1), so an agent can't
  pick an unreadable effect colour; it can only pick the kind.

## Status on 8 November 2026 (v0.7 MCP operations)

- Merged into `main`. Codex runs `~/Documents/Draft/scripts/draft-mcp.sh`; Claude Code has the same
  server registered for this project (`~/.claude.json`, project `<your-checkout>`,
  server `draft`) and its CLI reports it connected.
- DraftMCP tools (21 now; 14 at the time of this paragraph): `draft_list_spaces`, `draft_list_documents`, `draft_list_folders`,
  `draft_search`, `draft_read_document`, `draft_read_structure`, `draft_read_block`,
  `draft_document_revision`, `draft_formatting_guide`, `draft_propose_note_edits`,
  `draft_propose_create_document`, `draft_propose_rename_document`, `draft_propose_move_document`,
  `draft_request_status`.
- Every change is a reviewed proposal: the server only writes `agent-requests/`. Draft applies it
  after the user clicks Apply, rechecks the revision, saves with a backup, updates the index and makes
  it one Undo step (note edits in the note's undo; create/rename/move in Edit › Undo Agent Change and
  the toast). Reject, stale and refused edits leave everything unchanged.
- Claude Code was restarted after registration and lists all 14 tools. They point at the personal
  vault, so all testing uses `--vault` throwaway vaults.
- Review sheet validated with `scripts/review-gallery.sh`: light, dark and narrow captures in
  `docs/screenshots/v07/`; Return applies (one Undo reverses it) and Escape rejects, as real key
  events. Format-only cards now show the block under a neutral label and inline formats preview
  the result. Tab focus with Keyboard Navigation and VoiceOver still need a person.
- Checks: `scripts/mcp-test.sh` (50 checks over real stdio in a throwaway vault),
  `scripts/agent-test.sh`, unit tests (`AgentBlockOpsTests`, `AgentLibraryProposalTests`).
- Manual review-sheet check by the user: focus ring, VoiceOver, Return, Escape and one-step Undo
  pass; Tab navigation not tested yet.
- Permissions (v0.7 row 8, done): Settings › Agents has per-client Read / Propose / Destructive
  switches keyed by the MCP `clientInfo.name`; new clients read and propose, destructive is off until
  allowed (Codex and Claude Code included — allow it there to delete blocks, replace whole notes or
  move notes). The server refuses without permission and Draft rechecks when applying. Proposals
  record their client; the sheet shows it with the permission needed, affected notes, and
  Reject / Later / Apply. `agent-requests/activity.jsonl` logs tool, note id and time only.
- Rows 9–11 done: `draft_propose_create_folder` (full path in the review, duplicates and bad names
  refused), `draft_propose_delete_document` (to Recently Deleted with nested pages; Destructive
  permission), `draft_propose_multi_note_edits` (2–20 notes, all-or-nothing, one Undo). 17 tools;
  `scripts/mcp-test.sh` 69 checks.
- Row 12 done: table edits through `draft_propose_note_edits` (cells, rows, columns by id; preview
  grids in the review; Destructive for deletes). `scripts/mcp-test.sh` 78 checks.
- Row 13 done: collections through `draft_read_collection` and collection actions in
  `draft_propose_note_edits` (items as pages, fields, views; one Undo; Destructive for deletes).
  18 tools; `scripts/mcp-test.sh` 90 checks. Tab navigation fix: `scripts/nav-test.sh`.
- Row 14 done: `insert_image` / `insert_file` with a local path; checked on proposal and at Apply
  (type, size, fingerprint), copied only on Apply, one Undo removes block and copy.
  `scripts/mcp-test.sh` 105 checks.
- Styling: 24 procedural background presets listed in `draft_formatting_guide` as
  `background_styles`, applied through `document_style` proposals.
- Next (see ROADMAP v0.7 rows 15–17, in order): inserting images and files,
  richer actions, review-sheet polish, and a Codex app-server mode only after supported sign-in.
- Earlier plan line kept for reference: folder creation, deleting whole
  notes to Recently Deleted, multi-note proposals, tables, collections, inserting images and files,
  richer actions, review-sheet polish, and a Codex app-server mode only after supported sign-in.

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
