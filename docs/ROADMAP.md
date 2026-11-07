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

## v0.1 — "First light" (current milestone, macOS) ✅

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

## v0.2.1 — "Writer's desk, continued" (macOS)

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

**Gate.** 10,000-block document keystroke latency < 16 ms p95 on M1; every new block type
round-trips through Markdown export and import.

## v0.3 — "Linked thinking" (macOS)

- ⬜ `[[` / `@` link picker for documents and blocks; block references that survive moves.
- ⬜ Backlinks pane; tags (`#tag`) with autocomplete, colors, results view, ignore rules (hex/numeric/custom).
- ⬜ Daily notes; Calendar stream (Today, upcoming, Add Task, Create Daily Note); global Tasks view
  (Today/Upcoming/Overdue/Completed) with due dates and reminders (local notifications).

**Prerequisites.** Persistent link/tag/task index derived from block ids. **Gate.** Renaming or moving
a target never breaks a link; toggling a task in Tasks view updates the source block with one undo.

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

*(updated after v0.2)*

1. **Callout, toggle list and page-break blocks** with their Markdown triggers (+ the remaining
   separator variants and the `x ` task trigger).
2. **Move blocks to another document** (block menu → Move to…), reusing the group-into-page path.
3. **Performance pass**: incremental moves and a measured 10k-block budget.
4. **Tab state across restarts** (scroll and caret per tab).
