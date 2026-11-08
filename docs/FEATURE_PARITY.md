# Feature parity and gap matrix

Tracks Craft-like capabilities (the reference studied in the research brief) against Draft's
**actual** status on macOS. It records behavior and workflow coverage, never copied assets.

**Evidence keys** — `B§x`: section of `craft-inspired-notes-app-research-brief.md`. `S01`…`S42`:
native screenshots `craft-macos-ui/NN-*.png` (kept **outside** this repo — they contain personal
content). `?` = reference behavior not confirmed by evidence; not a parity target until verified.

**Status** — `missing` · `partial` (gaps named) · `working` (implemented and exercised in the running
app or screenshots) · `verified` (covered by `swift test` or `scripts/smoke.sh`).

Platform: all statuses are for the native macOS app. Windows: see §22.

Last updated: v0.4 shipped (native macOS) — 2026‑11‑08.

## 1. Editor primitives and keyboard

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| E1 | Text block as default atom | Open and type | B§1, B§5.3 | verified | — | 0.1 | New doc → typing → paragraph with id (`testTypingPersistsIntoDocument`) |
| E2 | Stable block ids | Addressable blocks | B§4, B§B | verified | — | 0.1 | Missing/duplicate ids repaired, first wins; ids survive save/load (`BlockIdTests`, `ConverterTests`) |
| E3 | Enter rules | Heading→paragraph; empty item exits list; split keeps first id | B§5.3 | verified | E1 | 0.1 | `testEnterAfterHeading…`, `testSplitInMiddle…`, `testListTriggersEnterAndExit` |
| E4 | Backspace rules | Merge into previous; list item un-lists/outdents first | B§5.3 | verified | E1 | 0.1 | `testBackspaceAtStartOfBullet…`, `testBackspaceMergeKeepsPreviousBlock` |
| E5 | Soft break | Shift+Return | B§5.3 | working | — | 0.1 | Shift+Return inserts a line break exported as `hardBreak` |
| E6 | Undo / redo | Formatting, moves, deletes | B§8 | verified | — | 0.1 | `testToggleBold…Undo`, `testFindReplaceAllIsOneUndo` |
| E7 | Markdown block triggers | `#`…`####`, `-`/`*`, `1.`, `[]`/`x `, `[x]`, `>`/`|`, `+ ` toggle, ``` | B§G | verified | — | 0.2.1 | All listed triggers convert; undo restores the literal text (`testMarkdownHeadingTrigger…`, `testXTriggerMakesTask`, toggle test) |
| E8 | Separator triggers | `---` regular; `=--` strong, `.--` dotted, `..-` three-dot, `===` page break | B§G | verified | — | 0.2.1 | Each trigger creates the matching separator or page break (`testSeparatorVariantsAndPageBreak`); page breaks start a new page when printing / saving PDF |
| E9 | Inline Markdown | `*i*` `**b**` `~~s~~` `==h==` `` `c` `` | B§G | verified | — | 0.1 | `testInlineMarkdownBold`; typing after the delimiter is plain |
| E10 | Equations `$$x$$` | Inline math | B§G, S06 | missing | renderer | later | `$$a^2$$` renders as formula and exports as `$$…$$` |
| E11 | Slash menu | Filter, arrows, Return, Esc | B§5.3 | verified | E-cmds | 0.1 | `/check` + Return → checklist (`testSlashMenuInsertsChecklist`) |
| E12 | `+` insert menu | Image, File, Code, Formula, Mermaid, Whiteboard, Table, Collection, Page Break | S34 | partial | — | 0.2.1→0.5 | Image, File, Page, Card, Separator, Page Break, Code, Checklist, Quote work; Table/Collection (v0.5), Formula/Whiteboard (later) listed disabled with version |
| E13 | Indent / outdent | Tab / Shift-Tab | B§8 | verified | — | 0.1 | `testTaskTriggerTabNestingAndToggle` |
| E14 | Block handle + drag reorder | Gutter handle, insertion line | B§5.3, S01 | verified | E15 | 0.2 | ⋮⋮ handle on hover; drag shows insertion line, autoscrolls; drop moves selected blocks (`testDragDropBoundaryMapping`); one undo |
| E15 | Block selection | Distinct from text selection | B§5.3 | verified | — | 0.2 | Esc selects block, ⇧↑/↓ extend, ↑/↓ move, Delete removes, typing/Return exits; ⌘C copies blocks (`testEscSelectsBlock…`) |
| E16 | Group into page ⌘G / ungroup ⇧⌘G | Tree transform | B§B, S42 | verified | E15 | 0.2.1 | First block becomes the page title and the card keeps its id; other blocks keep ids, marks, checkboxes; nested pages move along; undo/ungroup set the page aside (not into Recently Deleted) and redo restores it; ungroup restores the original blocks exactly (`GroupTests`, smoke `pageTitle`/`ungroupedGone`) |
| E23 | Block context menu | Turn into, duplicate, copy link, group, move, delete | S42, B§5.4 | verified | E15 | 0.2.1 | Right-click/⌃-click on the ⋮⋮ handle or Block submenu in the text menu; items run shared commands (`testDuplicateAndCopyLinkAndMenu`) |
| E24 | Block links `draft://open?doc=…&block=…` | Copy link to block | B§5.6 | verified | E2 | 0.2.1 | Copy Link to Block; opening the link (from Draft or another app) opens the doc at that block (smoke `linkOpened`) |
| E25 | Move blocks to another document | Move to new Document(s) / Move to Daily Note | S42 | verified | E15 | 0.3 | Block menu → Move to: New Document (⌥⌘N), Today’s Daily Note, or one of 15 recent docs; blocks keep ids and marks; new document / daily note leave a page card; one undo takes them back (`testMoveToNewDocumentAndTodayLeaveCards`, smoke `movedTo`) |
| E17 | Move up/down/top/bottom | Shortcut actions | S42 | verified | E15 | 0.2 | ⌥⌘↑/↓, ⌃⌥⌘↑/↓; ids, marks, task state preserved; one undo each (`testMoveUpDown…`) |
| E18 | Paste | Rich, plain, Markdown | B§5.3 | verified | — | 0.2 | Multi-line text → one block per line, Markdown recognized; RTF/HTML → headings, lists, bold/italic/underline/strike/code/links; Draft→Draft keeps blocks+marks with new ids; surrounding block keeps id; one undo (`PasteTests`, `MarkdownImportTests`) |
| E19 | Multi-block text selection | Beta in reference | S12 | working | — | 0.1 | Drag across paragraphs selects text in all (native TextKit) |
| E20 | IME / non-US layouts | Fixes documented | B§7, B§8 | partial | — | 0.6 | NSTextView composition works; layout matrix untested |
| E21 | 10k-block performance | Quality gate | B§11 | partial | — | 0.2.1→0.8 | `scripts/perf.sh` (10,000 blocks, real app): keystroke 7 ms p50 / ~20 ms p95, Return ~13 ms, block move ~14 ms, save ~0.3 s, open ~2.1 s, search past the index limit ~0.15 s. Limits: a keystroke that changes line wrapping and a toggle near the top (~120 ms) relayout everything below (TextKit 1 contiguous layout; non-contiguous layout mis-measures collapsed toggles) |
| E22 | Spellcheck | Native | S11 | working | — | 0.1 | Continuous spellcheck on in editor |

