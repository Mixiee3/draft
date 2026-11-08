# Draft UI, motion and performance audit — before v0.6

*Audited 2026-11-08 on `main` at `3b75f26` (v0.5.1). Read-only: no Draft source was changed. Captures
were made by a throwaway harness built in a separate worktree (never committed); everything referenced
below is in [`docs/screenshots/audit-v06/`](screenshots/audit-v06/).*

## 0. How this was done, and on what

| | |
|---|---|
| Mac | MacBook Air M4 (Mac16,12), 16 GB, built-in Liquid Retina display, **60 Hz** (`maximumFramesPerSecond` = 60), so the frame budget is 16.7 ms |
| Load | **Not an unloaded Mac.** Parsec (remote desktop) was running for the whole audit, keeping system GPU utilisation at 70 % mean / 98 % max (`data/sys.txt`); Spotlight indexing (`mds_stores`) was also busy. GPU-bound numbers are pessimistic; main-thread findings are not affected by this |
| Screens | 134 screenshots: every major screen and flow in light and dark, at 1440×900 and 760×720 (`screens/`, prefixes `dark-`, `narrow-`). Taken from the screen area over the window, so popovers, menus and sheets are included |
| Motion | 11 recordings at 31–60 fps (`motion/*.mp4`); per-frame change analysis in `data/motion-analysis.txt` (an episode that changes in one frame is a cut, a spread over frames is an animation) |
| Performance | 20 scripted scenarios driven frame by frame against a `CADisplayLink`, with representative content: 300 notes, 2,000- and 10,000-block documents, a 1,000-item collection, the installed LFM2.5-2.6B model. Recorded: frame intervals, % within 16.7 ms, p95/p99/max, hitches (> 2.5 frames), input-to-frame latency, process CPU, memory (`data/audit-frames.json`). Hot paths from `sample` profiles of the five worst scenarios |
| Reference | Craft screenshots and research brief (comparison only; nothing copied). Craft references are cited by file name, e.g. *Craft 27-new-document-menu* |

**Reading the tables.** *Type*: **Bug** = observed defect; **Design** = subjective improvement.
*Severity*: Critical (blocks a task), High (looks broken or costs real time), Medium, Low.
*Effort*: S ≤ ½ day, M ½–2 days, L 2–5 days.

---

## 1. Top 15 recommended fixes (ranked by user impact ÷ effort)

| # | Fix | Finding | Type | Sev | Effort |
|---|---|---|---|---|---|
| 1 | Floating Assistant window opens 380×1284 pt on a ~956 pt screen: message box off-screen. Clamp to the screen's visible frame (default 400×640), drop the duplicate title and close button | V16 | Bug | Critical | S |
| 2 | Collections re-convert the whole host document and JSON-round-trip the collection on every view update → cache the decoded `CollectionData` per (document, block, revision) | P1 | Bug (perf) | High | S |
| 3 | Space switch takes 616 ms median: the "Switched to …" toast's `withAnimation` forces the whole new Space to render synchronously inside an animation; Calendar `Day.title` builds a `DateFormatter` per card; library saved as pretty JSON on the main thread → toast after the switch without animation, cache formatters, save off the main thread | P3 | Bug (perf) | High | S |
| 4 | Assistant edit preview: inline word diff glues added and removed words ("twoThree ideaspages, —first athing.") → before/after stacked view when most words change, sentence-level diff otherwise, tinted backgrounds plus +/− markers instead of red/green text | V17 | Bug | High | M |
| 5 | Note creation: caret lands in the body so notes stay "Untitled"; the page is a small card in a large grey field; the sidebar flips to an empty outline; 350 ms to the first frame → caret in the title, page fills the viewport, stable sidebar, animated arrival, faster path (see P4) | V2, M4, P4 | Bug + Design | High | M |
| 6 | "+" glyph sits 3.0 pt left of centre (measured, light and dark); same construction on Sort, More and the document "+" → one `DraftIconMenu` control with a square hit area and a real `NSMenu`, no reserved indicator space | V1 | Bug | Medium | S |
| 7 | Opening a document parses it three times (`JSONValue` → migrate → re-encode → decode `DocFile`) and loads + restyles all blocks synchronously inside a SwiftUI `body` → decode `DocFile` directly when the schema is current; create editors outside `body`; style the visible range first | P2 | Bug (perf) | High | M |
| 8 | Settings controls look dated and foreign: AppKit pop-ups with blue steppers, blue checkboxes, small bezel buttons, plain text fields, shortcuts as a paragraph → Draft menu button, switch rows, Draft buttons and fields, a shortcuts table | V4 | Design | High | M |
| 9 | Panels close with no animation (one-frame cut) while they open with a spring; opening shows an empty slab before content and the page width jumps → one shared enter/exit transition, page offset animated as a transform, width committed once | M1, M2 | Bug | Medium | M |
| 10 | Assistant opening: toolbar button capsule and label animate separately (overlapping text), panel contents clipped while sliding, editor re-wraps at the end → keep the button fixed-width, slide a snapshot-sized container, re-wrap once after | M3 | Bug | Medium | M |
| 11 | Flat panels where Craft layers translucent controls (Format, Style, Info, Share, Assistant, template picker, Quick Open) → one `Surface` system with three levels on native materials | V6 | Design | Medium | M |
| 12 | Share panel tabs truncate ("Publi…", "Expo…", "Tran…"); Info panel shows "Words 0, Blocks 1" for a note with content until it saves → fit or icon segments; read counts from the live editor | V7, V8 | Bug | Medium | S |
| 13 | Library list scrolling burns 97 % CPU and tab switching misses frames (p95 75 ms, 659 ms with large documents open): every model change re-evaluates the whole window; each card builds its own context menu → split `AppModel` into observed pieces, lazy context menus | P4, P6 | Bug (perf) | High | L |
| 14 | First launch drops people into a library with two seed notes and no explanation of local files, Spaces or the Assistant → the welcome screen and 5-step tour in §6 | V23 | Design | Medium | L |
| 15 | Narrow window: tabs are cut under the Assistant button with no fade ("Reac…"); floating panels cover text with no edge → overflow fade plus "more tabs" menu; soft scrim edge under floating panels | V21, V22 | Bug + Design | Medium | S |

