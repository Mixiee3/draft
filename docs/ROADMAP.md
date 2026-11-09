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
- **2026‑11‑08** — v0.7 started: reviewed MCP operations (create, rename, move, block changes, links, tasks) for Codex and Claude Code.
- **2026‑11‑08** — v0.6 work: polish pass, performance rows 13–15, Assistant rows 16, 17, 19, Focus/Present/Shortcuts/sidebar/per-Space settings; localization and table reordering moved to v0.8; VoiceOver, permissions and IME checks need a person.

- **2026‑11‑08** — v0.5.1 shipped (UI polish, design system, Local Assistant); v0.6 extended with tab-switch latency, Assistant follow-ups and voice.
- **2026‑11‑08** — v0.5 shipped; v0.6 planned in full with the carried permission and VoiceOver checks.
- **2026‑11‑08** — v0.4 shipped; v0.5 planned in full with carried-forward checks.
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

## v0.4 — "Style studio" (macOS) ✅ shipped

**Theme.** Make documents look the way you want and export them the way they look.

| # | Feature | Status | Acceptance check (result) |
|---|---|---|---|
| 1 | Saved user styles: save, duplicate, rename, pin, delete, use for new documents; gallery with live preview before Apply | ✅ | "Studio" saved from one document and applied to another renders identically after relaunch; deleting a style in use falls back to its base and content is unchanged (`scripts/style-test.sh`, `StyleStudioTests`) |
| 2 | Original presets | ✅ | 6 new (Linen, Aurora, Graphite, Sorbet, Harbor, Orchard; 13 in all), every one ≥ 4.5:1 text contrast (`testPresetsAreReadable…`) |
| 3 | Gradient editor (start/end color, direction) | ✅ | Angle and colors update live, survive relaunch, and appear in the HTML export (`linear-gradient(130deg, #112233, #ddeeff)`, style test) |
| 4 | Backdrop library + opt-in online search | 🟡 | Library: 12 original vector scenes, fully offline ✅. Online search (Openverse) is off by default, refuses with no request while off, and asks before the first search ✅; a real search against the live service was not exercised in automation |
| 5 | Varied separators | ✅ | Two tape separators in one document differ (angle, length, offset) and keep their look after relaunch (stable per block id; style test, `testSeparatorVariation…`) |
| 6 | Contrast auto-adjust with explanation | ✅ | Low contrast shows "Adjust text color (2.2:1 → 4.6:1)", keeping the hue (`testReadableColorKeepsHue…`, `v04-contrast-adjust.png`) |
| 7 | Per-block font | ✅ | A Mono block stays Mono after the document font changes, after relaunch and in HTML export; code blocks stay mono; one undo (`StyleEditorTests`, style test) |
| 8 | Card sizes (compact/medium/feature) and previews (standard/icon/gallery) | ✅ | Stored on the card, drawn in the editor, kept in JSON and HTML export, one undo (`testCardSizeAndPreview…`, style test) |
| 9 | Styled PDF, HTML and PNG export with "Use document style" | ✅ | PDF and PNG are made from the same HTML; page color sampled in the editor, the PNG and the PDF matches the style within 5%; PDF text is real text and page breaks paginate (style test). Not a full-image diff |
| 10 | Offline static site | ✅ | 8 pages, 15 local links and assets all resolve, no scripts or remote resources (style test, `testSiteLinksAllResolve`) |
| 11 | Web-link previews (opt-in) | 🟡 | Off by default: a pasted URL stays text and nothing is requested ✅; when on, a card appears, fills in without an undo step and exports as a plain link ✅ (unit test with a stand-in fetch); a real fetch was not exercised |
| 12 | Calendar filters persist | ✅ | All/Tasks/Notes and Completed survive relaunch (links test) |
| 13 | Dates as chips or plain text | ✅ | Switching changes only the look; stored dates identical (links test, `testDueDateFromEditor…`) |
| 14 | Task due dates and times | ✅ | Date/time picker and `@tomorrow 3pm` write a date chip; the reminder is scheduled at that time; one undo (links test) |
| 15 | Today/Overdue roll over while idle | ✅ | Checked every 20 s; with the clock moved past the day start, tomorrow's task moves to Today (links test) |

