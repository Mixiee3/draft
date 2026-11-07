# Draft roadmap

Draft is a free, open-source, local-first notes and document app. **The first release line is
macOS only**, built natively: SwiftUI for the app shell, AppKit/TextKit 1 for the editor. Documents
use a portable, documented format ([`FORMAT.md`](FORMAT.md)) so a separate Windows app can follow
without blocking the Mac release.

This roadmap turns the gaps in [`FEATURE_PARITY.md`](FEATURE_PARITY.md) into versioned releases.
It is a working plan and changes when implementation reveals constraints.

**Ordering principle.** A complete, trustworthy *personal writing* workflow (write → structure →
style → find → export → recover) comes before anything that needs a server or other people.

**Promises every version keeps.** No account, paid service or network is needed to write, find,
export or recover notes. Every stored entity has a stable id; every schema change has an explicit
migration that backs up first; unknown fields and block types are preserved.

Legend: ✅ done · 🟡 partial · ⬜ not started

### Change log of this plan

- **2026‑11‑07** — Architecture change (not a scope reset): the Electron prototype was replaced by a
  native macOS app. Kept: data model, layer separation, styles, migrations design, export rules,
  seed copy. Added: Windows as a separate later track (below). TextKit 1 chosen over TextKit 2 for
  mature custom drawing (`NSLayoutManager`) and attachment cells; revisit when list/marker drawing
  APIs in TextKit 2 cover our needs.

---

## v0.1 — "First light" (macOS) ✅

**Theme.** A runnable native vertical slice proving the architecture.

**User-visible capabilities**
- ✅ Native window: full-height rail, top tab strip, All Docs home; tabs persist across restarts.
- ✅ New document in one action (⌘N); typing starts in the title; content persists across quit/relaunch (smoke test).
- ✅ Blocks: paragraph, Title/Subtitle/Heading/Strong/Caption, quote, code, bullets, numbers, checklist
  (nested), separators, links, images (vault assets, paste or pick), nested pages as cards/pages.
