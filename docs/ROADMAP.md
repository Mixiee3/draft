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
- **2026‑11‑24** — New plan after 0.11.8. Everything earlier is done, waiting for a person (VoiceOver, real keyboards and input methods, translations), or blocked outside the code (Developer ID notarization, Codex eligibility); those stay listed under *Manual checks carried forward*. Added v0.11 (shipped) and five milestones: v0.12 Liquid Glass everywhere, v0.13 Images & media (insertion, sizing, iPhone sketches as ink, scans, editing, galleries), v0.14 Capture anywhere, v0.15 Thinking tools, v0.16 Share what you write, then the v1.0 gate.
- **2026‑11‑15** — v0.11.5 published on the stable update channel. Fixed silent updater failures in protected install locations: request macOS authorization, verify again before replacement, restore/reopen the previous app on failure, and show a recovery message next launch. Added a drag-to-Applications DMG; the runtime is bundled. Automated updater checks pass. Real authorization and relaunch on another Mac remain a manual beta check.
- **2026‑11‑13** — v0.9 Scale & Reach: long notes, separate search index, Czech and German, keyboard/IME matrix, table column reordering, performance budgets on every build, accessibility static audit, panel timing, display sizes. Six features done; keyboard/IME, accessibility and display scaling need a person for the last part (physical keyboards, VoiceOver, system Reduce Motion).
- **2026‑11‑12 (late)** — v0.8 Trust & Recovery batch done: Vault Check with 19 problem kinds and severities; repairs with an exact preview, a backup and journal first, validation after, all-or-nothing and one Undo (also after relaunch); rebuild library from notes and rebuild index with a dry run; Version History with readable diffs and restore as one Undo step; attachment and backup browsers; migration validator with fixtures for every schema; startup recovery and Safe Mode. Found and fixed: prototype (schema 0) vaults could never migrate (two false differences in the dry run); a damaged search index was overwritten without a copy. `scripts/trust-test.sh` (41 checks) and `RecoveryPerfTests`.
- **2026‑11‑12 (night)** — Effect presets: 8 glow, 7 shadow, 6 outline, 6 lift, 5 emboss, 8 accent, 30 gradient (2–5 stops with positions, 4 radial), 16 Spectrum palettes (5 new), 19 block presets, three new highlights, grouped Calm/Warm/Cool/Editorial/Neon/Nature/Dark/Study/Decorative, in the effect editor, the Decorations panel and `draft_formatting_guide`. Text-rendering audit on native Retina captures: body text keeps full font smoothing; Shadow, Lift and Outline defaults were too soft or heavy and were tightened; Glow and Lift keep the text color. v0.8 started: vault check and unused-file cleanup (first slice).
- **2026‑11‑12 (evening)** — Spectrum direction was reversed (forward moved the colors left): fixed and checked from pixels in a unit test and in the running app. Six more palettes: Ember, Citrus, Forest, Glacier, Berry, Candy (11 in all; each loops without a seam, reaches at least three hues across a phrase and stays readable on every style).
- **2026‑11‑12 (later)** — Root cause of “Spectrum is one static color / effects are plain color changes”: macOS Increase Contrast is on on the development Mac, and Draft simplified every effect there (one still readable color; no glow, shadow, outline or emboss); earlier visual checks overrode Increase Contrast and so never showed it. Now a notice with **Show Full Effects** in the effect editor and the bar, an Appearance setting (Full text effects with Increase Contrast), palettes shown as their full gradients, an Animate switch; every effect re-verified on screen under the real system settings. Item 17 researched: blocked on eligibility (see below).
- **2026‑11‑12** — Editor fixes found with mouse-driven probes: mouse selections no longer pick up paragraph breaks and the empty blocks after a heading (they were painted as a wide selected band and formats applied to them); side panels no longer narrow the page (that re-wrapped every paragraph and moved the text under the reader by up to 9 pt). Text color and effect colors are separate (`EffectSpec`: effect color, gradient stops and direction, strength), edited in the Format panel's Text Effect section; every effect verified on screen through the bar (`effects-live`/`effects-read`); Outline now draws a visible rim.
- **2026‑11‑11 (evening)** — Interaction audit with mouse and keyboard events in the running editor (`selection-test`, `spectrum-test`): formatting bar regrouped (marks | link, code | colour | Effects | More) with labelled pages that wrap in narrow windows; the bar steps aside while the right-click menu is open (it used to sit on top of it) and comes back after; Font, Layout Orientation and Continuity Camera removed from that menu; Spectrum verified on screen (moving, one continuous gradient, still for Reduce Motion and Increase Contrast, after scrolling, tabs, style and theme changes, undo, paste, reopen and relaunch; GIF recorded); Gradient text moved onto the same gradient layer (it was coloured letter by letter). v0.7 row 16 done.
- **2026‑11‑11 (later)** — UI audit (fresh captures in light, dark, 720×640 narrow light and dark, Increase Contrast, maximized, full screen, resize; `docs/screenshots/v07/ui-audit/`) and fixes: window buttons pushed above the window after theme changes (AppKit re-laid out the title bar to its native height; the layout is now re-applied on every title-bar frame or appearance change, checked in 13 window states by `nav-test.sh`), the empty title row now drags the window and double-click zooms; dot textures redrawn in the scenes' language; Share tab labels truncated; focus lost after Present; raw Markdown in the Assistant's After preview; library cards ignored Paper's dark mode. New: Spectrum (moving gradient) text. v0.7 row 15 done.
- **2026‑11‑11** — v0.7 styling extension done: dot textures on all 24 presets, gradient editor, text effects, block effects, Effects row in the selection menu, styling through reviewed MCP proposals (`document_backdrop`, `text_effect`, new decorations).
- **2026‑11‑09** — Fixed: clicking a document tab did nothing from non-document screens (an empty toolbar in the title bar swallowed the click); `scripts/nav-test.sh`. v0.7 row 13 (collections) done.
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
| 13 | Collections | ✅ | `draft_read_collection` (fields, views, items with stable ids) and collection actions in `draft_propose_note_edits`: add/update/delete/move items (each item is a page; values checked against field types and select options), add/rename/delete fields, add views and set a view's type, sort, filters, match, group and visible fields, and `collection_create` for a new collection. Every edit is checked on a copy first, item pages are created only after that, and one Undo (Edit › Undo Agent Change) restores the data, removes new pages and brings back deleted ones. Deleting items or fields needs Destructive. Review shows the items as Before/After tables plus readable cards (“Update “Atlas”: Status: Done”, “Sort: Pages ↓ · Filter: Status isNot To do”). Existing UI checks still pass: 1,000 items open in 94 ms, scroll p95 5.1 ms, Kanban drag one undo, sort/group/CSV, ids after relaunch (`structure-test.sh`). `mcp-test.sh` 90/90 |
| 16 | Review sheet for long proposals | ✅ | A summary that stays visible (changes, notes, removals, kinds); changes grouped by note (or block) or by kind in collapsible sections, Expand/Collapse All, long proposals open with the first section only; groups over 15 cards show 10 with “Show N more”; removals marked in red with a VoiceOver hint; section headers announced with their count and state; the list is sized to the window so Reject, Later and Apply stay on screen (checked at 720×640, light and dark); the notes' structure is read once per sheet, not on every redraw. Apply, Undo, stale revisions and all-or-nothing are unchanged. `mcp-test.sh` 129/129 with a 40-change proposal rejected in narrow dark and applied and undone in light. Not done: per-card skip (apply the rest) and a mini preview of the note after the change |
| 15 | Richer agent actions | ✅ | Note edits `link_note` (a phrase becomes a link chip to another existing note; the server and Draft both refuse missing, deleted or template targets), `add_tag` / `remove_tag` (no duplicates), `task_due` (YYYY-MM-DD or none; tasks only), `image_caption` / `image_alt` (images only), plus `text_effect` spectrum; library proposals `draft_propose_rename_folder` (unique, valid names; one Undo restores), `draft_propose_create_style` (saved style from JSON, text ≥ 4.5:1 and accent ≥ 3:1 or refused; optionally applied to a note; the review shows its look before and after; one Undo removes it and restores the note) and `draft_propose_daily_append` (today's daily note by the day-start setting; refused if it doesn't exist). Applying a saved style to several notes uses `document_style` in a multi-note proposal. Every card reads in plain words with before and after (old caption, old folder path). `RicherAgentActionTests`; `mcp-test.sh` 123/123 (accept, one Undo, reject, stale revision, missing link target, unreadable style, bad folder name, images kept) |
| 14 | Insert images and files | ✅ | `insert_image` / `insert_file` in note edits with a full local path. One policy in DraftCore checks type (images png/jpg/gif/heic/webp/tiff ≤ 25 MB; documents, archives, audio and video ≤ 100 MB; no scripts, links, folders or bundles), size and readability when proposed and again at Apply, with a SHA-256 fingerprint so a file swapped in between is refused. Nothing is copied before Apply; Reject and Later leave no file. Apply copies the file into `assets/` (content-addressed) and inserts the block with the proposal's other edits; one Undo (Edit › Undo Agent Change) removes the block and any copy this proposal created. Review shows thumbnail or file icon, name, type, size, path, caption, target block and note. `mcp-test.sh` 105/105: unsupported type, oversized, missing, permission, Later, Reject, apply, one Undo with cleanup, file changed after proposal, stale revision, links/tables/images/nested pages kept, relaunch |