---

## 2. Shared design-system causes

Fixing these at the source improves many screens at once.

| Cause | Where it shows | Fix in the design system |
|---|---|---|
| **C1. SwiftUI `Menu` used as an icon button.** Rendered as an `NSPopUpButton` that keeps room for its (hidden) arrow and has a 37×14 pt intrinsic frame inside a 32×30 pill | Off-centre "+" (V1), Sort, More, document "+", collection "…" | `DraftIconMenu`: square hit target sized by `DS.control`, glyph centred by layout, opens a native `NSMenu` |
| **C2. Native AppKit controls left in SwiftUI forms** | Settings pop-ups, checkboxes, steppers, bezel buttons, text fields (V4); Style Gallery buttons (V11); edit preview buttons; Data & Storage | `DraftMenuButton`, `DraftSwitchRow`, `DraftButton(.primary/.secondary/.destructive)`, `DraftTextField`, `DraftStepper`, all on `DS` tokens |
| **C3. No surface levels.** Every floating thing is an opaque `floatingSurface` card | Panels, Assistant, picker sheets, Quick Open, coach marks (V6) | Three levels: **Inline** (cards on canvas: solid), **Floating** (panels, popovers, Assistant: `NSVisualEffectView` `.popover`/`.sidebar` material, 0.5 pt inner highlight, rim, `DS` shadow), **Overlay** (sheets, welcome: `.hudWindow`-like material over a 20 % scrim). Text on materials keeps ≥ 4.5:1 contrast |
| **C4. Transitions written ad hoc per view** (`transition(.opacity.combined(with: .move))`, `withAnimation` at call sites) | Asymmetric panel open/close (M1), Assistant open (M3), cuts on navigation (M4–M6), toast forcing synchronous renders (P3) | `Motion` presets used through view modifiers only (`.panelTransition()`, `.navigationTransition()`), never `withAnimation` around model mutations that change whole screens |
| **C5. One big observed model.** `AppModel` publishes everything; any change re-evaluates the rail, tab strip, library, commands and document screen | Tab switch, note creation, list scrolling CPU, Space switch (P3, P4, P6) | Split into observed models (library, tabs, settings, per-document UI) with the Observation framework; `Equatable` row views |
| **C6. Derived data recomputed in `body`** | `collectionData` (P1), `outlineOf` in the sidebar, editor creation inside `DocumentScreen.body` (P2), Info counts (V8) | Derived values cached by revision on the model; `body` only reads |
| **C7. Planned features shown as disabled rows** | "Present — planned", "Word — later", "E-mail — v1.x", "Published Content · v1.x", "Language & Spelling · v0.6" (V10) | One "Coming later" footnote per panel instead of dead rows |

---

## 3. Findings by screen

### 3.1 First launch, library and note creation