## 2. Inline and block formatting

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| F1 | Selection toolbar | Translucent pill above selected line | S06 | verified | — | 0.1 | Select text → bar visible (`testPaletteKeepsSelection…`); screenshot `selection-toolbar.png` |
| F2 | Flip / clamp | Flip near top; clamp in canvas | S06 notes | verified | F1 | 0.1 | `testToolbarFlipsBelowNearTopAndClamps` |
| F3 | Toolbar controls | Highlight▾, B, I, S, code, link, equation, @, comment, suggestions, feedback | S06 | partial | F1 | 0.1 | Highlight▾/B/I/U/S/code/link/clear work; equation (E10), @ (L1), comment (R3), suggestions (J3) not shown |
| F4 | Active states | From selection | S06 | working | F1 | 0.1 | Bold selection shows B active (`isMarkActive`), accessibility value "on" |
| F5 | Inline color palette in place | Clear + pastels + saturated | S07 | verified | F1 | 0.1 | ▾ swaps bar to palette; swatch applies (`testPaletteKeeps…`); `color-palette.png` |
| F6 | Selection preserved through palette/link | — | S07 | verified | F5 | 0.1 | Selection range unchanged after choosing color (test) |
| F7 | Keyboard access + Esc | — | prompt | partial | F1 | 0.1→0.6 | Esc dismisses (`testEscapeDismissesToolbar`); ⌥F10 focuses bar, ←/→/Return/Esc work; VoiceOver pass pending (Y15) |
| F8 | Reapply last color ⌘⇧B | Documented | B§G | verified | F5 | 0.1 | Test applies same color to a new range |
| F9 | Underline / strike / code marks | Inline | B§7 | working | — | 0.1 | ⌘U, ⌘⇧X, ⌘E via Format menu |
| F10 | Text color vs highlight | Separate | B§7 | working | — | 0.1 | Palette: pastel squares = highlight, circles = text color |
| F11 | Links | Add/edit/remove | S06 | working | — | 0.1 | ⌘K opens link field in the bar; ⌘-click opens URL externally |
| F12 | `Aa` Titles/Content | Title, Subtitle, Heading / Strong, Body, Caption | S05 | working | cmds | 0.1 | `format-panel.png`; active state follows caret |
| F13 | `Aa` Groups Page/Card | Turn block into page/card | S05 | working | E16 | 0.2.1 | Page/Card switches a page block's presentation or inserts a new page; existing blocks become a page with ⌘G |
| F14 | `Aa` marks/lists/indent/align | Disabled when not applicable | S05 | working | — | 0.1 | Buttons use command `isEnabled` |
| F15 | Decoration Focus / Block | Bar or filled block | S05 | working | — | 0.1 | Focus draws accent bar; Block fills background |
| F16 | Block color | Swatch grid | S05 | working | F15 | 0.1 | Stored as `blockColor` attr, drawn by layout manager |
| F17 | Toggle list | `+ ` | B§G, S05 | verified | — | 0.2.1 | ▶/▼ marker (click or ⌘↩) collapses children, which are hidden from layout but kept in the file (`open` attr); caret skips hidden text; undoable; survives reload (`testToggleCollapse…`) |
| F18 | Callout | Block | B§7 | verified | — | 0.2.1 | Slash / `Aa` → Callout; icon + tinted box spanning its paragraphs; Return continues, empty Return exits; block color applies; exports as a quote with the icon (`testCalloutContinuesExits…`) |
| F19 | Code block | ``` | B§7 | working | — | 0.1 | Monospace, background; Return adds lines, Return on empty last line exits; no syntax highlighting |
| F20 | Per-block font | Format panel bottom | S05 | verified | — | 0.4 | Format → Block Font (Doc/System/Serif/Mono/Rounded) and Format menu; wins over the document font; code stays mono; HTML export; one undo (`StyleEditorTests`, style test) |

## 3. Nested pages and cards

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| P1 | Nested page | Block becomes a page | B§B, B§5.4 | working | — | 0.1 | `/page` or `/card` creates child doc and opens it in place; card click opens; `nested-page.png` |
| P2 | Card presentation | Visual treatment of same model | B§D | partial | P1 | 0.1→0.4 | Card vs page row; sizes and preview modes missing |
| P3 | Card preview modes | Standard, emoji, book, sticky, gallery | B§D | verified | P2 | 0.4 | Sizes compact/medium/feature and previews standard/icon (monogram)/gallery (cover); stored on the card, exported (`testCardSizeAndPreview…`, style test). Emoji/book/sticky looks not built |
| P4 | Breadcrumb / back | Ancestry; back restores parent | B§5.4 | working | P1 | 0.1 | Child shows `Folder › Parent`; Back returns within tab |
| P5 | Outline lists pages | TOC lists headings and pages | S01 | working | P1 | 0.1 | Outline shows page rows; click opens |
| P6 | Recoverable deleted pages | Reference: nested pages not in Recently Deleted | B§B | verified | H4 | 0.2 | Deleting a doc trashes its nested pages too; restore brings them back with structure; a page whose parent stays deleted returns top-level (`TrashTests`) |

*Draft decision:* nested pages are child documents (`parentDocId`) referenced by a `pageCard` block.

## 4. Themes, covers, backdrops

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| T1 | Style panel | Preview, All Styles, Tailored, Backdrop, Doc/Text color, Cover, Separator, Font, Advanced | S02 | working | — | 0.1 | `style-panel.png`; "Tailored" = overrides shown in preview name + Reset |
| T2 | Built-in styles | 100+ presets | S03, B§C | working | T1 | 0.4 | 13 original styles (6 new in v0.4), all ≥ 4.5:1 contrast (`testPresetsAreReadable…`) |
| T3 | Style Gallery | Searchable modal, 3 columns | S03 | working | T2 | 0.4 | My Styles + Draft Styles, search, live preview pane with contrast and Apply (`v04-style-gallery.png`) |
| T4 | Save / default / pin styles | User styles | B§C | verified | T2 | 0.4 | Save, duplicate, rename, pin, delete (falls back to base), use for new documents; survives relaunch (style test, `StyleStudioTests`) |
| T5 | Backdrop solid | Palette | B§C | working | — | 0.1 | Backdrop popover → Solid |
| T6 | Backdrop gradient | Start/end/direction | B§C | verified | — | 0.4 | Start/End color wells and direction slider, live; round-trips and exports (style test) |
| T7 | Backdrop image, shuffle, upload, blur, Immersive/Faded | S04 | S04 | working | assets | 0.4 | 12 original offline scenes, Shuffle, Upload, Blur, Immersive/Faded; opt-in Openverse search (off by default, asks first); live check in v0.5: 18 results, one downloaded and stored as an asset, no requests while off (`online-live` automation) (`v04-backdrop-library.png`) |
| T8 | Page color and text color independent | Separate layers | B§C | working | — | 0.1 | Changing one leaves the other |
| T9 | Contrast warning / adjust | Warn + auto adjust | B§C | verified | T8 | 0.4 | Warning < 4.5:1 with "Adjust text color (x:1 → y:1)", hue kept (`testReadableColor…`, `v04-contrast-adjust.png`) |
| T10 | Cover image | Upload, crop ratios, reposition, remove | B§C | verified | assets | 0.2.1 | Upload; hover pencil/X (also Style → Crop…/Remove); crop sheet with Original, 16:9, 2:1, 3:1, 4:3, Free, drag to move, corner to resize, arrow keys; the crop is stored as a rect + ratio, never baked into the image (`CoverCropTests`; visual check at 1440 and 720 pt) |
| T11 | Separator styles | Line, tape, doodle | S02, B§C | working | — | 0.1 | Line / Dots / Tape / Wave (original artwork), document-wide |
| T12 | Fonts System/Serif/Mono/Rounded | Families | S02, B§C | working | — | 0.1 | System font designs; document-only |
| T13 | Shell tinted by doc style | Appearance setting | S10 | working | — | 0.1 | Rail/tabs tint (`document-ember.png`), toggle in Settings and Style panel |
| T14 | Present mode | Info → Present | S41 | missing | — | 0.6 | Listed disabled in Info |
| T15 | Style independent of semantics | — | B§G | verified | — | 0.1 | `testThemeChangeDoesNotChangeContent`, `testOverridesLayerOnStyle…` |

## 5. Sidebar, tabs, spaces, folders

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| N1 | Full-height rail | Space, destinations, Starred, Folders, Tags, utilities | S21 | working | — | 0.1 | `library-gallery.png` (local "Stored on this Mac" card replaces plan card) |
| N2 | Document rail + 4-segment control | Thumb, title, time; Outline/Tasks/Attachments/Find | S01, S18–20, S35 | working | — | 0.1 | `document.png`, `document-tasks-rail.png`, `document-find.png` |
| N3 | Rail mode menu | Folders / Document; Focus mode | S08 | partial | — | 0.6 | Folders/Document switch works; Focus mode missing |
| N4 | Collapse rail | — | S01 | working | — | 0.1 | ⌃⌘S; persisted |
| N5 | Tab strip | Home + tabs, close, + | S01, S21 | verified | — | 0.1 | Open doc tab survives restart (smoke `tabOpen`) |
| N6 | Tab state restore | Scroll/caret per tab | B§5.5 | verified | — | 0.2.1 | Each document tab stores scroll offset and selection (captured on tab switch and quit); restored once when the tab reappears after relaunch (smoke `tabState`) |
| N7 | Back / forward | Back button in doc | S01 | verified | L1 | 0.3 | ⌘[ / ⌘] (Go menu) per tab with scroll per entry; follow → back → forward (links test) |
| N8 | Spaces | Switcher, per-space tree | B§4, S13 | working | schema 2 | 0.5 | Rail switcher and Settings → Space: create, switch, delete (empty only); each Space keeps its own folders, documents, tags, tasks and tabs; templates and styles are shared. Unsaved text survives a switch; tabs restore after relaunch (`scripts/workflow-test.sh`, `SchemaTwoTests`, `v05-settings-spaces.png`) |
| N9 | Folders | Create/rename/nest/delete | S21, S30 | partial | — | 0.2 | Create, rename, remove (docs → Unsorted); nesting missing |
| N10 | Move doc to folder | Info → Move to | S41 | working | N9 | 0.1 | Info panel and card context menu |
| N11 | Unsorted view + empty state | Message + skeletons | S29 | working | — | 0.1 | Empty-state message and placeholder rows |
| N12 | Starred | — | S21, S41 | working | — | 0.1 | Star in Info/context menu; shows in rail |
| N13 | Shared with Me | Empty view | S31 | partial | R2 | 2.0 | Honest local-only empty state |
| N14 | Drag doc to folder | — | B§5.5 | missing | — | 0.2 | — |

## 6. Search, Quick Open, Find in Page

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| S1 | Library inline search | Expands in header | S26 | verified | — | 0.2 | All terms, case/diacritic-insensitive; documents longer than the 50,000-character index are searched in full (`testLongDocumentsAreSearchedPastTheIndexLimit`, perf `searchHits`) |
| S2 | Quick Open ⌘O | By name; create new | B§H | working | — | 0.3 | Documents by name, then blocks containing every typed word (from the index), then "Create …" (`v03-quick-open.png`) |
| S3 | Space Search with counts + jump | One result per doc | B§H | verified | — | 0.2 | All terms, case/diacritic-insensitive, title matches first, match-count badge, highlighted snippet; Return/click opens the doc with Find in Page filled and the first match scrolled into view (`SearchTests`, smoke `jumpVisible`) |
| S4 | Find in Page ⌘F | Rail pane, next/prev | S35, B§H | working | — | 0.1 | Highlights all, current stronger; ⌘G/⇧⌘G |
| S5 | Replace | — | B§H | verified | S4 | 0.1 | Replace all is one undo (test) |
| S6 | Phrase / exclusion / regex | macOS options | B§H | verified | S3 | 0.3 | `"red bag"` exact, `train -vienna` excludes, `.*` toggle for regex; invalid regex → red field + inline error (`testSearchOptions`, `v03-search-regex-error.png`) |

## 7. Tasks, calendar, daily notes, reminders

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| K1 | Checklist block | `[] ` | B§G | verified | — | 0.1 | Trigger + click toggle (`testTaskTrigger…`) and smoke test |
| K2 | Document Tasks pane | Tasks in doc | S18 | working | K1 | 0.1 | Lists, counts, toggles source block |
| K3 | Global Tasks view | Today/Upcoming/etc. | B§5.7 | verified | index | 0.3 | Inbox/Today/Upcoming/Overdue/Completed with counts; completing updates the source block (editor and file) and one undo reverts it (links test) |
| K4 | Due dates / reminders | Date on task | B§5.7 | partial | K3 | 0.4 | `@tomorrow 3pm` and the Tasks date/time picker set the due date; reminder scheduled at that time; one undo (links test). Real permission prompt not exercised |
| K5 | Daily notes | One page per date | B§5.7, S33 | verified | index | 0.3 | ⇧⌘D opens today; opening twice never creates two notes (also after relaunch); previous/next/Today in the top bar; template; start-of-day setting (links test, `LinkingTests`) |
| K6 | Calendar stream | Day cards, Add Task, Create Daily Note, filters | S33 | verified | K5 | 0.4 | Today highlighted; Add Task on a future day is due that day; filters persist across relaunch; Today/Overdue roll over while idle (links test) |
| K7 | Completed-task appearance | Setting | S12 | working | — | 0.1 | Strikethrough / Dimmed / Unchanged |

## 8. Tags, links, backlinks

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| G1 | Tags `#tag` | Inline, autocomplete | B§5.6, S17 | verified | index | 0.3 | `#` picker lists existing tags with counts; colored inline; sidebar Tags list; tag view lists every tagged block; per-tag color (`LinkTests`, `v03-tag-view.png`) |
| G2 | Tag ignore rules (hex, numeric, custom) | Settings | S17 | verified | G1 | 0.3 | `#fff`, `#a1b2c3`, `#1` ignored by default; custom words in Settings → Tags; changing rules re-indexes (`testTagRules`, `testRefreshIsIncremental…`) |
| G3 | Backlinks | Pages linking here | B§5.6 | verified | L1 | 0.3 | Rail segment, grouped by source document, one row per block; appears 0.52 s after the link is typed; click opens the source at the block (links test) |
| L1 | Doc/block links (`[[`, `@`) | Link picker | B§G | verified | E2 | 0.3 | `[[` documents, nested pages, blocks, "New document"; `@` dates and documents; chips keep live titles through rename, move, group, relaunch and index rebuild; missing targets shown struck through and recover; relative links in Markdown export (links test, `LinkTests`) |