### Planned, in order

| # | Feature | Depends on | Acceptance check | Accessibility | Performance |
|---|---|---|---|---|---|
| 17 | **Codex app-server integration** (separate from the OpenAI API mode) — ⏸ blocked on eligibility (researched 12 Nov 2026) | 8, 11 | OpenAI now documents app-server (JSON-RPC over stdio: `initialize`, `thread/start`, `turn/start`, streaming `item/*` and `turn/completed`, `turn/interrupt`, approval requests) and a Sign in with ChatGPT flow for open-source clients (PKCE, loopback redirect `127.0.0.1`, dynamic client registration issuing an `oaiapp_…` client id, token passed to app-server as an environment variable). But plan usage is “available to all open-source partners and selected private clients”, and Sign in with ChatGPT for commercial apps is a limited trial. Draft is a private repository, so it is neither; using the open-source registration would misrepresent it. Implement when Draft is published as open source or OpenAI issues it a client id. Architecture: `docs/CODEX_INTEGRATION_HANDOFF.md` | Same review sheet; streaming status announced politely | First token < 2 s on a normal network; cancel < 500 ms |

### Styling (v0.7 extension)

| Feature | Status | Evidence |
|---|---|---|
| Layered background model: multi-stop gradients with opacity, linear angle or radial focal point, soft light, quiet patterns (dots, grid, halftone, waves, hills, stars, blobs, rings, diagonal, window light), grain | ✅ | `Backdrop` fields (optional, older files decode unchanged), `FieldView` drawn once per size (Equatable, so typing doesn't redraw it); `BackgroundTests` |
| 24 original background presets | ✅ | Soft Sunrise, Quiet Lavender, Blue Hour, Moss Study, Terracotta Paper, Winter Glass, Coastal Haze, Deep Ink, Apricot Grid, Sage Mist, Midnight Constellation, Rose Paper, Mineral Blue, Amber Desk, Cloud Study, Forest Dusk, Lilac Fog, Copper Evening, Sea Glass, Charcoal Bloom, Lemon Wash, Indigo Paper, Warm Concrete, Morning Window: procedural, no image files or network; distinct palette, texture and light; each text colour ≥ 4.5:1 on its page and accent ≥ 3:1 (tested); Style Gallery section; persisted by style id; screenshots in `docs/screenshots/v07/backgrounds/` (light, dark, narrow, Increase Contrast) |
| Accessibility fallback | ✅ | Increase Contrast keeps only the gradient (verified on this Mac, which has Increase Contrast and Reduce Transparency on); static, so Reduce Motion needs nothing more |
| Export | ✅ | HTML/PDF/PNG: field backgrounds are rendered to a picture like scenic backdrops; gradients export their stops (linear or radial) as CSS; `style-test.sh` and a field export check |
| Performance | ✅ | 10,000-block typing on Midnight Constellation / Copper Evening: keystroke p95 19.8 / 21.8 ms (Paper 14.8), Return p95 11.4 / 11.3 ms (budgets 40 / 33) |
| MCP and Assistant formatting | ✅ | `draft_formatting_guide` lists `background_styles` with mood guidance and the Increase Contrast rule; applied through the reviewed `document_style` proposal |
| Dot textures | ✅ | Redrawn in the language of Draft's original scenes (compared side by side with Tidepool and Ember): a ~13 pt lattice whose dot size falls off as 1 − d² inside soft discs anchored to the light, one palette colour at 40–60 %, drawn under the pattern so hills keep the land clean, and placed in the side margins the page card leaves visible. Six styles (grid, radial, halftone, cluster, scatter, fade), all used, distinct per preset; drawn in the same cached canvas and exported with it. Increase Contrast drops it with the other decorative layers; Reduce Transparency changes nothing because field backgrounds are opaque. `BackgroundTests` (visible ranges, distinct per preset, persistence); 24 presets × light, dark, narrow, Increase Contrast in `docs/screenshots/v07/backgrounds/` |
| Gradient editor in the Style panel | ✅ | Backdrop › Gradient: live preview, linear/radial, angle, focal point, 2–8 colours with colour, position and opacity, add/remove/reorder, Reset to the style's own backdrop; a drag is one Undo (merged by `updateAppearance`); warning above 4.5:1 between stops with “Use Calmer Colors”; VoiceOver labels on every control; no animation. `GradientEditTests`, `styling-shots` (one-Undo drag and persistence) |
| Text effects | ✅ | Accent, Gradient, Glow, Shadow, Outline, Lift (3D offset), Emboss as an inline `effect` mark (text unchanged). Colours come from the style and are pushed to ≥ 4.5:1 on the page, so no effect can make text unreadable (tested for every style). Increase Contrast keeps the colour and drops glow, shadow and outline (`prefers-contrast` in exports). Selection menu → ✦ Effects row; selection kept; one Undo; HTML/PDF/PNG via CSS classes; `text_effect` agent action. `TextEffectTests`, `TextEffectExportTests` |
| Block effects | ✅ | Decorations Gradient, Glass, Glow, Accent beside Focus and Block (Format panel); Accent on a heading draws an accent underline. Plain fills only (no blur), boxes measured from the text so stacked effects don't touch. Increase Contrast flattens gradient and glow; Reduce Transparency makes glass solid. Content and block ids unchanged; one Undo; exported (all decorations now reach HTML/PDF/PNG through `data-deco`). `BlockEffectTests`, `BlockEffectExportTests` |
| Effects under Increase Contrast | ✅ | Shown in full by default (effect colors already reach 4.5:1); simplifying to one still, readable color is opt-in: Settings › Appearance › Simplify text effects with Increase Contrast (replaces the earlier opt-in “Full text effects”, which is ignored so existing libraries start full). When simplified, the effect editor and the bar say so, with **Show Full Effects**. Verified on the development Mac with the real setting: simplified vs full (all effects visible, Spectrum moving across several colors, after scroll, tabs, style change, reopen and relaunch). Spectrum palettes shown as gradients in the bar and the effect editor, with an Animate switch, speed and direction. `SpectrumPaletteTests` (each palette ≥ 3 hues across a phrase; palettes differ), `effects-live`, `spectrum-test` |
| Effect colors | ✅ | The text keeps its own color (the text color mark); each effect has its own color and strength (glow, shadow, outline, lift, emboss), accent color, gradient stops (2–5) and direction; Spectrum palette, speed and direction. Letters' fill colors (accent, gradient) are kept at 4.5:1 and the editor says when one was adjusted. Format panel → Text Effect (also from Effects → Customize… in the bar); a slider or color drag is one Undo. Exported as CSS variables and gradients; agents use `text_effect` values like `glow?color=#ff4fd8&intensity=0.7` or `gradient?stops=#3a5bd9,#d6336c&angle=30`. `EffectColorTests`, `EffectExportTests`, `effects-live` |
| Selection ranges | ✅ | Mouse selections (drag, double- and triple-click) stop at the text: paragraph breaks and empty blocks at either end are dropped, so a heading followed by empty blocks selects and formats only the heading; selections across real paragraphs are unchanged; keyboard extension untouched; empty blocks stay selectable as blocks. `SelectionRangeTests`, `editor-audit` |
| Side panels keep the page still | ✅ | Opening Format, Style, Info or Share slides the page sideways if there is room but never changes its width, so nothing re-wraps: first visible line, caret and selection stay put at the top, middle and bottom of a note (light, dark, 720×640). `PanelLayoutTests`, `editor-audit` |
| Spectrum text | ✅ | A moving multi-colour gradient for titles and labels (Aurora, Prism, Sunset Spectrum, Ocean Rainbow, Neon Dusk; still/slow/normal/fast; forward/backward), drawn as one continuous gradient clipped to the glyphs of the whole run; only the phase moves and only visible runs are redrawn (no layout or attribute work per frame), ~30 fps while on screen. Still under Reduce Motion (app or system), a readable solid colour under Increase Contrast, every colour pushed to ≥ 4.5:1 on the page, at most 200 characters in one paragraph. Exports a still gradient. Selection menu → Effects → Spectrum; `text_effect` `spectrum:<palette>:<speed>:<direction>`. `SpectrumTests`, `SpectrumCoreTests` |
| Selection bar and right-click menu (interaction audit) | ✅ | Checked with mouse and keyboard events in the running editor in light, dark, 720×640 narrow (light and dark) and Increase Contrast: double-click a word, drag a sentence, shift-click across paragraphs, hover, right-click, ⌥F10 then →/Tab/Return/Space/Escape, click a colour, click away, selections at the top, bottom and right edge, after scrolling, on links, lists, quotes, code and a custom background. The bar stays inside the window and off the selection in every case, keeps the selection when a colour or effect is applied, hides and restores the I-beam on click-away, and steps aside while the context menu is open. Bar: B I U S │ link, code │ highlight, colours │ Effects │ More (Clear Formatting, block options); pages with section labels and a labelled Back; effect names drawn in their effect; rows wrap in narrow windows. Right-click: Format Selection… (⌥F10), Block, Look Up, clipboard, spelling, services; macOS still adds AutoFill. `SelectionToolbarTests`; `selection-test` |
| Selection formatting menu | ✅ | Already on translucent material (`NSVisualEffectView`, within-window, hairline border, shadow, arrow cursor, keyboard ⌥F10); now with an Effects row. Captures light, dark, narrow, Increase Contrast in `docs/screenshots/v07/styling/` |
| Styling through MCP | ✅ | Formatting guide lists text and block effects with where each fits, plus restraint rules; `text_effect`, new decorations and `document_backdrop` (validated JSON gradient, never an image; refused above 4.5:1) go through the review sheet, which now shows the note's look **before and after** for `document_style` and `document_backdrop`. `mcp-test.sh` covers effects, a refused harsh backdrop and one-step Undo |

## v0.8 — "Trust" (macOS)

- ➡️ Localization, table column reordering and long-document layout moved to v0.9 (below).
- 🔎 **Open validation (not a reopened feature):** a person still has to try the Trust & Recovery
  screens with VoiceOver and Full Keyboard Access (Check, Repair preview, Attachments, Backups,
  Migration, Version History, startup recovery). Automated labels and focus checks are part of v0.9 #7.

- ✅ **Vault integrity checker and unused-file cleanup — first slice (12 Nov 2026).**
  Scope: Settings › Data & Storage › **Check Vault** reads the vault without changing it and reports an
  unreadable library, notes listed without a file, note files the library doesn't know, note files that
  don't decode, attachments a note points to that are missing, and attachments no note uses (notes in
  Recently Deleted and templates count as users). **Move Unused Files…** asks first (count and size),
  moves them to `backups/unused-<time>/` (never deletes) and one Undo moves them back.
  Acceptance: a throwaway vault with each kind of problem is reported exactly; moving and Undo restore
  the same bytes; nothing outside `assets/` is touched; a read-only vault refuses the move.
  Performance: check 2,000 notes and 1,000 attachments in < 2 s, off the main thread, UI responsive.
  Accessibility: the report is a list VoiceOver reads row by row with counts; the move button names the
  count; confirmation is inline in the same row (Cancel, Escape, or Move to Backups) so it is visible in captures.
  Result: `VaultCheckTests` (each problem kind, same bytes after Undo, read-only refusal, 2,000 notes / 1,000
  files in 0.4 s debug); `vault-check` probe in light and dark (`docs/screenshots/v08/vault-check/`).
  Screenshots: Data & Storage with a clean report, with problems, and the confirmation (light and dark).