| ID | Screen and interaction | Capture | What is wrong / could improve | Craft reference | Proposed fix | Type | Sev | Effort |
|---|---|---|---|---|---|---|---|---|
| V23 | First launch | `screens/01-first-launch.png`, `dark-01-…`, `narrow-01-…` | Opens straight into All Docs with "Welcome to Draft" and "Morning pages". Nothing says where notes live, what Spaces are or that an Assistant exists | Craft opens to its own onboarding (not in our set) | Welcome screen and tour (§6) | Design | Medium | L |
| V24 | First launch, library | `01-first-launch.png` | The selected "Welcome" card has a 2.5 pt teal border that reads like a focus ring on a screen nobody has touched; card preview text is ~8 pt serif and dense | *Craft 21-all-docs-gallery*: selection is a soft tint | Selection = 1 pt accent ring + light tint; previews at `DS.footnote` with 3–4 lines | Design | Low | S |
| V1 | Library header "+" | `02-new-note-button-zoom.png`, `dark-02-…` | Glyph is **3.0 pt left** (and 0.2 pt low) of the circle's centre, measured from pixels in both themes (cause C1) | *Craft 21*: centred plus in a circle | `DraftIconMenu` (C1) | Bug | Medium | S |
| V3 | "+" menu | `03-new-note-menu.png` | A click opens a menu instead of a note; "New Folder" sits in a note menu; the document toolbar has a second "+" with the same menu | *Craft 27-new-document-menu*: click creates, menu offers templates | Click = new note; chevron or long-press = "From Template…", "New Folder", "Import…" | Design | Medium | S |
| V2 | New note (⌘N or +) | `06-new-note-empty.png`, `07-editor-content.png`, `motion/new-note.mp4` | Caret lands in the body, so the note stays "Untitled" (tab, sidebar, library) unless you click the title. The page is a short card in a large grey field. The sidebar switches from the library to an empty "Table of Contents". Arrival is a hard cut (M4) and takes 350 ms to the first frame (P4) | *Craft 27* | Caret in the title; Return moves to the body; the page always fills the viewport height; keep the library sidebar with the new note highlighted (outline only on request); animated arrival (§4) | Bug + Design | High | M |
| V27 | After closing a menu with Esc | `06`–`28` captures show a creation menu under the document "+" | A "New Document / From Template… / New Folder" menu stays drawn in later captures. Most likely my scripted Esc plus a queued click reaching the new note's "+", but not proven | — | **Verify by hand**: open "+", press Esc, press ⌘N | Unverified | — | S |
| V28 | Library list | `04-library-list.png` | Fine overall; three date columns compete with the preview line | *Craft 23-all-docs-list* | Last edited only by default; others behind Sort | Design | Low | S |

### 3.2 Editor, formatting and panels

| ID | Screen and interaction | Capture | What is wrong / could improve | Craft reference | Proposed fix | Type | Sev | Effort |
|---|---|---|---|---|---|---|---|---|
| V6 | Format, Style, Info and Share panels | `10-panel-*.png`, `dark-10-panel-format.png` | Opaque flat cards; Craft's panels are layered and translucent over the backdrop | *Craft 02-style-panel, 05-format-panel, 41-info-panel* | Surface level **Floating** (C3) | Design | Medium | M |
| V7 | Share panel tabs | `10-panel-share.png` | Labels truncate: "Publi…", "Expo…", "Tran…" (four stretched segments in 304 pt) | *Craft 37-share-panel* | Icon + short labels, or two rows; or 320 pt panel | Bug | Medium | S |
| V8 | Info panel counts | `10-panel-info.png` | "Words 0, Blocks 1" for a note with six blocks while "Saving…": counts come from saved metadata | *Craft 41-info-panel* | Derive from the live editor document | Bug | Medium | S |
| V9 | Info panel actions | `10-panel-info.png` | Grey action rows mixed with a blue link-style "Move to…" with chevron and a disabled "Present — planned" | *Craft 42-info-actions* | One action-row style; Move to opens a folder menu | Design | Low | S |
| V10 | Share export list, Settings sidebar, Info | `10-panel-share.png`, `14-settings-*.png` | Dead rows for future features ("Word — later", "E-mail — v1.x", "Published Content · v1.x", "Language & Spelling · v0.6", "Present — planned") | Craft shows only working items | C7 | Design | Low | S |
| V29 | Share export: "Use document style" | `10-panel-share.png` | A lone centred switch between list rows; "Print… (Save as PDF from the dialog)" wraps | *Craft 39-export-panel* | Switch as a full-width row under a "Style" header; shorter label "Print…" | Design | Low | S |
| V11 | Style Gallery | `11-style-gallery.png` | Small native bezel buttons ("In Use", "Duplicate") under the preview; modal dims the whole window including the sidebar | *Craft 03-style-gallery* | `DraftButton`s; preview column with a large "Use Style" primary | Design | Low | S |
| V30 | Selection toolbar | `08-selection-toolbar.png` | Good glass look; appears in a single frame (M7) | *Craft 06-selection-toolbar* | 120 ms fade + 4 pt rise | Design | Low | S |
| V31 | Slash menu | `09-slash-menu.png` | Clear; list is cut mid-row at the bottom with no fade; shortcut column very light | *Craft 34-editor-insert-menu* | Bottom fade; shortcuts at `secondary` colour | Design | Low | S |
| V20 | Dark theme, editor | `dark-07-editor-content.png`, `dark-10-panel-format.png` | Shell turns dark but the backdrop and Paper stay light: a bright slab in a dark window | Craft keeps document styles but offers dark variants | "Paper follows appearance" option (Paper ↔ a dark paper) on by default for Paper only | Design | Medium | M |

### 3.3 Settings