## 9. Tables and collections

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| C1 | Simple table | Insert menu | S34 | working | — | 0.5 | `/table` or Insert → Table; click a cell to edit; Tab/⇧Tab/Return move, ⌥⌘↓ adds a row, ⌥⌘→ a column, ⌥⌘⌫/⌦ remove; each committed cell is one undo; Markdown pipe tables round-trip (`TableTests`, `StructureTests`, `v05-table-editing.png`). Rows reorder by command; no column reordering or rich text inside cells yet |
| C2 | Collections + field types | Records are pages | B§I | working | schema 2 | 0.5 | Text, number, select, multi-select, date, checkbox, relation, URL; each item is a nested page that keeps its id after relaunch; 1,000 items open in ≈ 0.1 s (`scripts/structure-test.sh`). Relation picker lists the first 40 documents by title (no search yet) |
| C3 | Table / Gallery / Kanban views | Shared records | B§I | working | C2 | 0.5 | Per-view sort, filters, group-by and visible fields persist; Kanban drag changes one value of one record and is one undo; drag also has VoiceOver "Move to" actions; 1,000-row table scroll p95 ≈ 5 ms (`v05-collection-*.png`) |
| C4 | Calc row, multi-sort, filters | — | B§I | working | C3 | 0.5 | Count, empty, filled, sum, average, min, max, checked match fixtures; multiple sort rules; AND/OR filters (`StructureTests`, `v05-filter-editor.png`) |
| C5 | CSV / frontmatter export | — | B§I | working | C2 | 0.5 | CSV export re-imports to the same values (structure test); Markdown export gives each item page YAML frontmatter |

