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

- **2026‑11‑07** — v0.3 shipped; v0.4 expanded with the items deferred from v0.3.
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



## v0.3 — "Linked thinking" (macOS) ✅ shipped

**Theme.** Notes that know about each other and about time: links, backlinks, tags, daily notes,
a calendar, and tasks across documents. Everything is derived from block ids in a local index.

| # | Feature | Status | Acceptance check (result) |
|---|---|---|---|
| 1 | Local link/tag/task index (`index/index.json`, rebuilt from documents, incremental on save) | ✅ | Deleting `index/` and relaunching gives identical backlinks, tags, task buckets and block locations, and no document file changes (`scripts/links-test.sh`); 10,000-block vault rebuilt from disk in 0.8 s (perf `indexRebuildMs`, budget 3 s) |
| 2 | Linked documents: `[[` / `@` picker (documents, nested pages, blocks, "New document …"), link chips with live titles, click to open | ✅ | Chip follows a rename, a folder move and grouping, also after relaunch; Markdown export writes `[Title](Title.md)` relative links (links test) |
| 3 | Back / forward (⌘[ / ⌘]) across links, restoring scroll | ✅ | Follow link → back → forward lands on each document (links test); scroll offset is stored per history entry |
| 4 | Backlinks pane (rail segment), grouped by source, one row per mentioning block, click opens it | ✅ | A new link appears in the target's backlinks 0.52 s after typing stops (links test, budget 1 s) |
| 5 | Block references that survive moves; missing state | ✅ | Grouping the referenced block into a nested page: the reference resolves to the new page; a deleted target shows struck-through "missing" and recovers when restored (links test, `LinkTests`) |
| 6 | Tags: `#` autocomplete, colors, sidebar list, tag view, ignore rules (hex, numbers, custom) | ✅ | `#fff` and `#123` are not tags by default; custom words apply after re-index (`LinkingTests`, `testTagsAreColoredButHexIsNot`) |
| 7 | Daily notes: ⇧⌘D, previous/next day, template, "Show daily notes in All Docs" | ✅ | Opening today twice returns the same note, also after relaunch (links test `dailyUnique`, `dailyCount` = 1) |
| 8 | Calendar stream: day cards, Today highlighted, Create Daily Note, Add Task, All/Tasks/Notes filter, Completed toggle, optional calendar events | 🟡 | A task added on a future day is due that day and listed under Upcoming (links test); filters do not persist across relaunch (→ v0.4) |
| 9 | Tasks across documents: Inbox / Today / Upcoming / Overdue / Completed, due dates from `@date` chips or the daily note's day | ✅ | Completing a task in the Tasks view updates the source block in the editor and on disk; one undo reverts it (links test `undoSteps` = one) |
| 10 | Reminders (opt-in local notifications) | 🟡 | Bundled app: enabling schedules exactly one pending notification per due task; turning reminders off removes them (permission probe: 1 → 0). The macOS permission prompt itself was not clicked through in automation |
| 11 | Move blocks to a new document (⌥⌘N) or today's daily note | ✅ | Both leave a page card; moved blocks keep ids; one undo restores (`testMoveToNewDocumentAndTodayLeaveCards`) |
| 12 | Search options: `"phrase"`, `-exclusion`, regex (`.*` toggle); Quick Open finds blocks | ✅ | Invalid regex shows an inline error (`testSearchOptions`, `v03-search-regex-error.png`) |
| 13 | Date mentions `@next monday` → date chips that open that day | 🟡 | Chips, prefix suggestions while typing (`@nex`), week start and start-of-day settings work; the S12 "badge or plain text" display setting is not built (→ v0.4) |

**Deviations from the plan.** Tags stay plain text (no `tag` node): portable and readable everywhere.
Links and dates are marks (`docLink`, `date`), not new node types, so older builds keep the text.
Daily notes live in Unsorted with `dailyDate`, not in a separate folder; Calendar is their home.
Due dates come from date chips (or the daily note); `taskItem.due` is read but not written.