| ID | Screen and interaction | Capture | What is wrong / could improve | Craft reference | Proposed fix | Type | Sev | Effort |
|---|---|---|---|---|---|---|---|---|
| V4 | Settings controls (your note) | `14-settings-daily.png`, `-editor`, `-advanced`, `-tags`, `-space`, `-data`, `-assistant`, `-templates`, `-about` | AppKit pop-up menus with blue stepper chevrons (default style, daily template, reminder time, day start), blue checkboxes (Daily, Tags, Online) next to switches (Appearance), small bezel buttons (Save, New Space…, Rebuild Index, Show in Finder, Export All, Remove Model…, Third-Party Notices), plain bordered text fields, keyboard shortcuts as a run-on paragraph | *Craft 10-settings-appearance, 13-settings-space, 17-settings-tags, 12-settings-advanced* | C2 components; switches for every on/off; shortcuts as a two-column table; one primary action per card | Design | High | M |
| V5 | Settings layout | `14-settings-appearance.png` | Three columns (app sidebar, settings list, content) and a wide empty right side at 1440 pt | *Craft 16-settings-on-device*: settings replace the sidebar | Settings list takes the sidebar's place while Settings is open; content column max 680 pt, centred | Design | Medium | M |
| V32 | Template picker | `13-template-picker.png`, `narrow-dark-13-…` | Heavy dark-navy focus ring around the search field; flat sheet | *Craft 28-template-picker* | Focus ring = accent at 50 % with 3 pt soft glow; Overlay surface | Design | Low | S |
| V33 | Settings → Assistant | `14-settings-assistant.png` | Model choice shows "1,59 GB" next to a segmented control; actions are bezel buttons; facts block dense | — | Model cards with size, speed, quality notes; `DraftButton`s | Design | Low | S |

### 3.4 Calendar, tasks, tables, collections

| ID | Screen and interaction | Capture | What is wrong / could improve | Craft reference | Proposed fix | Type | Sev | Effort |
|---|---|---|---|---|---|---|---|---|
| V13 | Tasks, empty Today | `16-tasks.png` | Under "Nothing due today…" are five blank grey bars that look like failed rows | *Craft 18-document-tasks-sidebar* | Check what renders them; empty state alone, centred, with one action ("Add a task to today's note") | Bug (verify) | Medium | S |
| V14 | Calendar | `15-calendar.png` | Day cards use the left ~45 % of the page at 1440 pt; filters sit far right | *Craft 33-calendar* | Two-column week layout above 1100 pt, or centred column with filters beside the title | Design | Low | M |
| V15 | Collection table | `19-collection-table.png` | Every status prefixed with a small square glyph; empty cells as "—"; a footer row of blue "Calculate" links; "New Item" filled navy, off the accent | — | Status as a coloured pill; blank empty cells; calculations shown on hover; accent-filled primary | Design | Medium | S |
| V34 | Collection gallery | `19-collection-gallery.png` | Every card is a pastel tile with "B"; scrolls at 77 % on-time frames (P1) | — | Use the first image or a title tile; fix P1 | Design | Low | S |
| V35 | Table editing | `18-table-editing.png` | Correct alignment; fields are native text fields without Draft focus styling | — | `DraftTextField` focus | Design | Low | S |

### 3.5 Assistant

| ID | Screen and interaction | Capture | What is wrong / could improve | Craft reference | Proposed fix | Type | Sev | Effort |
|---|---|---|---|---|---|---|---|---|
| V16 | Floating Assistant window (your note) | `26-assistant-floating.png`, `dark-26-…`, `data/26-assistant-floating-size.txt` | Opens **380 × 1284 pt** on a ~956 pt-tall screen: the message box, actions and footer are off-screen. Title bar says "Assistant" and so does the header; two close buttons | *Craft 32-imagine*: compact assistant pill | Clamp to `screen.visibleFrame` (default 400 × 640, max 85 % height); hide the window title; one close button | Bug | Critical | S |
| V17 | Edit preview (your note) | `25-assistant-edit-preview.png`, `dark-25-…` | Word-level diff of a full rewrite is unreadable: added and removed words glued without spaces; red/green text only (colour-blind and dark-mode contrast issues); buttons are large native bezels | — | If > 40 % of words change: "Before" (muted) and "After" stacked; else sentence diff with tinted backgrounds and +/− gutter; `DraftButton`s; Replace as primary | Bug | High | M |
| V18 | Answer text selection, dark (your note) | `dark-24-assistant-text-selection.png` | A scripted drag did not create a selection, so the dark-mode selection colour could not be judged | — | **Check by hand**; if the highlight is the system blue on the dark panel, use accent at 35 % | Unverified | — | S |
| V19 | Assistant panel layout | `21-assistant-ready.png`, `23-assistant-answer.png`, `narrow-21-…` | Large empty middle when idle; answers at 12 pt in a 330 pt column feel dense; user bubble shows the scope as a second line inside the bubble | *Craft 32-imagine* | Idle state with 3 suggestion chips; answers at `DS.body`; scope as a small label above the bubble | Design | Low | S |
| V36 | Thinking state | `22-assistant-thinking.png`, `motion/assistant-states.mp4` | Orb + "Thinking… Show reasoning" works; streamed text appears in line-sized jumps | — | 80 ms fade-in per new line (Reduce Motion: none) | Design | Low | S |

### 3.6 Narrow window and Spaces