## 10. Templates

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| M1 | New → From Template picker | Search + rows | S27, S28 | working | — | 0.5 | ⌥⌘T or Library + → From Template…: search, category chips, keyboard; 5 original built-ins; new documents get fresh block ids (`ImportTests`, `v05-template-picker.png`) |
| M2 | Custom templates | Settings | S09 | working | M1 | 0.5 | Info → Save as Template… with a category; listed in the picker and Settings → Templates; editing a template never changes documents made from it (workflow test) |

## 11. Attachments and media

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| A1 | Image block | Insert/upload | S34 | working | vault | 0.1 | Picked/pasted image copied to `assets/<sha>`; content addressing verified (`testAssetsAreContentAddressed`) |
| A2 | Paste images | — | B§5.3 | working | A1 | 0.1 | PNG/TIFF on pasteboard → image block |
| A3 | File attachment block | File | S34, S19 | verified | vault | 0.2.1 | Insert → File, drag a file onto the page, or paste a file copied in Finder; stored once by content hash with its original name and size; click opens it in its default app; listed in Attachments; exported as a link with the file in `assets/` (`testFilesInsertOpenPasteAndExport`, `FileAssetTests`) |
| A7 | Image size, caption, alt text | Resize, caption | B§7 | verified | A1 | 0.2.1 | Drag the right edge or use the image bar (S/M/L/Full) to set width as a fraction of the text width; caption shown under the image and exported; alt text is the VoiceOver label and the Markdown alt; each change is one undo step (`testImageBarSizeCaptionAltAndUndo`, `testDragResize…`) |
| A4 | Attachments pane | Images, links, files listed | S19 | working | A1 | 0.2.1 | Lists images (thumbnail), links and files; click jumps to the block |
| A5 | Link previews | Rich link | B§H | working | opt-in network | 0.4 | Off by default (no request); when on, a pasted URL becomes a card that fills in without an undo step and exports as a plain link (unit test with a stand-in fetch); live fetch checked in v0.5 (`online-live`: title read from example.com, no requests while off) |
| A6 | Whiteboard / Mermaid / Formula / photo search | Insert menu | S34 | missing | — | later | Listed disabled with version |