### v0.8 batch — Trust & Recovery (12 Nov 2026, done)

Ten connected features. Rule for all of them: **scans only read; nothing in the vault is written until
the person approves an exact preview, a backup is made first, and the change is validated afterwards
(all or nothing).** Tests use throwaway vaults only.

| # | Feature | Depends on | Status |
|---|---|---|---|
| 1 | Complete Vault Check | first slice | ✅ |
| 2 | Vault repair (preview, backup, confirm, validate, Undo, journal) | 1 | ✅ |
| 3 | library.json and index repair (rebuild library from notes, restore metadata, rebuild index) | 1, 2 | ✅ |
| 4 | Version History UI (snapshots with source, readable diff) | — | ✅ |
| 5 | Document restore (backup first, ids/links/attachments checked, one Undo) | 4 | ✅ |
| 6 | Asset browser (used, unused, missing; type, size, last reference, documents) | 1 | ✅ |
| 7 | Crash recovery and Safe Mode | 2, 3 | ✅ |
| 8 | Backup browser (per-document, health, retention, preview, restore, delete) | 4, 5 | ✅ |
| 9 | Migration validator (dry run on a copy, fixtures for every schema, rollback) | 3 | ✅ |
| 10 | Performance and reliability checks | all | ✅ |

**Implementation order.** 1 → 2 → 3 (one repair engine in DraftCore: `VaultCheck` finds issues,
`VaultRepair` turns chosen issues into a plan of file changes, backs those files up to
`backups/repair-<time>/` with a `journal.json`, writes atomically, re-checks, and rolls back on any
failure) → 9 (validator reuses the same copy-and-check) → 4 → 5 (`VersionDiff` in DraftCore; restore goes
through the editor as one Undo step) → 6 → 8 (catalogue of everything under `backups/` and `history/`)
→ 7 (startup reads leftover journals, temp files and an unreadable library and offers recovery) → 10.