Also fixed: each document keeps its **own undo history** (⌘Z never edits a document you aren't looking at);
an off-screen document that receives new link titles gets **no extra undo step**; style changes
are **undoable** (a drag of the same control is one step); date chips store a stable label ("Mon 9 Nov")
instead of words like "Tomorrow" that went stale at midnight.

**Release gate (met).** Editor, HTML and PDF agree on page color and text (sampled), every style
change is undoable and never touches content, v0.3 vaults open unchanged (vault written by the v0.3
build read by v0.4: content, style, trash and backups intact). 111 unit tests; smoke, drag, links,
style/export and perf scripts pass (keystroke p95 ≈ 22–24 ms, index rebuild 0.8 s on 10,000 blocks).

**Not tested.** The macOS Allow/Don't Allow prompts for notifications and calendars (computer use was
not available to click them; scheduling and cancelling was checked in the bundled app). VoiceOver itself
(not run; the automated label audit only inspects AppKit views and does not cover it). Real network
requests for image search and link previews.

**Known limitations.** When a document that is not on screen receives new link titles, its own undo
history is reset (its old steps would point at shifted text). Word export remains "later".

## v0.5 — "Structure" (macOS) ✅ shipped

**Theme.** Structured information inside documents: collections with views, simple tables,
templates, import, and more than one Space. Started with a polish pass (window buttons, cursor,
glass formatting bar; before/after in `docs/screenshots/polish/`).

| # | Feature | Status | Acceptance check (result) |
|---|---|---|---|
| 1 | Schema 2 migration with a dry-run validator (backup first, never in place) | ✅ | A vault written by the v0.4 build, copied and opened by v0.5: dry run reports no differences, `backups/…-library.v1.json` is byte-identical to the original, every document and folder is in the Space, trash, folders and saved styles unchanged; smoke and style reads give identical results on both builds. A failing dry run leaves the vault read-only (`SchemaTwoTests`) |
| 2 | Simple tables (C1) | ✅ | Tab/⇧Tab/Return move between cells, ⌥⌘↓ adds a row, ⌥⌘→ a column; one undo per committed cell; Markdown pipe tables round-trip (`TableTests`, `StructureTests`). Partial: no column reordering, plain text inside cells |
| 3 | Collections: 8 field types; items are pages (C2) | ✅ | 1,000 items open in 83–116 ms; items open as pages and keep ids after relaunch (`scripts/structure-test.sh`). Partial: the relation picker lists the first 40 documents, no search |
| 4 | Views: table, gallery, Kanban; per-view sort, filter, group, visible fields (C3) | ✅ | Each view keeps its own settings after relaunch; 1,000-row table scroll p95 4–5 ms at a fast trackpad speed (budget 16.7) |
| 5 | Kanban drag between groups | ✅ | One drag changes one value of one record; one undo restores it (structure test). VoiceOver users get "Move to" actions on cards |
| 6 | Calculations row, multi-sort, AND/OR filters (C4) | ✅ | Sum of the fixture = 832 as hand-computed; sort by pages descending gives Dune, Zen, Atlas (structure test, `StructureTests`) |
| 7 | CSV and frontmatter export (C5) | ✅ | Exported CSV re-imports into a second collection with the same values; item pages carry YAML frontmatter |
| 8 | Templates (M1, M2) | ✅ | 5 original built-ins plus saved templates with categories; new documents get fresh block ids and the template's style; editing a template never changes documents made from it (workflow test) |
| 9 | Import: Markdown folder, HTML, OPML, Draft JSON (X5) | ✅ | Draft's own export re-imported reproduces documents, links, style and folder; links between Markdown files become doc links; clashing ids are remapped (workflow test, `ImportTests`) |
| 10 | Multiple Spaces (N8, Z7) | ✅ | Two Spaces keep separate trees, tags and tabs; switching never loses unsaved text; tabs come back per Space after relaunch (workflow test). Partial: settings other than the name are shared by all Spaces |
| 11 | Carried: live image search and link previews | ✅ | Opt-in on: 18 Openverse results, one image (224 KB) downloaded into assets; preview of example.com read its title; off: zero requests (`online-live` automation) |
| 12 | Carried: notification and calendar permission prompts | ⬜ not tested | Computer use was not available to click the macOS prompts; moved to v0.6 |
| 13 | Carried: VoiceOver pass | ⬜ not tested | VoiceOver was not available to drive; moved to v0.6. The label audit now also covers the table editor, collection views, template picker and Space settings, but it only inspects AppKit views |
| 14 | Carried: keep an off-screen document's undo history when link titles change | ✅ | The title refresh rides along as a silent step; after a rename elsewhere, ⌘Z in the linking document still undoes its earlier edits (`LinkTests`) |