## 12. Import / export

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| X1 | Markdown + assets | Export As → Markdown | S39 | verified | — | 0.1 | `MarkdownTests`; real export inspected (nested page linked, tasks, quote, highlight) |
| X2 | Lossless native export | — | B§10 | verified | — | 0.1 | `draft-export.json` in bundle (`testExportBundle…`) |
| X3 | Export all | Library ⋯ | S25 | working | X1 | 0.1 | One folder, subfolders per folder |
| X4 | PDF / Print / Word / Image / E-mail | Export panel | S39 | verified | — | 0.4 | PDF (paged), HTML and PNG with "Use document style"; page color and text agree with the editor (style test). Word later, E-mail v1.x |
| X5 | Import | Library ⋯ → Import | S25 | working | — | 0.5 | ⇧⌘I: Markdown files and folders (subfolders → folders, links → doc links, images → assets), HTML, OPML, Draft JSON (ids remapped on clash; folders and styles included). Draft export → import reproduces documents, links, style and folder (workflow test, `ImportTests`) |
| X6 | Duplicate | Export panel | S39 | working | — | 0.1 | New ids for every block |
| X7 | Transfer to other apps | Disabled when absent | S40 | missing | — | 1.x | Share panel explains |
| X8 | Copy as Markdown | — | — | working | X1 | 0.1 | Share/Info → clipboard |