| ID | Screen and interaction | Capture | What is wrong / could improve | Craft reference | Proposed fix | Type | Sev | Effort |
|---|---|---|---|---|---|---|---|---|
| V21 | Tabs at 760 pt | `narrow-21-assistant-ready.png` | Tab strip cut off under the Assistant button ("Reac…") with no fade or overflow menu | Craft compresses tabs | Right-edge fade + "› n more" menu; Assistant button collapses to its icon below 900 pt | Bug | Medium | S |
| V22 | Panels and Assistant at 760 pt | `narrow-10-panel-format.png`, `narrow-21-…` | Float over the page as designed, but the page text is cut mid-word with no edge | — | 12 pt soft shadow + 6 % scrim on the covered page | Design | Low | S |
| V26 | Space switcher menu | `20-space-menu.png` | My click missed the switcher; the menu was **not captured** | *Craft 08-sidebar-mode-menu* | Inspect by hand | Not inspected | — | — |

---

## 4. Motion audit and proposed rules

### 4.1 What happens today

| ID | Interaction | Recording | Measured (`data/motion-analysis.txt`) | Assessment | Fix | Type | Sev | Effort |
|---|---|---|---|---|---|---|---|---|
| M4 | New note appears | `new-note.mp4` | One-frame cut (100 % of change in the first frame) | Missing: the new page just replaces the library | 180 ms: library fades and scales 0.98, page rises 8 pt and fades in; caret visible from frame 1 | Design | Medium | M |
| M5 | Library → editor | `enter-editor-from-library.mp4` | One-frame cut | Missing | Same navigation transition as M4 (shared) | Design | Low | S |
| M6 | Space switch | `space-switch.mp4` | 54 % of the window changes in one frame, plus a toast | Abrupt; also slow (P3) | 200 ms crossfade of content only (sidebar list cross-fades, chrome stays); toast without animation transaction | Bug | Medium | S |
| M1 | Panel close | `panel-open-close.mp4` | Open: ~180 ms over 7 frames. Close: **one frame** | Asymmetric; exit missing | Shared `.panelTransition()`: in 220 ms spring, out 160 ms ease-in | Bug | Medium | S |
| M2 | Panel open | `panel-open-close.mp4`, `panel-switch.mp4` | Empty translucent slab first, then dimmed content fades in; page narrows in one step; switching panels takes 3 uneven steps (55–250 ms) | Rough | Container and content as one unit; page offset animated as a transform, final width applied once at the end; panel-to-panel = content crossfade, container stays | Bug | Medium | M |
| M3 | Assistant open/close | `assistant-open-close.mp4` | Open ~60–115 ms in uneven steps; close ~260 ms. Toolbar button capsule and label animate separately (overlapping text); panel content clipped while sliding ("marize", "rten"); breadcrumb pill flickers to disabled | Rough and asymmetric | Fixed-width toolbar button (fill change only); slide a container already laid out at final width; editor re-wrap after the slide; 260 ms in / 200 ms out | Bug | Medium | M |
| M7 | Selection toolbar | `selection-toolbar.mp4` | Appears in one frame | Slightly abrupt | 120 ms fade + 4 pt rise; disappear 90 ms | Design | Low | S |
| M8 | Tab switch | `tab-switch.mp4` | Instant | Correct for speed; keep | No animation; only the tab pill's highlight slides (120 ms) | — | — | S |
| M9 | Hover on library cards | `library-hover.mp4` | Posted mouse moves did not trigger hover: **not judged** | — | Check by hand; current code scales cards 1.2 %, barely visible | Not inspected | — | — |
| M10 | Block drag and drop | `block-drag.mp4` | Ghost follows the pointer over ~260 ms continuously; drop lands in one frame | Good drag, abrupt drop | 150 ms settle of the moved block into place | Design | Low | S |
| M11 | Assistant states | `assistant-states.mp4` | Orb states change smoothly; text arrives in line jumps | Good; streaming could be softer | V36 | Design | Low | S |

### 4.2 Proposed shared rules (`Motion` tokens)

| Token | Use | Curve | Duration | Reduce Motion version |
|---|---|---|---|---|
| **instant** | Typing, caret, selection, tab content, scrolling | — | 0 | same |
| **micro** | Hover, press, toggles, toolbar appear, tab highlight | ease-out `(0.2, 0, 0, 1)` | 120 ms in / 90 ms out | opacity only, 80 ms |
| **panel** | Side panels, popovers, menus, Assistant pinned | spring response 0.26, damping 0.9 | ≈ 220 ms in / 160 ms out (ease-in) | 120 ms crossfade, no movement |
| **navigate** | Library ↔ editor, new note, Space switch | ease-out | 180 ms; outgoing fades in 120 ms | 100 ms crossfade |
| **emphasis** | Sheets, welcome, tour spotlight, floating Assistant window | spring response 0.34, damping 0.86 | ≈ 300 ms in / 200 ms out | 150 ms crossfade, spotlight jumps |
| **decor** | Thinking orb, border beam, liquid metal | continuous | — | still frame (already done) |

Rules:
1. **Never delay writing.** No animation on a path between a key press and its character; the caret is visible from the first frame of any transition into the editor.
2. **Exits mirror entries and are ~25 % faster.**
3. **Animate transforms and opacity only.** Layout changes (page width, text re-wrap) happen once, at the start or the end, never per frame.
4. **One owner per transition.** A container animates; its content does not run its own transition at the same time (stagger content ≤ 40 ms if at all).
5. **No `withAnimation` around whole-screen model changes** (Space switch, document open). Use view-level transitions so SwiftUI can render the new screen first.
6. **Reduce Motion** (Draft setting or macOS): movement becomes a short crossfade, springs become 120 ms fades, decorative loops pause.