**1. Vault Check — acceptance.** One problem of each kind in a throwaway vault is reported exactly, with a
severity (Critical: data can't be read; Warning: something is missing or inconsistent; Info: tidy-up):
missing note file, unreadable note file, malformed JSON, duplicate document id (file name ≠ id inside,
or two files with one id), duplicate block ids in a note, library entry without a note, note file not in
the library, missing image/file, unused asset, nested page whose parent is gone, link to a missing note
or block, invalid index file, newer or unsupported schema, folder that no longer exists, leftover
temporary files from an interrupted save, interrupted repair or restore. The scan writes nothing
(test compares a hash of every file before and after).

**2. Repair — acceptance.** Each repairable issue lists its exact effect ("library.json: add entry
‘Trip notes’ from docs/d_x.json") before anything happens; Repair asks once more; the files it will
touch are copied to `backups/repair-<time>/` first; after writing, the vault is checked again and
every touched file must decode, otherwise every file is put back and the vault opens read-only with
an explanation. One Undo (toast, and the Backups browser) puts the copies back; it survives relaunch.
Issues without a safe repair (a missing image, a newer schema) say so and are never touched.

**3. Library and index repair — acceptance.** Rebuilding library.json from note files keeps every
known entry's folder, Space, star, nesting and unknown fields, adds entries for unlisted notes from
their own titles, drops nothing, writes atomically after a backup; a dry run shows the difference first.
Rebuilding the search/link index starts from nothing and gives the same results as before.

**4–5. Version History and restore — acceptance.** Automatic snapshots (every 10 min while editing,
30 kept) and manual ones (“Save Version”), each with time and source (automatic, manual, before
restore, before repair). The diff lists title, text (word level), formatting, block type, style,
backdrop and attachment changes, block by block. Restore shows the same diff as a preview, saves the
current version first, keeps block ids, lists blocks other notes link to that the old version doesn't
have, brings back attachments from `backups/unused-*` if needed, and is one Undo step in the editor.
Nested pages, links, tables, collections, images and files survive the round trip (test).

**6. Asset browser — acceptance.** Every file in `assets/` and every missing one: kind, size, used or
unused or missing, last reference (newest note that uses it) and the notes that use it. Unused files
move to `backups/unused-*` (Undo). Removing them for good is only possible from the Backups browser
and moves them to the macOS Trash after a second confirmation.

**7. Crash recovery and Safe Mode — acceptance.** At launch Draft notices a repair or restore journal
that never finished, leftover temporary files, a corrupt index, a library it can't read, a failed
migration or unreadable notes. It keeps the originals, explains what happened, offers recovery from a
backup (or rebuilding the library from the notes) and offers to continue read-only. Holding Option at
launch (or `DRAFT_SAFE_MODE=1`) opens the vault read-only.

**8. Backup browser — acceptance.** Lists per-document versions, migration copies, repair backups,
unused-file folders and unreadable copies with time, size, source and a preview; restores any of them
through the same confirmed path; deletes by moving to the macOS Trash after a warning; shows retention
(30 versions per note, 30 days in Recently Deleted) and health (unreadable backups, total size); an
optional clean-up of backups older than 30 days lists exactly what goes first.

**9. Migration validator — acceptance.** Copies the vault to a temporary folder (nothing written to the
real vault), migrates the copy, reports expected changes and fields this Draft doesn't know (which are
kept), verifies the migrated copy decodes and keeps titles, text, block ids and links. Fixtures for
every schema Draft has written (library 0, 1, 2; document 0, 1). Real migrations already back up
first; rollback puts the backed-up files back.

**10. Performance budgets.** Kept: keystroke p95 < 40 ms, Return p95 < 33 ms, tab switch p95 < 50 ms,
Space switch p95 < 100 ms, 2,000-block open < 250 ms where applicable, 1,000 collection items < 1 s,
scrolling at 60 FPS. New (debug build, Apple silicon): vault check of 2,000 notes / 1,000 assets < 2 s;
asset scan < 2 s; library rebuild from 2,000 notes < 3 s; migration dry run of 2,000 notes < 5 s;
listing 5,000 backups < 1 s; loading a 30-version history and diffing a 2,000-block note < 500 ms.

**Accessibility.** Every list row reads as one VoiceOver element (severity, title, detail); severity is
never shown by color alone (icon + word); every action is a real button reachable with Tab and has a
visible focus ring; Return confirms and Escape cancels in confirmations; no motion besides standard
progress (Reduce Motion respected); Increase Contrast uses the system's stronger separators.

**Screenshots** (`docs/screenshots/v08/`, light, dark and 720 px narrow): Vault Check with problems,
repair preview, repair done with Undo, Asset browser, Backup browser, Migration validator report,
Version History with a diff, restore preview, recovery screen after an interrupted repair, Safe Mode.

**Result.** All ten done. Evidence: `VaultCheckTests`, `VaultRepairTests`, `MigrationFixtureTests`,
`VersionDiffTests`, `BackupCatalogTests`, `RecoveryPerfTests`; `scripts/trust-test.sh` (light, dark,
narrow, relaunch, Safe Mode); screens in `docs/screenshots/v08/trust-recovery/`. Measured (debug):
vault check 2,000 notes / 1,000 assets 0.8 s; repair plan 0.7 s; asset list 0.1 s; library rebuild
1.6 s; migration validation 1.0 s (current) / 3.3 s (schema 1 → 2); 5,100 backups listed 0.65 s;
30-version history of a 2,000-block note listed, loaded and diffed in 38 ms. Not covered: a person
using VoiceOver and Full Keyboard Access on these screens (labels and focus are set in code); an
interrupted write caught at the exact byte (simulated through the journal state).

- ✅ Orphan cleanup for backups older than 30 days (manual, listed first — part of #8).
- ⬜ Optional encryption at rest (later milestone).

## v0.9 — "Scale & Reach" (macOS, 12–13 Nov 2026)

Nine connected features on branch `feature/v0.9-scale-reach`. Rules: measure before changing working
code (repeat runs, separate rendering cost from automation overhead); every automated test uses a
throwaway vault; the installed app is replaced only after the whole batch passes.

| # | Feature | Depends on | Status |
|---|---|---|---|
| 6 | Performance budgets in every build (`scripts/budgets.sh`: repeated runs, median-of-runs, machine and display report, history in `perf-history/`) | — | ✅ |
| 8 | Panel and window performance (re-measure Style, Format, Info, Share, Version History, Recovery, Assistant, review sheet; fix only what is consistently slow) | 6 | ✅ |
| 1 | Very long documents (10,000 and 20,000 blocks: typing, Return, scrolling, selection, formatting, moves, outline, relaunch) | 6 | ✅ |
| 2 | Separate search index (`index/search.json`: blocks, phrases, regex, exclusions, tags, dates, links, versioned, stale detection, safe rebuild) | — | ✅ |
| 5 | Table column reordering (keyboard, menu, drag; one Undo; MCP before/after) | — | ✅ |
| 3 | Localization (String Catalog; English source; Czech and German; plurals; dates and numbers; spelling language) | 5 (new strings first) | ✅ |
| 4 | Keyboard layouts and IME (QWERTZ, AZERTY, Dvorak; Japanese and Chinese composition) | 3 | 🟡 automated parts done; physical keyboards and real IMEs need a person |
| 7 | Accessibility and keyboard reach (names, roles, values, focus order, focus rings, Reduce Motion, Increase Contrast) | 3 | 🟡 static audit and fixes; full VoiceOver/AX audit needs a person or Accessibility permission |
| 9 | Display scaling and narrow layouts (720×640, 960×720, 1440×900; light, dark, Increase Contrast, Reduce Transparency, Reduce Motion) | 3, 7 | 🟡 three sizes, light and dark verified; Increase Contrast and Reduce Transparency are on on this Mac; system Reduce Motion not toggled |

**Implementation order** is the table order: the measuring harness first (so later work is judged on
repeated numbers), then the code-heavy features, then localization (after new strings exist), then the
input, accessibility and layout passes over everything, then screenshots and the full test run.

**Acceptance and budgets.**
- *#6/#8:* each check runs N times (default 3); a budget fails only when the **median** is over it;
  one slow run is reported as noise. Report: Mac model, macOS, display size and scale, Low Power and
  accessibility display settings; results appended to `perf-history/<date>.json`. Budgets: keystroke
  p95 < 33 ms, Return p95 < 33 ms, tab switch p95 < 50 ms, Space switch p95 < 100 ms, 10,000-block open
  < 2.5 s, search < 500 ms, index rebuild (10,000 blocks) < 3 s, 1,000-item collection open < 1 s and
  scroll p95 < 16.7 ms, panel open < 100 ms, Version History (30 versions, 2,000 blocks) < 500 ms,
  Vault Check (2,000 notes) < 2 s, migration check (2,000 notes) < 5 s, 10,000-block scroll p95 < 16.7 ms.
- *#1:* the same budgets at 10,000 and 20,000 blocks; block ids unchanged after typing, Return,
  formatting and moves; outline updates without rebuilding the document; content identical after
  relaunch.
- *#2:* the index never writes a note; rebuild from disk equals incremental updates; damaged or older
  index files are copied to `backups/` and rebuilt; results identical after relaunch; `"phrase"`,
  `/regex/`, `-word`, `#tag`, `tag:`, `date:`/`before:`/`after:`, `link:`, `in:title` and block-level
  results; rebuild of 10,000 blocks < 3 s and search < 500 ms.
- *#5:* ⌥⌘⇧← / → and the table menu move a column, one Undo restores it, cell ids, rich text, links,
  files and images survive, Markdown/HTML export keep the order, MCP review shows the table before and
  after; works in a narrow window and is announced by VoiceOver.
- *#3:* every string in menus, Settings, Assistant, review sheet, Trust & Recovery, tables,
  collections, onboarding, errors and accessibility labels is in `Localizable.xcstrings`; a check renders
  the main screens in Czech and German and fails on any English source string still visible; Czech
  plurals (one/few/other); dates and numbers through the system formatters; a spelling-language setting.
- *#4:* a test matrix (`docs/INPUT_MATRIX.md`) checks every shortcut on QWERTZ, AZERTY and Dvorak key
  maps and composition (marked text) in the editor: no early commit, Return/Enter commit the
  composition instead of splitting the block, slash menu and Markdown shortcuts wait for the commit,
  effects don't disturb marked text.
- *#7:* in-process accessibility audit of every v0.8/v0.9 screen: every control has a name, role and
  value; Tab order follows reading order; focus rings visible; animations off with Reduce Motion;
  stronger separators with Increase Contrast.
- *#9:* captures at the three sizes in light, dark and with Increase Contrast / Reduce Transparency /
  Reduce Motion; no clipped labels (checked on the German layout, the longest).

**Screenshots** (`docs/screenshots/v09/`): localized UI (Czech, German), narrow layouts, a
20,000-block note being edited, search results with block hits, table column reorder before/after,
Version History, Trust screens with keyboard focus, accessibility audit output.

**Result.**
- *#1:* 10,000 and 20,000-block notes (15,000 and 30,000 real blocks): keystroke p95 17 ms, Return p95 15 ms,
  scroll step p95 0.6 ms, open 0.5 s / 1.1 s, block ids unique after editing, outline memoized per saved
  revision (4 ms at 30,000 blocks, 0 ms cached). Folding a toggle recomputes only its children
  (tested against a full recompute). Known limit: a toggle at 30,000 blocks takes 250 ms (TextKit 1
  relays out everything below; non-contiguous layout was tried and rejected — it broke hidden-text
  heights).
- *#2:* `index/search.json` with full block text, tags, dates and links; query forms tested
  (`SearchIndexTests`, `search-perf`/`search-read` identical after relaunch); 10,000-block rebuild
  107 ms, query p95 87 ms; damaged copies kept in backups/; versioned; never writes a note.
- *#3:* String Catalog (`Localization/Localizable.xcstrings`, ~1,060 strings, Czech and German, plural
  forms cs one/few/other, de/en one/other), compiled into the app by `build-app.sh`; `l10n-sync.sh`
  extracts strings with the compiler; `l10n-check.sh` runs the app in en/cs/de at three sizes plus
  dark, reads the screens with on-device text recognition and fails on visible English or cut-off
  labels. Dates use the app's language with the person's region. Spelling-language setting in Editor.
  The sample notes created on first launch stay English (content, not interface).
- *#4:* `docs/INPUT_MATRIX.md` (47 shortcuts × US/QWERTZ/AZERTY/Dvorak from macOS's own layouts; only
  ⌘[ and ⌘] need Option on QWERTZ/AZERTY, which macOS remaps automatically); `IMETests` (Japanese,
  Chinese, Korean composition in Spectrum text, slash/Markdown triggers, a bold heading).