## 13. Version history and recovery

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| H1 | Atomic durable saves | — | B§10 | verified | — | 0.1 | No temp leftovers (`testFirstRunSaveReload…`); quit flushes (smoke test) |
| H2 | Migrations with backup; read-only on newer schema | — | prompt | verified | — | 0.1 | `testMigrationWritesBackupFirst`, `testNewerLibraryMakesVaultReadOnly` |
| H3 | View backups / restore | Info → View Backups | S41 | verified | — | 0.2 | Automatic backup at most every 10 min while editing, 30 kept per doc; Info → View Backups → Restore (current version backed up first) (`BackupTests`, smoke `backups`) |
| H4 | Recently Deleted | Top-level docs | B§B | verified | — | 0.2 | Delete → Recently Deleted with Undo toast; Restore / Delete Permanently / Empty; purged after 30 days with backups (`TrashTests`, smoke `trashed`) |
| H5 | Save state indicator | Quiet | B§8 | working | — | 0.1 | "Saved / Saving… / Not saved" in document rail |
| H6 | Unknown data preserved | — | prompt | verified | — | 0.1 | `testLibraryV0…KeepsUnknownFields`, `testUnknownNodeTypes…`, unknown block shown as preserved placeholder |

## 14. Publishing

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| U1 | Publish with preview + Create Link | Publish tab | S38 | partial | — | 1.x | Preview shown; Create Link disabled with plan |
| U2 | Published content + analytics | Settings | S14 | missing | U1 | 1.x | Settings planned state |
| U3 | Static HTML export | — | B§J | verified | X4 | 0.4 | Website of all documents: index + one page each, relative links and assets all resolve, offline (style test) |

## 15. Sharing, comments, collaboration

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| R1 | Share panel tabs | Share/Publish/Export/Transfer | S36, S37 | partial | — | 0.1 | All four tabs; Share explains local-only + Copy Markdown |
| R2 | Collaborators | Viewer/editor | B§J | missing | Y2 | 2.0 | — |
| R3 | Comments | Toolbar comment | S06, S42 | missing | — | 2.0 | — |
| R4 | Mentions | `@` | S06 | missing | L1 | 0.3 / 2.0 | — |

## 16. Sync and self-hosting

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| Y1 | Offline-first | Offline mode | B§16 | working | — | 0.1 | App contains no networking code |
| Y2 | Multi-device sync | Cloud | — | missing | CRDT | 1.x | — |
| Y3 | Custom vault location | External locations | S12, S16 | partial | — | 0.6 | `DRAFT_DATA_DIR`; in-app chooser missing |