---

## 5. Performance

### 5.1 Measured baseline (60 Hz, Parsec running)

*On time* = frame interval ≤ 16.7 ms. Target: **≥ 99 % on time** while scrolling and animating. Latency = action to
the second following frame (floor of the method: 2 frames ≈ 33 ms).

| Scenario | Frames | On time | p95 | p99 | Max | Hitches | Latency p50 / p95 | CPU | Memory |
|---|---|---|---|---|---|---|---|---|---|
| Idle, document open | 180 | 100 % | 16.7 | 16.7 | 16.7 | 0 | — | 2.0 % | 131 MB |
| Typing, 2,000-block doc | 356 | 99.7 % | 16.7 | 16.7 | 34.4 | 0 | 33 / 33 ms | 43 % | 216 MB |
| Return, 2,000-block doc | 91 | 100 % | 16.7 | 16.7 | 16.7 | 0 | 33 / 33 ms | 41 % | 216 MB |
| Scroll, 2,000-block doc | 241 | 100 % | 16.7 | 16.7 | 16.8 | 0 | — | 11 % | 201 MB |
| **Scroll, 10,000-block doc** | 245 | **73.1 %** | 33.3 | 33.3 | 41.8 | 1 | — | 39 % | 296 MB |
| Library gallery scroll (300 notes) | 241 | 100 % | 16.7 | 16.7 | 16.8 | 0 | — | 49 % | 285 MB |
| Library grid scroll | 241 | 99.6 % | 16.7 | 16.7 | 33.3 | 0 | — | 28 % | 221 MB |
| **Library list scroll** | 241 | **94.6 %** | 33.3 | 33.3 | 35.3 | 0 | — | **97 %** | 280 MB |
| Collection 1,000, table scroll | 241 | 100 % | 16.7 | 16.7 | 16.8 | 0 | — | 42 % | 256 MB |
| Collection 1,000, board scroll | 241 | 100 % | 16.7 | 16.7 | 16.8 | 0 | — | 32 % | 198 MB |
| **Collection 1,000, gallery scroll** | 241 | **77.2 %** | 51.6 | 56.3 | 60.8 | 36 | — | 42 % | 241 MB |
| **Note creation** (×8) | 306 | **85.6 %** | 164.7 | 464.8 | 473.8 | 24 | **349 / 349 ms** | 60 % | 166 MB |
| **Tab switching** (×20, incl. 2k and 10k docs) | 341 | **85.0 %** | 74.9 | 312.7 | 584.4 | 30 | **166 / 659 ms** | 47 % | 313 MB |
| **Space switching** (×8) | 218 | **89.9 %** | 79.9 | 606.8 | 677.9 | 13 | **616 / 697 ms** | 53 % | 243 MB |
| Panels open/close (×6) | 313 | 91.1 % | 26.4 | 93.8 | 106.9 | 15 | 114 / 133 ms | 44 % | 272 MB |
| Selection toolbar (×10) | 251 | 100 % | 16.7 | 16.7 | 16.8 | 0 | — | 3 % | 210 MB |
| **Settings sections** (×12) | 205 | **89.8 %** | 48.7 | 203.4 | 544.4 | 13 | 83 / **747 ms** | 36 % | 255 MB |
| Assistant open/close (×4) | 169 | 82.2 % | 70.4 | 89.2 | 100.1 | 22 | 127 / 158 ms | 51 % | 288 MB |
| Assistant streaming (10.7 s answer) | 617 | 98.7 % | 16.7 | 33.3 | 117.2 | 4 | — | 40 % | 591 MB footprint, **2.27 GB resident** (mapped model) |
| Window live resize 1440 → 728 pt | 91 | 71.4 % | 33.3 | 39.7 | 39.7 | 0 | — | 61 % | 405 MB |
| Block drag (frame scenario) | — | — | — | — | — | — | — | — | **not measured** (scenario failed to find its blocks; motion recorded only) |

System GPU during the run: 70 % mean, 98 % max (Parsec). Per-process GPU time is not available without
elevated tools; GPU numbers above are system-wide.

### 5.2 Code paths behind missed frames (from `sample` profiles), ranked by impact