- *#5:* ⌥⌘⇧←/→/↑/↓ and the Table menu move columns and rows with one Undo, cell ids, rich text and
  links kept, Markdown export keeps the order, VoiceOver announces the new position. Fixed on the way:
  deleting a row or column could overwrite the neighbouring cell with the old field's text.
- *#6:* `scripts/budgets.sh` (3 runs, median judged, machine/display/accessibility report,
  `perf-history/`); all budgets pass.
- *#7:* `scripts/a11y-static.py` (no unnamed icon buttons, tap targets announced as buttons, motion
  through Motion) — 10 findings fixed; review sheet, Version History and Recovery labels localized.
- *#8:* repeated panel timing (cold, warm median, phases). Style/Format were never consistently slow
  (old single cold samples); the review sheet was (174 → 36 ms render: it re-read the note and rendered
  Markdown per block); Version History renders in 4 ms, its ~0.3 s on screen is AppKit's sheet animation.
- *#9:* captures at 720×640, 960×720, 1440×900, light and dark, in three languages; clipped Czech and
  German labels shortened; the History sheet fits its window.

**Manual checks still needed from you** (cannot be automated here): VoiceOver speech on the Trust and
v0.9 screens; Full Keyboard Access with real Tab presses; typing with a physical QWERTZ/AZERTY/Dvorak
keyboard and the real Japanese and Chinese input methods; reading the Czech and German text as a
native speaker.