## 17. Settings

| ID | Capability | Reference behavior | Evidence | Status | Deps | Target | Acceptance check |
|---|---|---|---|---|---|---|---|
| Z1 | System/Light/Dark | Previews | S10 | working | — | 0.1 | `settings-appearance-dark.png` |
| Z2 | Accent color | Swatches | S10 | working | — | 0.1 | Recolors selection, active states |
| Z3 | Reduce animations | Toggle | S10 | working | — | 0.1 | Disables panel/rail animations |
| Z4 | Sound / app icon choice | Toggles | S10 | missing | — | later | — |
| Z5 | Language & spelling | Rows | S11 | missing | I1 | 0.6 | Planned state |
| Z6 | Advanced | Task appearance, date links, sidebar, week start | S12 | partial | — | 0.6 | Week start, start of day, dates as chips/plain text, Online (off by default), Rebuild Index; sidebar customization → v0.6 |
| Z7 | Space settings | Avatar, name | S13 | working | N8 | 0.5 | Rename, list, switch, delete empty Spaces, New Space; generated avatar |
| Z8 | Stats | Storage, docs, blocks, pages, words, reading time | S15 | working | — | 0.1 | Settings → Stats |
| Z10 | Daily notes & tasks, Tags settings | Daily notes, reminders, calendar events; tag rules and colors | S12, S17, S25 | working | K5, G2 | 0.3 | `v03-settings-daily.png`, `v03-settings-tags.png` |
| Z9 | Data location | (Draft) | prompt | working | — | 0.1 | Path, Show in Finder, Export all |

## 18. Accessibility

| ID | Capability | Evidence | Status | Target | Acceptance check |
|---|---|---|---|---|---|
| Y11 | Accessible labels on icon-only controls | B§10 | working | 0.2.1 | Draft-owned AppKit controls (image bar, cover buttons, block handle, toolbar) have names (a11y automation); `Aa` icon chips speak their command names; attachment cells carry Image/File/Page labels with alt text |
| Y12 | Visible keyboard focus and keyboard paths | B§10 | partial | 0.6 | ⌥F10 formatting bar, Esc block mode, Tab into the image bar (a11y automation `tabIntoImageBar`), ⌘↩ toggles, crop sheet arrow keys; full audit of SwiftUI focus rings pending |
| Y13 | Menus: arrows, Return, Esc | B§5.1 | working | 0.1 | Slash menu, Quick Open, palette |
| Y14 | Contrast over backdrops | prompt | working | 0.1 | Built-in styles ≥ 7:1 text/page (test); controls on opaque pills |
| Y15 | VoiceOver audit | B§12 | missing | 0.6 | Recorded VoiceOver pass |
| Y16 | Reduce Motion and Reduce Animations | B§10 | working | 0.5.1 | One motion helper honours both Draft's setting and macOS Reduce Motion; Thinking Orbs, Border Beam and the liquid-metal edge show still frames when either is on or the window is inactive (`assistant-answering-reduced.mp4`) |
| Y17 | One design system | prompt | working | 0.5.1 | Shell uses one type scale, spacing grid, three radii, control sizes, one floating-surface shadow and shared segmented control (12 AppKit segmented pickers replaced); before/after in `docs/screenshots/v051/` |

## 19. Narrow / mobile layouts

| ID | Capability | Evidence | Status | Target | Acceptance check |
|---|---|---|---|---|---|
| W1 | Narrow window | B§9 | verified | 0.1 | < 820 pt: rail becomes overlay; paper margins shrink; breadcrumb hides; text starts below controls and the slash menu stays inside at 1440×900 and 720×640 (automation layout checks, `testSlashMenuStaysInsideVisibleAreaInShortWindow`) |
| W2 | iPad / iPhone | B§9 | missing | later | Apps on top of `DraftCore` |

## 20. Localization

| ID | Capability | Evidence | Status | Target | Acceptance check |
|---|---|---|---|---|---|
| I1 | String catalog | B§7 | missing | 0.6→0.8 | Not started in v0.6; strings are still literals in SwiftUI views |
| I2 | Unicode titles and file names | B§7 | verified | 0.1 | `testSafeFileNameKeepsDiacritics` |

## 21. Assistant and integrations (optional)