| # | Path | Evidence | Fix | Expected effect | Effort |
|---|---|---|---|---|---|
| P1 | `AppModel.collectionNode` → `EditorController.document()` (whole host document converted from text storage) → `CollectionData(node:)` (JSON encode + decode) on **every** call; `CollectionScreen.body` calls it repeatedly | Collection profile: `JSONValue.encode`, `CollectionData.init(node:)`, `CollectionItem.init(from:)` top Draft frames | Cache decoded `CollectionData` per (doc, block, revision); read the node from the saved document unless the editor is dirty | Gallery scroll 77 % → ≥ 99 % | S |
| P2 | `Vault.loadDoc` → `Migrations.migrateDoc`: decode to `JSONValue`, run steps, **re-encode**, decode `DocFile`; then `AppModel.editor(for:)` inside `DocumentScreen.body` runs `EditorController.load` + `restyleAll` for every block | Scroll/open profile: `JSONValue.init(from:)` 4,061 samples; tab profile: `editor(for:)` → `restyleAll` 412 samples | Fast path: decode `DocFile` directly when `schemaVersion` is current; create editors outside `body` (prewarm on tab open); style visible range first, rest in idle slices | First open of a 10k-block doc ~3× faster; tab switch to an unopened doc no longer blocks | M |
| P3 | `AppModel.switchSpace` → `toast(...)` → `withAnimation` flushes the whole new Space synchronously (168 of 185 samples); `Day.title` allocates a `DateFormatter` per calendar card; `Vault.saveLibrary` writes pretty, key-sorted JSON of all metadata on the main thread | Space profile | Toast without animation transaction, after the switch; cache `Day.title` formatters (same fix as `Day.key` in v0.5.1); encode on main, write on a background queue, compact JSON | Space switch 616 ms → ~100 ms | S |
| P4 | SwiftUI graph and layout for the whole window on every model change (`AG::Graph::UpdateStack::update`, `makeElements`, `sizeThatFits` dominate note creation and tab switching); `DocCardMenu` builds a context menu per library card | Create and tab profiles | C5: split observed state; `Equatable` cards and rows; context menus built on demand; library list with fixed row heights | Note creation 350 → ≤ 100 ms; tab switch p95 75 → ≤ 50 ms | L |
| P5 | Settings: first visit to each section builds its view tree (and Assistant settings query the model store) | Settings p95 747 ms, first-visit spikes | Keep sections alive after first show; move file-system checks off the main thread | ≤ 100 ms | S |
| P6 | Library list view: 97 % CPU while scrolling (row views with preview text and three formatted dates) | Frame scenario | Cache formatted dates per row; `Equatable` rows; drop unseen columns at narrow widths | ≥ 99 % on time, CPU < 40 % | S |
| P7 | 10,000-block document scroll at 33 ms frames | Frame scenario; needs a dedicated profile | Profile `DraftLayoutManager.drawGlyphs`/markers; cache marker geometry; TextKit non-contiguous layout check | ≥ 99 % on time | M |
| P8 | Live resize re-wraps the editor every frame | Frame scenario | Freeze text wrap during live resize (scale the page), re-wrap on `viewDidEndLiveResize` | ≥ 95 % on time | M |
| P9 | Assistant open: panel insertion changes the editor width, causing a re-wrap mid-animation | Assistant profile + M3 | Overlay during the slide, commit width at the end | 127 → ≤ 50 ms to first frame | S |

### 5.3 Proposed targets (to add to `scripts/ux-perf.sh`, measured with a `CADisplayLink`)

| Measure | Target at 60 Hz | Target at 120 Hz (ProMotion) |
|---|---|---|
| Scrolling: documents, library, collections | ≥ 99 % frames ≤ 16.7 ms | ≥ 99 % frames ≤ 8.3 ms; ≥ 99.5 % ≤ 16.7 ms |
| Animations (panels, navigation, Assistant) | ≥ 99 % on time, no frame > 33 ms | ≥ 98 % ≤ 8.3 ms |
| Typing / Return latency (to displayed frame) | ≤ 2 frames p95 | ≤ 3 frames p95 |
| Note creation to editable caret | ≤ 100 ms p95 | same |
| Tab switch / Space switch | ≤ 50 ms / ≤ 100 ms p95 | same |
| Panel / Assistant / Settings section first frame | ≤ 50 ms p95 | same |
| Open a 10,000-block document | ≤ 500 ms | same |
| Idle CPU with a document open | ≤ 1 % | same |
| Assistant streaming | ≥ 99 % frames on time; UI never blocked by generation | same |

ProMotion could not be measured: this Mac's display is 60 Hz.

---

## 6. First-use experience (design only)

Mockups (static, rendered over real screenshots): [`first-use/`](screenshots/audit-v06/first-use/).
The editor backdrops in steps 3–4 contain the stray creation menu noted in V27; ignore it.

### 6.1 Welcome — `fu-01-welcome.png`, `fu-01-welcome-dark.png`

Shown once, on first launch, over the app (blurred), on an **Overlay** surface.

> **Welcome to Draft**
> A quiet place to write. Your notes live on this Mac.
>
> 📁 **Plain files you own** — Every note is a file in a folder you can open. No account, no cloud, nothing to sign in to.
> ▢ **Spaces for each part of life** — Keep work, study and home apart. Each Space has its own notes, tags and tabs.
> Aa **Write first, format later** — Just type. Select text for formatting, or type / to add a heading, list, table and more.
> ✦ **An optional private Assistant** — Download a 1.6 GB model later if you like. It runs on this Mac, works offline, and never sends your notes anywhere.
>
> **[ Start Writing ]**  ·  [ Take the 1-minute Tour ]
> Import notes…  ·  Show me the folder