## v0.11 — "Liquid Glass" (macOS) ✅ shipped

**Theme.** The editor's floating controls and the window chrome move to macOS Liquid Glass, and updates install reliably. 0.11.5–0.11.8, published on the in-app update channel and draft-notes.github.io.

| # | Feature | Status | Evidence |
|---|---|---|---|
| 1 | Recoverable updates and a DMG installer | ✅ | Authorization in protected locations, verify-before-replace, restore on failure (0.11.5) |
| 2 | Glass selection toolbar and block bar inside the editor | ✅ | Real refraction of the page behind them; bars step aside while typing; `docs/screenshots/ux-review-0.11.7/` (0.11.7) |
| 3 | Accent underline and Glow halo, same for manual and Assistant formatting | ✅ | `effects-shots`, light and dark (0.11.7) |
| 4 | Click the page background to stop typing | ✅ | Checked by hand (0.11.7) |
| 5 | Draft switches, glass top bar, liquid sidebar selector | ✅ | Checked by hand in light, dark and on an image backdrop (0.11.8) |

## v0.12 — "Liquid Glass everywhere" (macOS)

**Theme.** Finish the visual move: every surface that floats over the page or the backdrop is real Liquid Glass with one motion language, and it stays readable with Reduce Transparency, Increase Contrast and Reduce Motion.

| # | Feature | Status | Done when |
|---|---|---|---|
| 1 | Side panels (Format, Style, Info, Share) as glass sheets that slide in over the backdrop | ⬜ | Panels sample the backdrop; page never re-wraps (`PanelLayoutTests`); light, dark, image-backdrop captures |
| 2 | Tab strip and Assistant button in glass; tabs morph when opened, closed and reordered | ⬜ | Tab switch p95 stays < 50 ms (`budgets.sh`); drag-reorder animates |
| 3 | Slash menu, `[[` / `@` pickers and Quick Open as glass popovers | ⬜ | Keyboard paths unchanged; selection kept; captures in both themes |
| 4 | One motion system: shared springs for bars, panels, selector, switches, sheets | ⬜ | Every animation reads from one place; Reduce Motion turns all of them into fades (test) |
| 5 | Accessibility fallbacks for glass | ⬜ | Reduce Transparency gives solid surfaces, Increase Contrast adds borders; captures with each setting on |
| 6 | Glass block handle and drag preview: the block lifts, others make room, a glowing drop line | ⬜ | Drag a block in a 10,000-block note within budget; one Undo |
| 7 | Glass controls kit: segmented pickers, sliders, steppers and menus in the Draft style, used in every panel | ⬜ | No system-default control left in Style, Format, Info, Share and Settings |
| 8 | Sidebar in glass over the window backdrop, with the liquid selector for Library / Document | ⬜ | Readable over every style; selector press-and-slide works |
| 9 | Context-aware formatting bar: shows table, list, image or link tools for what is selected | ⬜ | Each kind of selection has its own row; keyboard ⌥F10 still reaches every item |
| 10 | Haptics on Force Touch trackpads for snaps (selector landing, block drop, switch flip) | ⬜ | Off when the system setting is off |