| ID | Capability | Reference behavior | Evidence | Status | Target | Acceptance check |
|---|---|---|---|---|---|---|
| J1 | Assistant | Lower-right pill | S01 | working | 0.5.1 | Toolbar button and ⌘J; pinned panel or floating window; runs LFM2.5 on this Mac via llama.cpp (no account, key or cloud); opt-in verified download with size, progress, cancel and remove; Selection / Document / Space context, Space answers retrieve blocks from the vault index and cite them as source cards that open the block; summarize, explain, rewrite, shorten, expand, outline; streamed with Stop; history per Space; preview with word diff before Insert or Replace, one undo step (`scripts/assistant-test.sh` runs with networking denied; `AssistantTests`, `AssistantEditTests`, `ModelStoreTests`, `PrivacyTests`, `v051-assistant-*.png`) |
| J4 | Assistant on long documents | — | — | verified | 0.6 | Ask/Summarize/Explain/Outline read a document longer than the context in parts and combine the notes; the notice says it read all of it in N parts. Offline test: fact at the end of a 4,686-word note found (2 parts) |
| J5 | Faster Assistant follow-ups | — | — | verified | 0.6 | Model state saved after the system turn (document text) and restored for the next question: 2nd question first token 0.12–0.39 s vs 2.3–3.0 s (offline test asserts ≥ 2×) |
| J6 | Assistant voice | — | — | partial | 0.6 | Read Aloud (system voice) verified offline; dictation uses only Apple's on-device recognizer (available on this Mac) but the microphone/speech prompts and a live dictation need a person; VoiceGlow only while listening or speaking |
| J7 | Assistant quality benchmark | — | — | verified | 0.6 | `scripts/assistant-quality.sh`: 30 fixed questions, expected facts and citations; LFM2.5 2.6B 27/30 (90%), results in `docs/assistant-quality/` |
| J2 | MCP / API connections | Scenic connection view | S32 | working | 0.7 | DraftMCP 0.2.0 (14 tools) for Codex and Claude Code: read tools and reviewed proposals for note edits (text, append, insert, delete, reorder, block types, lists, tasks, inline formatting, colours, links, decorations, separators, style) and create/rename/move notes; revision recheck, backup, index update, one Undo; reject/stale/refused leave notes unchanged (`scripts/mcp-test.sh` 39 checks, `scripts/agent-test.sh`). Not yet: folders, deleting notes, multi-note proposals, tables, inserting images/files; no connection UI in Draft |
| J8 | Optional OpenAI provider | — | — | partial | 0.6 | Own API key in Keychain, Responses API with `store: false`, context reviewed before each send; unit-tested (SSE parsing, privacy fields, separate histories); a live request was not made (needs the user's key). Not ChatGPT sign-in, not a Codex agent |
| J3 | Writing suggestions in toolbar | Dynamic slot | S06 | missing | later | — |

## 22. Platforms

| ID | Capability | Status | Target | Acceptance check |
|---|---|---|---|---|
| PL1 | Native macOS app (SwiftUI + AppKit/TextKit) | working | 0.1 | `scripts/build-app.sh` → `build/Draft.app`; smoke test passes |
| PL2 | Portable format spec | working | 0.1 | `docs/FORMAT.md` matches `DraftCore` |
| PL3 | Conformance fixtures for other implementations | missing | 0.6–0.8 | Language-neutral input/expected-output vaults |
| PL4 | Windows app | missing | after Mac 1.0 | Reads/writes a Mac vault losslessly |
| PL5 | Signed + notarized build | missing | 1.0 | Gatekeeper accepts download |

## 23. v0.6 "Every window" additions

| ID | Capability | Status | Target | Acceptance check (result) |
|---|---|---|---|---|
| W1 | Shared components and surfaces | working | 0.6 | `Components.swift`: buttons, centred icon menus, rows, empty states, one translucent surface and motion for Format/Style/Info/Share/Quick Open/templates/dialogs/Assistant; captures in `docs/screenshots/v06/` |
| W2 | First-use welcome and five-step tour | working | 0.6 | Shown once (not during automation); Start Writing, tour with Back/Next/Skip and ←/→/Return/Esc; replay from Help and Settings; the model downloads only from its button |
| W3 | Keyboard Shortcuts sheet (⌘/) | verified | 0.6 | Read from the live menu bar plus typing triggers, searchable (`MenuShortcutTests`) |
| W4 | Focus mode (⇧⌘F) | verified | 0.6 | Chrome hidden, other blocks faded; Esc leaves; 10k-block keystroke p95 14–18 ms, Return p95 13–16 ms in Focus mode |
| W5 | Present mode (⌥⌘P) | partial | 0.6 | Headings (level 1–2) split slides (`SlidesTests`); arrows/Space/Return/Esc; full screen on a second display when one exists — not tested (one display) |
| W6 | Sidebar customization | verified | 0.6 | Show/hide and reorder in Settings → Appearance → Sidebar; stored in settings, repaired on load (`SpaceSettingsTests`) |
| W7 | Per-Space theme, daily-note and tag settings | verified | 0.6 | Saved and applied on Space switch without restart (`SpaceSettingsTests`) |
| W8 | Relation picker search | working | 0.6 | Searchable popover over every live document (was the first 40 in a menu) |
| W9 | Table column reordering in one undo; rich text in cells | missing | 0.8 | Not done in v0.6 |
| W10 | Dark Paper | verified | 0.6 | `Styles.forDisplay` (tested); files and exports keep the light page |
| W11 | Out-of-process accessibility audit | partial | 0.6 | `scripts/ax-audit.swift` written; needs a terminal with Accessibility permission to run — not run |