**Release gate (met).** Links never break on rename, move or group; task completion is one undo;
links, tags, tasks and daily notes survive relaunch and an index rebuild; perf budget holds
(keystroke p95 ≈ 23–28 ms, open 2.1 s, index rebuild 0.8 s on 10,000 blocks). 99 unit tests, smoke,
drag, links and perf scripts pass.

**Known limitations.**
- Renaming a document refreshes link titles in open documents; an off-screen document updates its
  chips when it is shown, as a separate undo step there.
- Today/Overdue roll over when the app next updates (any edit or navigation), not exactly at midnight.
- The real Allow/Don't Allow prompts for notifications and calendars were not exercised (they need
  a person); both start in "not determined" and are requested only from Settings.
- VoiceOver itself was not run; the picker exposes a menu with labelled, selectable items (tested).

## v0.4 — "Style studio" (macOS)

**Theme.** Make documents look the way you want and export them the way they look.

| # | Feature | Status | Acceptance check |
|---|---|---|---|
| 1 | Save, duplicate, rename and delete user styles; pin and set default; preview before apply (T4) | 🟡 partial ("Use for new documents" ✅) | Save the current look as "Studio", apply it to another document, relaunch: both render identically; deleting a style in use falls back to its base without touching content |
| 2 | More original style presets | ⬜ planned | At least 5 new presets, all original artwork; each passes the 4.5:1 text-contrast check |
| 3 | Gradient editor: start/end colors, direction (T6) | 🟡 partial (presets ✅) | Dragging the angle updates the backdrop live; the gradient round-trips through the file and export |
| 4 | Image backdrop library + opt-in search provider | ⬜ planned | Works fully offline with the bundled library; the search provider is off by default and asks before any network request |
| 5 | Per-instance doodle/tape variation | ⬜ planned | Two tape separators in one document look different and keep their look after relaunch |
| 6 | Contrast auto-adjust with explanation (T9) | 🟡 partial (warning + one-click fix ✅) | Choosing low-contrast text offers an adjusted color with the before/after ratio stated |
| 7 | Per-block font (F20) | ⬜ planned | A block set to Mono stays Mono after restyling the document, in export and after relaunch |
| 8 | Card sizes (compact/medium/feature) and preview modes (standard, icon, gallery) (P3) | ⬜ planned | Size and mode are stored on the card, shown in the editor and kept by Markdown/JSON export |
| 9 | Styled PDF and HTML export with "use style" toggle; image export (X4) | 🟡 partial (Print → PDF ✅) | The same document renders consistently in editor, HTML and PDF (visual diff within tolerance) |
| 10 | Static HTML site export (U3) | ⬜ planned | Exporting a folder writes an offline site whose links between pages (including `docLink` chips) all resolve |
| 11 | Link previews for web links (A5, opt-in network) | ⬜ planned | Off by default; when on, a pasted URL becomes a preview card that still exports as a plain link |
| 12 | Calendar filters persist (deferred from v0.3 step 8) | 🟡 partial | All/Tasks/Notes and Completed survive tab switches and relaunch |
| 13 | Date display setting: chip or plain text (S12, deferred from v0.3 step 13) | 🟡 partial (chips ✅) | Switching to plain text re-renders every date without changing stored dates |
| 14 | Task due-date picker and due times (deferred polish from v0.3 step 9) | 🟡 partial (`@` dates ✅) | A date/time popover on a task sets a `date` chip with a time; its reminder fires at that time |
| 15 | Midnight rollover of Today/Overdue (deferred from v0.3 limitations) | 🟡 partial | With the app idle across the day start, Today and Overdue update within a minute |

**Gate.** Same document renders consistently in editor, HTML and PDF; every style change is undoable
and never touches content.

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

*(updated after v0.3)* — start v0.4 with user styles (1) and per-block font (7), which share the
style model, then styled HTML/PDF export (9–10) so the "renders the same everywhere" gate can be
measured early. The small v0.3 carry-overs (12–15) fit between them.