- ✅ Markdown triggers (`#`…`####`, `-`, `*`, `1.`, `[]`, `[x]`, `>`, ```` ``` ````, `---`, `**b**`,
  `*i*`, `~~s~~`, `==h==`, `` `c` ``) — undo restores literal text.
- ✅ Floating selection toolbar with in-place color palette and link field; flip/clamp; Esc; ⌥F10.
- ✅ `Aa` Format panel; Style panel (backdrop solid/gradient/scenic/upload, blur, immersive/faded,
  page and text color with contrast warning, cover, separators, fonts); Style Gallery; 7 original styles.
- ✅ Document rail: Outline, Tasks, Attachments, Find & Replace.
- ✅ Library: gallery / grid / list, search titles + text, sort name/updated/created/viewed, folders,
  Unsorted, Starred, Quick Open (⌘O).
- ✅ Export: Markdown + assets + lossless `draft-export.json`; copy Markdown; print (→ PDF via dialog).
- ✅ Light/dark/system, accent, document-tinted shell, reduce motion; narrow-window layout.

**Architecture landed.** `DraftCore` (format/vault/migrations/export), `DraftEditor` (TextKit block
editor, command registry), `Draft` (SwiftUI shell). 34 tests + end-to-end smoke test.

**Migration / data risks.** Schema 1 is the first public format. The flat (TextKit) ↔ tree (file)
conversion is lossless for everything Draft produces (tested on seed docs + nested lists/quotes/code/
unknown nodes); exotic structures from other tools (e.g. a list inside a quote) are flattened.

**Release gate (met).** `swift test` green; `scripts/smoke.sh` passes; screenshots reviewed against
references for toolbar, canvas, and library layouts.

**Out of scope (why).** Drag-reorder and block selection (needs gutter/handle design — v0.2);
tables/collections (schema work — v0.5); tags/backlinks/daily notes (need an index — v0.3); sync,
sharing, publishing (need a proven local format — v1.x/v2.0); signing/notarization (v1.0).

---

## v0.2 — "Writer's desk" (macOS) ✅ requested scope done

**Theme.** Single-document writing that feels finished and safe.

- ✅ Block gutter handle, drag reorder with insertion line and autoscroll, block selection (Esc,
  ↑/↓, ⇧↑/↓), delete blocks, Move up/down/top/bottom (⌥⌘↑/↓, ⌃⌥⌘↑/↓). One undo per operation.
- ✅ Paste: multi-line text → one block per line with Markdown recognized; RTF/HTML → headings,
  lists and marks; Draft → Draft keeps blocks and marks; surrounding block keeps its id.
- ✅ Recently Deleted for documents *and* nested pages: Undo toast, Restore, Delete Permanently,
  Empty, 30-day purge.
- ✅ Automatic local backups (≤ 1 per 10 min while editing, 30 kept) with View Backups → Restore.
- ✅ Space Search: one result per doc, match count, highlighted snippet, opens the doc on the first
  match (Find in Page pre-filled).
- ✅ Layout: text scrolls only below the document controls; the slash menu flips/shrinks to stay in
  the window (checked at 1440×900 and 720×640).

**Data/format.** `DocMeta.deletedAt` (optional, schema 1 compatible); `history/<docId>/<ms>.json`
backups; `searchText` keeps original case (derived, rebuilt on save).
**Release gate.** Met: undo covers move/delete/paste; deleting and restoring a nested page keeps
child ids; 56 tests + smoke test (restart, trash, backups, search jump). **Not yet measured:**
10,000-block keystroke latency — moved to v0.2.1 with the remaining items.

## v0.2.1 — "Writer's desk, continued" (macOS) ✅ shipped

- ✅ Block context menu (turn into, duplicate ⌘D, copy link, group, move, delete) on the handle and in
  the text's context menu; `draft://` block links open the doc at the block.
- ✅ Group selected blocks into a nested page (⌘G) / ungroup (⇧⌘G), ids preserved, undoable.
- ✅ Move blocks to another doc (block menu → Move to), undoable on both sides.
- ✅ Undoing a group / ungrouping no longer leaves a page in Recently Deleted.
- ✅ Toggle list (`+ `, ⌘↩), callout block, page break (`===`, honored when printing), strong/dotted/three-dot separators, `x ` task trigger.
- ✅ Cover crop/reposition (Original, 16:9, 2:1, 3:1, 4:3, Free; keyboard nudging) stored as data.
- ✅ Tab state across restarts (scroll + caret). ⬜ Back/forward stacks (moved to v0.3 with links).
- ✅ Image block: resize (edge drag or S/M/L/Full), caption, alt text; file attachment block (picker, drag and drop, Finder paste; opens in its default app).
- ✅ Performance pass with `scripts/perf.sh` (10,000 blocks, real app). Fixed: per-keystroke whole-window
  SwiftUI re-renders and full-document conversions (131 → 7 ms p50), full ID scans on Return
  (114 → 13 ms), block moves via direct paragraph cut/insert (382 → 14 ms), forced full layout on
  height changes, and search of text beyond the 50,000-character index.
  🟡 Known limits (TextKit 1 contiguous layout): keystrokes that change wrapping (~20 ms p95) and
  toggles near the top of a 10k-block doc (~120 ms) relayout everything below → v0.8.

**Gate (as shipped).** Build, 77 tests, smoke test (relaunch: content, grouping, move-to, trash,
backups, search jump, block link, ungroup, tab state), drag test and `scripts/perf.sh` all pass.
Every new block type round-trips losslessly through the native format (tests) and exports to
Markdown, with lossy cases reported (toggles → bullets, callouts → quotes, image sizes).
**Deviation:** the planned < 16 ms p95 keystroke target at 10,000 blocks is not met (7 ms p50,
~20 ms p95; budget in `perf.sh` is 16 ms p50 / 40 ms p95) — the remaining cost is TextKit 1
contiguous relayout and moves to v0.8 with the layout-scaling work.

**Data/format.** Additive only (schema stays 1): `toggleList`/`toggleItem(open)`, `callout(icon)`,
`pageBreak`, `horizontalRule.variant`, `file`, `image.width/caption`, `cover.crop/ratio`,
`Tab.scrollY/selStart/selLength`. Older builds keep unknown blocks as preserved placeholders.



## v0.3 — "Linked thinking" (macOS)

**Theme.** Notes that know about each other and about time: links, backlinks, tags, daily notes,
a calendar, and tasks across documents. Everything is derived from block ids in a local index.

**Implementation order** (each step builds on the previous one):

| # | Feature | Status | Acceptance check |
|---|---|---|---|
| 1 | Local link/tag/task index (`index/` in the vault, rebuilt from documents, incremental on save) | ⬜ planned | Deleting `index/` and relaunching rebuilds the same results; a 10,000-block vault indexes in < 3 s; no document file is ever written by indexing |
| 2 | Linked documents: `[[` and `@` picker (documents, nested pages, blocks), inline link chips, ⌘-click / click to open | ⬜ planned (block links via `draft://` ✅ in v0.2.1) | Type `[[Plan` → pick → chip shows the live title; renaming or moving the target keeps the link working; Markdown export writes relative links |
| 3 | Back / forward history across links and nested pages (⌘[ / ⌘]) | ⬜ planned (Back ✅) | Follow three links, ⌘[ three times returns through each with scroll restored |
| 4 | Backlinks pane (document rail segment) grouped by source with context snippet; jump to the linking block | ⬜ planned | A link added in doc A appears in B's backlinks within 1 s; clicking it opens A at the block |
| 5 | Block references that survive moves (render referenced block text, update when it changes) | ⬜ planned | Move or group the referenced block — the reference still resolves; deleting it shows a recoverable "missing" state |
| 6 | Tags `#tag`: inline chips, autocomplete, colors, tag results view in the rail, ignore rules (hex colors, numbers, custom) | ⬜ planned | `#ideas` autocompletes existing tags; `#ff0000` and `#1` are ignored by default (S17); tag view lists every block with the tag |
| 7 | Daily notes: one page per date in a "Daily Notes" folder, today via ⌘⇧D, previous/next day, optional template; "Show Daily Notes" toggle in All Docs (S25) | ⬜ planned | Opening today twice never creates two notes; dates follow the week-start setting |
| 8 | Calendar stream (S33): day cards (Today highlighted, upcoming dimmed), Add Task, Create Daily Note, filters Daily Notes / Tasks (/ Events with optional, permission-gated system calendar read) | ⬜ planned | Add Task on a future day creates a task with that due date in the daily note; filters persist |
| 9 | Tasks across documents: due dates (`@today`, `@tomorrow`, date picker), Inbox / Today / Upcoming / Overdue / Completed views, source context, completion with one undo | ⬜ planned (per-document Tasks pane ✅) | Completing a task in the Tasks view updates the source block; ⌘Z reverts both; overdue tasks show after midnight |
| 10 | Reminders as local notifications (opt-in) | ⬜ planned | A task due at 09:00 posts one notification; turning reminders off cancels pending ones |
| 11 | Move blocks to a new document / to today's daily note (S42) | ⬜ planned (Move to existing ✅) | ⌥⌘N moves the selection into a new doc and leaves a page card |
| 12 | Search options: exact "phrase", -exclusion, regex (S6, B§H); Quick Open includes blocks of the current Space | ⬜ planned (Space Search ✅) | `"quiet place" -draft` returns only matching docs; invalid regex shows an inline error |
| 13 | Date links / mentions of dates (Advanced settings: badge or text, S12) | ⬜ planned | `@next monday` becomes a date chip that opens that daily note |

**Prerequisites.** Stable block ids (✅), block links (✅), the index (step 1), week-start / start-of-day
settings (S12, moved here from v0.6).
**Data risk.** New inline node for links and tags (`docLink`, `tag`) and task attributes (`due`,
`priority`) — additive; older builds keep them as text with a preserved mark. The index is derived
data and never the source of truth.
**Release gate.** Renaming or moving a target never breaks a link; toggling a task in Tasks view
updates the source block with one undo; tags, backlinks and tasks survive relaunch and index rebuild;
perf budget holds with links in a 10,000-block document.
**Out of scope (why).** Mentions of people and comments need collaboration (v2.0); Events editing
needs a calendar provider (later, optional); recurring tasks wait for usage feedback (v0.5+).

## v0.4 — "Style studio" (macOS)

- ⬜ Save/duplicate/rename user styles, pin and set default, preview before apply; more original presets.
- ⬜ Gradient editor; image backdrop library + search provider (opt-in network); per-instance doodle/tape variation.
- ⬜ Contrast auto-adjust with explanation; per-block font.
- ⬜ Card sizes (compact/medium/feature) and preview modes (standard, icon, gallery).
- ⬜ PDF/HTML export with "use style" toggle; image export; static HTML site export.

**Gate.** Same document renders consistently in editor, HTML and PDF.

## v0.5 — "Structure" (macOS)

- ⬜ Collections in documents (field types incl. select/date/relation), items are pages.
- ⬜ Table → gallery → Kanban views with per-view sort/filter/group/visibility; calculations; CSV export.
- ⬜ Simple tables. Templates (save as template, picker with categories). Import (Markdown folder,
  HTML, OPML, Draft JSON). Multiple Spaces.

**Data risk.** Biggest schema change → migration 1→2 with a dry-run validator. **Gate.** 1,000-row
collection scrolls at 60 fps; a Kanban drag is one undoable record update.

## v0.6 — "Every window" (macOS + iPad-ready core)

(Week start / start-of-day settings moved to v0.3 for daily notes and the calendar.)

- ⬜ VoiceOver audit and fixes; full keyboard path for every panel; automated accessibility checks.
- ⬜ Localization (String Catalogs), two non-English locales; spelling language setting.
- ⬜ Keyboard layout (AZERTY/QWERTZ/Dvorak) and IME composition test matrix.
- ⬜ Remaining settings: shortcuts sheet, week start, sidebar customization; Focus mode; Present mode.

## v0.8 — "Trust" (macOS)

- ⬜ Layout scaling for very long documents: bounded relayout (e.g. TextKit 2 or chunked layout) so
  wrapping changes and toggles stay under 16 ms at 10,000 blocks; a separate search index.

- ⬜ Version history UI with diffs; vault integrity checker; orphan-asset GC (with confirmation).
- ⬜ Optional encryption at rest; performance budgets enforced in CI.

## v1.0 — "A credible personal workspace" (macOS)

**Gate.** Every parity row targeted ≤ 1.0 is `working` or `verified`; signed + notarized build;
documented format with conformance fixtures; CONTRIBUTING, code of conduct, issue templates; data
never leaves the Mac unless the user opts into a later sync feature.

---

## Windows track (separate app, after macOS 1.0 — never blocks the Mac release)

- **W0 (done during v0.1, no Mac cost):** portable format spec ([`FORMAT.md`](FORMAT.md)); `DraftCore`
  kept Foundation-only; format behavior covered by tests that can become shared fixtures.
- **W0.5 (alongside Mac v0.6–0.8, low cost):** export `Tests/Fixtures` as a language-neutral
  conformance suite (input vault → expected JSON/Markdown) so another implementation can verify itself.
- **W1 (after Mac 1.0):** Windows app reading/writing the same vault: native shell (WinUI 3) with a
  rich-text editor that maps to the same node schema; parity target = Mac v0.3 feature set first.
- **W2:** Windows reaches Mac 1.0 parity; vaults move between Mac and Windows losslessly via
  folder copy or the v1.x sync.

Out of scope until then: shared UI code across platforms (the editor is deliberately native per platform).

## v1.x — "Sync & publish" (optional, self-hostable)

- ⬜ Sync via a CRDT layer over a user-chosen folder (iCloud Drive / Syncthing / Dropbox) or a
  self-hostable relay; conflict recovery UI.
- ⬜ Publishing: static export first; optional self-hosted publish server with unlisted/password links.
  Publication is a policy attached to a document, never a copy.
- ⬜ Transfer to other apps; Share sheet; e-mail export.

## v2.0 — "Together"

- ⬜ Real-time collaboration, presence, comments, mentions, viewer/editor permissions — only after
  sync has run a full release cycle without data-loss reports.

## Later / optional

Assistant (opt-in, bring-your-own or local model, never required); local API/MCP connections
(permission-scoped); whiteboard, formulas, Mermaid; iPhone/iPad apps on top of `DraftCore`.

---

## Next smallest coherent slice (prioritized by user value)

*(updated after v0.2.1)* — start v0.3 with steps 1–2: the local index and `[[` linked documents,
then backlinks (4) and back/forward (3). Daily notes (7) and the Tasks view (9) follow, since they
share the date model.