## v0.13 — "Images & media" (macOS)

**Theme.** Images, scans and sketches behave like first-class blocks: they land where you expect, at a sensible size, look right in light and dark, and can be adjusted without leaving the note.

| # | Feature | Status | Done when |
|---|---|---|---|
| 1 | Predictable insertion: paste, drop, picker and iPhone capture all insert at the caret (or the drop line), never replacing the selection or jumping the page | ⬜ | Same result for every source; one Undo; the caret ends after the image; scroll position kept |
| 2 | Sensible default size: small images at their real size, large photos fit the page, retina images at point size | ⬜ | Rule tested with 1×, 2× and 12 MP images; no upscaling blur |
| 3 | Drag-to-resize handles and alignment (left, centre, right, full width) with a live size readout | ⬜ | Snaps to S/M/L/Full; one Undo per drag; keyboard alternative in the image bar |
| 4 | iPhone sketches as ink: the paper background is removed, the drawing is trimmed to its strokes, and the ink follows light and dark mode | ⬜ | A Continuity Camera sketch reads well on Paper, Night Ink and an image backdrop; the original is kept |
| 5 | Vector sketches: strokes captured as vectors where available, so sketches stay sharp at any size and stay editable | ⬜ | Zoomed sketch stays crisp; strokes can be recoloured and erased in the sketch block (see v0.15) |
| 6 | Scan cleanup: document scans auto-cropped, straightened and contrast-boosted; multi-page scans become one PDF block with page thumbnails | ⬜ | Text recognition (on-device) makes scanned text searchable |
| 7 | Crop, rotate, flip and simple adjustments (exposure, contrast, black & white) in a glass editor, non-destructive | ⬜ | Original asset untouched; edits stored as parameters; exports use the edited version |
| 8 | Image galleries: several images side by side or in a grid block, rearranged by dragging | ⬜ | Grid reflows in narrow windows; each image keeps caption and alt text |
| 9 | Quick Look and full-screen viewer with arrow keys through all images in the note | ⬜ | Space opens Quick Look; Esc closes; VoiceOver reads alt text |
| 10 | Live Text and on-device image description: select text in images, copy it, find it in search; suggested alt text | ⬜ | Suggestions are proposals, never applied silently; nothing leaves the Mac |
| 11 | Image formats and size: HEIC, WebP, animated GIF, SVG; large images stored once, downscaled previews cached | ⬜ | A note with 200 photos opens within budget; vault check finds unused images (existing cleanup) |
| 12 | Video and audio blocks: play inline, poster frame, voice memos recorded straight into a note | ⬜ | Recording needs the microphone prompt only when used; files saved in the vault |

## v0.14 — "Capture anywhere" (macOS)

**Theme.** Getting a thought into Draft should take one keystroke from anywhere on the Mac, without opening the window first. All local: no account, no network.

| # | Feature | Status | Done when |
|---|---|---|---|
| 1 | Quick Capture: a global shortcut opens a small glass capture window; append to today's note or a chosen note | ⬜ | Works with Draft in the background; text lands with one Undo; shortcut configurable |
| 2 | Menu bar extra: today's tasks, recent notes, new note, quick capture | ⬜ | Optional (off by default); keyboard reachable |
| 3 | Share extension ("Send to Draft") from Safari, Mail, Finder and other apps: links, text, images, files | ⬜ | Shared items land as link cards, quotes or attachments in the chosen note |
| 4 | Shortcuts / App Intents: create note, append to daily, add task, search, open note | ⬜ | Each intent runs from the Shortcuts app and Spotlight; tested with a throwaway vault |
| 5 | Spotlight search of notes (Core Spotlight, on-device) | ⬜ | A note found in Spotlight opens at the matching block; index removed when turned off |
| 6 | Desktop widgets: today's note, tasks due, a pinned note | ⬜ | Update within a minute of an edit; light and dark |
| 7 | Screenshot to note: capture a screen region straight into the current note | ⬜ | Uses the system capture UI and its permission; lands as an image block |
| 8 | Web clipping: a page's article text, title and link saved as a note (from the share extension) | ⬜ | Clean text without ads or scripts; original link kept |
| 9 | Templates for capture: meeting, idea, reading note — chosen in the capture window | ⬜ | Uses the existing template system |
| 10 | Dictation into Quick Capture with the on-device recognizer | ⬜ | Works offline; microphone prompt only when first used |

## v0.15 — "Thinking tools" (macOS)

**Theme.** Blocks for the kinds of thinking plain text can't hold, rendered offline and exported faithfully.

| # | Feature | Status | Done when |
|---|---|---|---|
| 1 | Math: inline `$…$` and block `$$…$$` formulas | ⬜ | Renders offline; edit in place; exports to HTML/PDF and stays `$$…$$` in Markdown (FEATURE_PARITY E10) |
| 2 | Mermaid diagrams as a block | ⬜ | Bundled renderer, no network; live preview; PNG/SVG in exports (A6) |
| 3 | Sketch block: draw with mouse, trackpad or an iPhone sketch, pen/marker/eraser, colours, lasso, editable later | ⬜ | Strokes stored as vectors in the note; exported as an image (A6) |
| 4 | Whiteboard page: an infinite canvas with notes, images, sketches and arrows | ⬜ | Pans and zooms smoothly with 500 items; content searchable |
| 5 | Margin notes: private comments on a word or block | ⬜ | Shown in the margin and in a Comments pane; never exported unless asked (R3, local-only) |
| 6 | Card sizes and previews for linked pages | ⬜ | Small/medium/large and image/text previews (P2) |
| 7 | Assistant writing suggestions in the selection bar (local model first) | ⬜ | Rewrite/shorten/expand proposals go through the review sheet; nothing sent without opt-in (J3) |
| 8 | Graph view of links between notes | ⬜ | Opens a note on click; filters by tag and Space; 2,000 notes within budget |
| 9 | Kanban and calendar views for collections, beside table and list | ⬜ | Drag between columns updates the field; one Undo |
| 10 | Formulas in tables and collections (sum, average, count, dates) | ⬜ | Recalculates on edit; exported as values |
| 11 | Code blocks with syntax highlighting, line numbers and copy | ⬜ | 20 common languages; colours follow the style |
| 12 | Footnotes and a table of contents block | ⬜ | Numbered automatically; exported to HTML/PDF/Markdown |