Interactions:
- **Start Writing** (default, Return): closes the welcome, creates a note, caret in the title. The two seed notes stay in "Getting Started".
- **Take the Tour**: starts §6.2.
- **Import notes…**: the existing import flow, then the library.
- **Show me the folder**: reveals the vault in Finder; the welcome stays open.
- **Esc** or the close control = Skip (same as Start Writing without creating a note).
- Appears with **emphasis** motion; Reduce Motion: 150 ms fade.
- VoiceOver reads the title, then the four points as a list, then the buttons.

### 6.2 Tour — five coach marks

Each step dims the window (42 % scrim) except a rounded spotlight around one control, with a small card
beside it: step count, **Skip Tour**, **Back**, **Next** (← / → / Return / Esc work). The real UI stays live:
clicking the spotlighted control does what it says and advances the tour.

| Step | Mockup | Spotlight | Card text |
|---|---|---|---|
| 1 | `fu-02-tour-spaces.png` | Space name and sidebar | **Your sidebar and Spaces.** Everything in this Space is here: all notes, Today, Calendar and Tasks. Click the Space name to make another Space for work, study or home. |
| 2 | `fu-03-tour-new-note.png` | "+" | **Start a note.** Click + or press ⌘N. Notes are saved as you type, as plain files in Draft's folder on this Mac. *Data & Storage in Settings shows the folder.* |
| 3 | `fu-04-tour-writing.png` | Selected text and the formatting bar (the tour types a sample sentence into a scratch note) | **Write, then format.** Select words to bold, highlight or link them. On an empty line, type / to add a heading, checklist, table or collection. |
| 4 | `fu-05-tour-style.png` | Aa and the brush | **Make it look yours.** Aa formats the current block. The brush opens styles: backdrops, paper, fonts and separators. Style never changes your words. |
| 5 | `fu-06-tour-assistant.png` | Assistant button | **A private Assistant, if you want one.** Ask about a note or your whole Space, or have it summarize and rewrite. It needs a one-time 1.6 GB download and then runs entirely on this Mac. *Download it now, later from Settings → Assistant, or never. Draft works fully without it.* Buttons: **Start Writing** (primary), **Download Model (1.6 GB)** (secondary, starts the existing verified download only on click), Back |

The tour's scratch note is deleted at the end unless the user typed in it.

### 6.3 Replay and state

- **Help → Show Welcome…** and **Settings → About → Replay Tour** reopen it at any time.
- Stored as `settings.onboarding` (`{version: 1, completed: true, skipped?: true}`) in `library.json`, so a
  future tour revision can show only what changed. A new Space never re-shows it.
- Never shown while automation or a migration error screen is active.

### 6.4 Accessibility and motion

- Spotlight targets get an accessibility hint ("Tour step 2 of 5: Start a note").
- Tour cards are focus traps with Skip always reachable.
- Spotlight moves between steps with **emphasis** motion; Reduce Motion jumps with a 150 ms fade.
- Text contrast on the frosted card ≥ 4.5:1 in both themes.

---

## 7. Could not inspect, or only partly

| Item | Why | What to do |
|---|---|---|
| An unloaded Mac | Parsec was running throughout (likely your connection), GPU 70 % mean | Re-run the audit harness locally without Parsec; compare GPU-bound scenarios |
| ProMotion / 120 Hz | Display is 60 Hz | Measure on a ProMotion Mac with the same harness |
| Assistant answer selection colour in dark mode (your note) | A scripted drag did not create a selection | Select answer text by hand in dark mode |
| Hover states (library cards, toolbar pills) | Posted mouse moves did not trigger SwiftUI hover | Check by hand |
| Space switcher menu | The scripted click missed it | Open it by hand |
| Possible stuck menu after Esc (V27) | Probably a harness artefact; not proven | Open "+", Esc, ⌘N by hand |
| Import / export Open and Save panels | They are drawn by a separate system process and not captured | Inspect by hand (behaviour is covered by the workflow test) |
| Block drag frame timing | The frame scenario could not find its blocks; only the recording exists | Re-run with a fixed block lookup |
| Per-process GPU use | Needs `powermetrics` with admin rights | Run `sudo powermetrics --samplers gpu_power` during the scenarios |
| VoiceOver and keyboard-only paths | Out of scope here; still open from v0.5/v0.6 | v0.6 items 1, 3, 4 |
| Craft motion and performance | Only static Craft screenshots exist | Record Craft's transitions if motion parity matters |
| Recording frame rate | Capturing frames limits recordings to 31–60 fps; very short animations (< 30 ms) may be missed | Use QuickTime screen recording for final motion review |

---

## 8. Files

- `screens/` — 134 screenshots (`NN-name.png`, with `dark-`, `narrow-` and `narrow-dark-` variants); zoom captures at full resolution.
- `motion/` — 11 recordings: new-note, enter-editor-from-library, tab-switch, space-switch, panel-open-close, panel-switch, selection-toolbar, assistant-open-close, assistant-states, block-drag, library-hover.
- `first-use/` — 7 mockups: welcome (light, dark), tour steps 1–5.
- `data/audit-frames.json` — every frame measurement; `data/motion-analysis.txt` — transition timing; `data/sys.txt` — GPU and Parsec samples; `data/*-floating-size.txt` — floating Assistant size.