**Release gate (met).** 126 unit tests (67 editor, 59 core); smoke, drag, links, style/export,
structure and workflow scripts pass; perf passes (keystroke p95 ≈ 22–23 ms; return p95 12–24 ms, one
run of three hit 38 ms against a 33 ms budget). v0.4 vaults migrate losslessly (check above).

**Not tested.** The macOS permission prompts and VoiceOver itself (see 12 and 13).

## v0.5.1 — "One app, and a local Assistant" (macOS) ✅ shipped

| # | Feature | Status | Acceptance check (result) |
|---|---|---|---|
| 1 | UI audit with before screenshots | ✅ | 100 before shots across library, editor, panels, settings, calendar, tasks, tables, collections, templates, Spaces; issues and fixes below; before/after pairs in `docs/screenshots/v051/` |
| 2 | One design system | ✅ | `DesignSystem.swift`: type scale (9–30 pt, 8 sizes in place of 19), 4-pt spacing, three radii (10/14/18 in place of 10 values), control heights, one floating-surface shadow, motion timings; 202 font sizes and 50 radii migrated |
| 3 | Shared controls | ✅ | 12 AppKit segmented pickers (navy selection) and the Calendar checkbox replaced by Draft's segmented control and toggle chip, with selected/toggle traits for VoiceOver |
| 4 | Fixed issues | ✅ | Format/Style/Info/Share panels no longer cover the page (the page moves aside, re-wrapping only when it must); Style panel labels no longer truncate; breadcrumb readable on scenic backdrops; disabled chips legible in dark mode; Tasks and Calendar columns align under their header; About text no longer claims "no network" |
| 5 | Lag | 🟡 | Date keys made a new `DateFormatter` per call (hot in link refresh, calendar, tasks) → cached. Redundant tab re-activation and panel publishes removed. Tab switch p50 38 → 30.5 ms, p95 85 → 75 ms; still over the new 50 ms p95 budget: the cost is SwiftUI re-evaluating the whole window from one `AppModel` (moved to v0.6 #14) |
| 6 | Libraries.dev effects | ✅ | Thinking Orbs (loading, searching, reasoning, writing), Border Beam (composer while answering), liquid metal (send/Stop and Download only), MIT, pinned revision; Metal shaders verified in the release app; still fallbacks for Reduce Animations, macOS Reduce Motion and inactive windows (`assistant-answering-reduced.mp4`). Liquid Metal's package depends on iOS-only MagnetKit, so its shader is vendored. Voice Glow/Ring not used (no voice mode); Gooey and Image FX not used (no native version, no need) |
| 7 | Local Assistant | ✅ | ⌘J/toolbar; pinned or floating; LFM2.5-2.6B QAD-Q4_0 via llama.cpp b11722 in-process on Metal; opt-in download (1.59 GB) with progress, SHA-256 check, cancel, remove; Selection/Document/Space; Space retrieval over the vault index with cited source cards that open the block; six actions; streaming, Stop, per-Space history; preview with diff before Insert/Replace, one undo step; offline end-to-end test (`scripts/assistant-test.sh` under a no-network sandbox) |

**Model selection (measured on this M4 with 16 GB; GPU shared with a running Parsec session, so absolute
speeds are low).** llama-bench without load: 2.6B Q4_K_M 34.7 tok/s, QAD Q4_0 31.9, Q8_0 16.4, 1.2B 52.3.
In Draft under load: QAD Q4_0 14.2 tok/s (1.8 GB resident), Q4_K_M 10.9, Q8_0 8.6, 1.2B 18.9–38.8.
QAD Q4_0 gave correct cited answers, clean "not in these notes" refusals and kept Markdown task
structure; the 1.2B dropped checkboxes and leaked citation markers into rewrites (offered as the
faster, less careful option). LFM2.5-2.6B always reasons before answering (`<think>`), which Draft shows
as "Thinking…" with the reasoning on request; first answer words arrive after several seconds.

**Release gate (met except tab-switch latency, pre-existing).** 147 unit tests; smoke, drag, links,
style/export, structure, workflow, perf (keystroke p95 22 ms, Return p95 12 ms) and the offline
Assistant test pass.

## v0.6 — "Every window" (macOS + iPad-ready core) 🟡 in progress

Measured on a MacBook Air M4 (60 Hz) with Parsec running, which keeps the system GPU about 65% busy
even at idle; all numbers below are under that load and from a limited number of runs.

| # | Feature | Status | Acceptance check (result) |
|---|---|---|---|
| 1 | Carried: VoiceOver pass through Calendar, Tasks, `[[` and `#` pickers, Style Gallery, export, tables, collections, template picker, Space switcher | ⬜ needs a person | Labels added to every new control (welcome, tour, shortcuts, relation picker, Present, voice); a real VoiceOver walk-through has not been done |
| 2 | Carried: notification and calendar permission prompts | 🟡 code ready, needs a person | Denial paths turn the setting back off with an explanation; clicking Allow / Don't Allow in the macOS prompts was not tested |
| 3 | Automated accessibility check from a separate process | 🟡 tool written | `scripts/ax-audit.swift` lists unnamed buttons, menus, fields and toggles; it needs a terminal with Accessibility permission, which this session did not have, so it has not run |
| 4 | Full keyboard path for every panel; visible focus rings | 🟡 partial | Welcome, tour (←/→/Return/Esc), Shortcuts sheet, Quick Open, Present and Focus mode are keyboard-only; a full panel-by-panel pass is still open |
| 5 | Localization with String Catalogs, two non-English locales; spelling language | ⬜ planned → v0.8 | Not started; UI strings are still literals |
| 6 | Keyboard layouts and IME matrix | ⬜ needs a person | Not tested |
| 7 | Shortcuts sheet | ✅ | Help → Keyboard Shortcuts (⌘/), searchable, read from the live menu bar so it can't disagree with the menus (`MenuShortcutTests`) |
| 8 | Sidebar customization | ✅ | Show/hide and reorder in Settings → Appearance → Sidebar; stored in settings and repaired on load (`SpaceSettingsTests`) |
| 9 | Focus mode | ✅ | ⇧⌘F hides chrome and fades all but the current block; Esc leaves; 10k blocks in Focus mode: keystroke p95 14–18 ms, Return p95 13–16 ms (3 runs) |
| 10 | Present mode | 🟡 | ⌥⌘P or Info → Present: level 1–2 headings split slides (`SlidesTests`), arrows/Space/Return/Esc; second-display full screen implemented but untested (one display) |
| 11 | Relation picker search; table column reordering; rich text in cells | 🟡 1 of 3 | Relation picker searches every document; column reordering and rich cells moved to v0.8 |
| 12 | Per-Space settings (theme, daily notes, tag rules) | ✅ | Each Space keeps theme, accent, daily-note and tag settings; applied on switch without restart (`SpaceSettingsTests`) |
| 13 | Perf: steady return-key latency | ✅ | Return p95 8.0–15.9 ms in 10 consecutive `scripts/perf.sh` runs (budget 33) |
| 14 | Tab and Space switching under budget | ✅ (under load, 3 runs) | Observation split; lazy document-rail lists; tour anchors read only during the tour. Tab p95 36–46 ms (was 69–91 at the start of the day, 149 ms median in the audit), Space p95 46–85 ms (`scripts/ux-perf.sh`) |
| 15 | Opening a document from the library | ✅ (under load, 3 runs) | 2,000 blocks: 126–143 ms (was 271–333): cached editor fonts and a JSONSerialization fast path for current-schema documents (equivalence tested) |
| 16 | Assistant: long documents | ✅ | Reads all parts and combines notes; notice states it; offline test finds a fact at the end of a 4,686-word note |
| 17 | Assistant: faster follow-ups | ✅ | Saved model state after the system turn; second question first token 0.12–0.39 s vs 2.3–3.0 s (7.7–19×) |
| 18 | Assistant: voice mode | 🟡 | Read Aloud verified offline; dictation is on-device only (`requiresOnDeviceRecognition`) and available on this Mac, but the permission prompts and a live dictation need a person; VoiceGlow only while listening/speaking |
| 19 | Assistant: quality checks | ✅ | `scripts/assistant-quality.sh`: 30 questions, LFM2.5 2.6B 27/30 = 90% (was 24/30 before fixing the 200-character index limit, stemming and the prompt) |
| 20 | Carried: VoiceOver pass of the Assistant | ⬜ needs a person | Not done |

**Codex/MCP and OpenAI (merged from `feature/codex-integration`).** Optional OpenAI provider with
your own key and per-request context review (live request untested: needs the user's key). `DraftMCP`
reads notes and proposes edits that Draft applies only after review, with a revision check, backup,
index update and one Undo; reject and stale paths verified (`scripts/agent-test.sh`) and an external
stdio round-trip (read → guide → propose → note unchanged → accept in Draft → saved → status
accepted). Still to do with the same reviewed design: create/rename/move notes, block
insert/delete/reorder, links/tags/tasks, multi-document proposals; a real Codex app-server mode only
after supported sign-in exists.

**Polish pass (from `docs/UI_AUDIT_V06.md`).** Shared components and surfaces; centred icon menus;
Settings rebuilt with grouped rows and a readable shortcut list; one surface and motion for Format,
Style, Info, Share, Quick Open, templates and dialogs; the page slides aside for panels; new notes
open as a full page with the caret in the title; arrow cursor off the page and click-away ends
editing; floating Assistant fits the screen (it was 1,262 pt tall because the hosting view sized the
window); readable edit preview (before/after or tinted inline diff); Share tabs no longer truncate;
live Info counts; tab overflow fade; empty states; dark Paper; first-use welcome and tour.
Screens: `docs/screenshots/v06/`.

## v0.7 — "Agents that ask first" (macOS) 🟡 in progress

Codex and Claude Code work on notes through Draft's MCP server. Every change is a proposal: the
server writes only `agent-requests/`, and Draft applies it after the user clicks Apply, rechecks the
revision, saves with a backup, updates the index and makes it one Undo step. These rules hold for
every row below; a row isn't done until `scripts/mcp-test.sh` covers accept, one Undo, reject and a
stale revision for it in a throwaway vault.

**Shared budgets for every row.** Proposal queued by the server < 50 ms; review sheet first frame
< 100 ms; applying a proposal of up to 100 edits to a 2,000-block note < 250 ms; one Undo < 100 ms;
typing in the open note unaffected (Return p95 < 33 ms in `scripts/perf.sh`).
**Shared accessibility.** Every card is one VoiceOver element that reads the change in plain words;
Return applies, Escape rejects, Tab reaches both buttons with a visible ring; light, dark, narrow
(760 pt) and Reduce Motion (sheet fades, no slide).

### Done

| # | Feature | Status | Acceptance check (result) |
|---|---|---|---|
| 1 | Claude Code and Codex connected to the stable checkout | ✅ | Both run `~/Documents/Draft/scripts/draft-mcp.sh`; after a restart Claude Code lists all 14 `draft_*` tools |
| 2 | Read tools | ✅ | Spaces, folders, documents, search, document, structure, block, revision, formatting guide |
| 3 | Create, rename and move notes | ✅ | Reviewed; fresh ids; folder and Space; one Undo; reject, stale and relaunch checked |
| 4 | Append, insert, delete, reorder blocks; block types, lists, tasks, quotes, callouts, code | ✅ | One proposal = one Undo; other blocks keep ids and marks |
| 5 | Inline formats, colours, highlights, links, block colours, decorations, separators, styles | ✅ | Verified end to end |
| 6 | Images, files, tables, nested pages and links protected | ✅ | Deletes of image, file, table and page card refused; whole-note replacement refused while they exist (43-check `mcp-test.sh`) |
| 7 | Review sheet | 🟡 one check open | Light, dark and 760 pt captures (`docs/screenshots/v07/`); readable before/after for text, inline, block, separator, move and rename. Manual check by the user (8 Nov 2026): visible focus ring **PASS**, VoiceOver labels and navigation **PASS**, Return applies **PASS**, Escape rejects **PASS**, one-step Undo **PASS**. Tab navigation **not tested yet** (turn on System Settings → Keyboard → Keyboard navigation, open a proposal, press Tab) |
| 8 | MCP permissions and confirmations | ✅ | Settings › Agents: per-client switches (by the name each client reports) for *Read notes*, *Propose changes* and *Destructive changes* (deleting blocks, replacing a whole note, moving notes); new clients can read and propose, destructive stays off until allowed. Checked by the server and again when applying. Review sheet shows the client, the permission needed, every affected note, destructive warnings and **Reject / Later / Apply** (Later keeps it pending; Edit › Review Agent Proposals brings it back). Local activity log (tool, note, time; never text; last 1,000). `mcp-test.sh` 50/50: blocked reader refused, new client can't propose deletes, revoking before Apply blocks it, Later keeps it pending, log holds no note text. Client names are self-reported by local processes, so this guards against mistakes, not against malicious local software |
| 9 | Create folders | ✅ | `draft_propose_create_folder`: one level under an optional parent, in a chosen Space; the review shows the full “Space › Parent › Name” path; duplicate names (ignoring case), “/”, line breaks, “.”, “..”, missing parents refused by the server and again in Draft; stale if folders changed; one Undo removes it while empty; notes untouched (`mcp-test.sh`) |
| 10 | Delete whole notes with recovery | ✅ | `draft_propose_delete_document`: needs Destructive; moves the note and its nested pages to Recently Deleted (never permanent); the review lists every page and the notes linking to it; one Undo restores; reject and stale refused (`mcp-test.sh`) |
| 11 | Multi-note proposals | ✅ | `draft_propose_multi_note_edits`: 2–20 notes in the open Space, all-or-nothing (all revisions checked first; a failing part rolls back the ones applied), grouped review, one Undo reverts every note; destructive if any part is (`mcp-test.sh` 69/69). Limit: Undo needs the notes' editors to still be open in this session |
| 12 | Tables | ✅ | Note-edit actions on a table block, addressed by row and cell ids (listed by `draft_read_structure`): set a cell (inline Markdown: bold, italic, code, links; optional expected text refuses a changed cell), insert/delete/move rows, insert/delete/move columns. All table edits in a proposal are checked on a copy first, so one bad edit leaves the table untouched; one Undo; deleting rows or columns needs Destructive; a table keeps at least one row and column and can't itself be deleted. Review shows Before/After grids (changed and new cells green, removed red) and names rows and columns (“Add a row after row “Beans””). Light and dark/narrow captures; `mcp-test.sh` 78/78 including persistence after relaunch |

### Planned, in order

| # | Feature | Depends on | Acceptance check | Accessibility | Performance |
|---|---|---|---|---|---|
| 13 | **Collections** (add/update items and fields, set views) | 12 ✅ | Items keep ids; select/relation values validated against the field; relation targets must exist; one Undo | Same as tables, plus field names in every spoken change | Gallery stays ≥ 99% frames on time after apply |
| 14 | **Insert images and files** | 8 | The client passes a local file path; Draft copies it into `assets/` only after Apply (type and size limits: images ≤ 25 MB, files ≤ 100 MB), shows a thumbnail or file icon in the card; Reject leaves no asset behind; one Undo removes the block and an unreferenced copied asset | Card thumbnail has the alt text; Apply announces the file name | Thumbnail in the card < 150 ms; copying off the main thread |
| 15 | **Richer agent actions**: link to another note by title (`draft_propose_link_note`), add or remove tags (`#tag` with tag rules), set task due dates, set captions and alt text on existing images, apply a saved style to several notes, daily-note append | 11 | Each action has a plain-language card, validation, one Undo and an end-to-end check; link targets resolve to existing notes; due dates use the user's calendar settings | Cards read naturally (“Add #shopping to 3 tasks”) | Same shared budgets |
| 16 | **Review sheet polish**: collapse long proposals (show first 20 cards, “Show all”), a mini preview of the note after the change, per-card skip (apply the rest) | 11 | Skipped cards aren't applied and are reported back; a 100-card proposal opens in < 100 ms | Skip is a toggle per card with a label | Sheet first frame < 100 ms for 100 cards |
| 17 | **Codex app-server integration** (separate from the OpenAI API mode) | 8, 11 | Only after OpenAI documents a supported sign-in for third-party apps: Draft starts `codex app-server`, streams turns, shows approvals in Draft's own sheet, cancel works; no ChatGPT credentials stored by Draft; off by default and clearly labelled | Same review sheet; streaming status announced politely | First token < 2 s on a normal network; cancel < 500 ms |

## v0.8 — "Trust" (macOS)

- ⬜ From v0.6: String Catalog localization with two non-English locales and a spelling-language
  setting; table column reordering in one undo; bold/links in table cells that survive Markdown.
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

*(updated after v0.5.1)* — v0.6 starts with the state split behind tab-switch latency (14), then the two checks that need a person at the Mac (1, 2) and
the out-of-process accessibility check (3), then keyboard paths (4) and the v0.5 follow-ups (11, 12).
Localization (5, 6) comes after strings settle.