## v0.16 — "Share what you write" (macOS)

**Theme.** Get work out of Draft the way people actually share it, still without an account or a Draft server.

| # | Feature | Status | Done when |
|---|---|---|---|
| 1 | Static site export of a folder (with links, styles, search) | ⬜ | The export opens offline in a browser and on any static host (U1, static first) |
| 2 | Share sheet and "Open in…" for notes as PDF, Markdown or HTML | ⬜ | Works from the Share panel and right-click (X7) |
| 3 | Book-style PDF: several notes in order with a contents page | ⬜ | Page numbers, headings in the contents, styles kept |
| 4 | Custom vault location with a safe move and undo | ⬜ | Move verified file by file; old folder kept until the new one opens (Y3) |
| 5 | Sidebar customisation: reorder and hide sections, pin notes and folders | ⬜ | Persists per Space (Z6) |
| 6 | Website follows releases: download page and changelog update when a release is published | ⬜ | A GitHub Action builds draft-site and deploys draft-notes.github.io; "Coming soon" kept for builds that aren't notarized if chosen |
| 7 | Import from Apple Notes, Notion, Obsidian and Bear exports with a preview | ⬜ | Images, links and tasks kept; duplicates flagged (existing import preview) |
| 8 | Export to DOCX and EPUB | ⬜ | Headings, lists, images, tables kept; opens in Pages and Books |
| 9 | Print layouts: margins, headers and footers, page breaks honoured | ⬜ | Matches the PDF export |
| 10 | Encrypted notes and folders (password or Touch ID), still plain files when unlocked | ⬜ | Locked notes unreadable on disk; never in search or Spotlight while locked |

**Order.** v0.12 first (it finishes work already started and touches every screen later features build on), then v0.13 Images & media (the most visible everyday rough edge), v0.14, v0.15, v0.16. Notarization (v1.0 gate) can land at any point once a Developer ID certificate exists.

## Manual checks carried forward (need a person; not forgotten)

| Check | From | Status |
|---|---|---|
| Native-speaker review of the Czech and German translations | v0.9 #3 | ⬜ open |
| Real keyboards: QWERTZ, AZERTY, Dvorak (typing and every shortcut in `docs/INPUT_MATRIX.md`) | v0.9 #4 | ⬜ open |
| Real input methods: Japanese, Chinese, Korean (composition, candidate window, Return) | v0.9 #4 | ⬜ open |
| VoiceOver on the v0.8 Trust & Recovery screens | v0.8 | ⬜ open |
| Full VoiceOver / accessibility-tree audit (`swift scripts/ax-audit.swift`, needs Accessibility permission for the terminal) | v0.9 #7 | ⬜ open |
| macOS Reduce Motion turned on: panels fade, Spectrum still, no slide animations | v0.9 #9 | ⬜ open |
| Folding a toggle in a 30,000-block note (250 ms today; TextKit 1 limit) | v0.9 #1 | ⬜ known limit |

## v1.0 groundwork — Release, Trust and Quality of Life (started 13 Nov 2026)

One connected batch on `feature/v1.0-groundwork`. Rules: no network request the person didn't ask for
(update checks are off by default, telemetry doesn't exist); every test on a throwaway vault; the
installed app is replaced only after the whole batch passes.

| # | Feature | Status |
|---|---|---|
| 12 | Version and migration policy (`docs/VERSIONING.md`) | ✅ complete |
| 1 | Signed and notarized distribution (`scripts/release.sh`, `scripts/verify-release.sh`, hardened runtime, entitlements, `docs/RELEASE.md`) | 🟨 partial: signed (Apple Development) with hardened runtime, verified and launches; notarization and stapling scripted but need a Developer ID and notary credentials |
| 2 | Secure opt-in updates (Ed25519-signed feed over HTTPS, verified download, install now / on quit / later, rollback, vault-compatibility warning, test mode) | ✅ implementation complete; stable 0.11.5 is hosted and updater suite passes. Real protected-location authorization/relaunch is awaiting the beta check |
| 3 | Release channels (stable default, beta, development; confirmation to switch; development builds never replace stable) | ✅ complete |
| 4 | Onboarding and first run (welcome, tour, first note, model setup, import, vault folder, local-only and network explanations, What's New after updates) | ✅ complete |
| 5 | Help center (searchable topics, each linking to its setting or action) | ✅ complete |
| 6 | Report a Problem (local report, redacted diagnostics, reviewed before saving; nothing is sent) | ✅ complete |
| 7 | Crash and recovery experience (unclean-exit detection, last save, recover, read-only, Safe Mode, logs, report; fault injection tests) | ✅ complete (`scripts/fault-test.sh`, limits in the script header) |
| 8 | Privacy center (every permission and network feature with what it does and how to turn it off) | ✅ complete (`docs/PRIVACY.md`) |
| 9 | Data portability (backup archive with manifest and restore, import preview with duplicates, export, “copy my data”) | ✅ complete |
| 10 | Daily quality of life (consistency audit: save state, recent documents, command search, empty states, messages) | 🟨 partial: save state, Quick Open with commands, shortcut lists and confirmations already exist; no full screen-by-screen audit in this batch |
| 11 | Release and CI gates (`scripts/release-check.sh`, GitHub Actions for what runs headless) | ✅ complete (CI not yet run on GitHub) |

**Updater decision.** Sparkle 2 (MIT) is the standard; it expects a Developer ID–signed app and a
binary dependency that wasn't approved for download here. Draft uses a small built-in updater instead:
a JSON feed signed with Ed25519 (CryptoKit), HTTPS only, the download's size, SHA-256 and signature
checked, the new app's code signature and bundle id checked, then a swap that keeps the old app until
the new one launches (rollback otherwise). The feed format is documented so moving to Sparkle later is
a drop-in replacement of `UpdateController`.

**Acceptance.** Signed build verifies (`codesign --verify --deep --strict`, hardened runtime flag);
notarization and stapling run when the secrets in `docs/RELEASE.md` are present (they are not on this
Mac: no Developer ID certificate); the updater installs a signed test update and refuses a tampered
one; a failed install rolls back; updates can be deferred and disabled; with checks off the app makes
no update request (test); onboarding from a clean vault; What's New after a version change;
diagnostics contain no note text, titles or paths (test); crash recovery keeps originals (fault
injection); Safe Mode writes nothing; a backup archive restores to identical files; Czech and German
uncut; all budgets pass.

**Screenshots** (`docs/screenshots/v10/`, light, dark, narrow): update available, release notes,
update settings, onboarding, What's New, Help, Report a Problem, Privacy, Crash Recovery, Safe Mode,
backup archive, import preview.

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
