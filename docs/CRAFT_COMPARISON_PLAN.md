# Craft comparison: Draft UX and clean-room improvement plan

**Updated:** 2026-11-16  
**Focus:** overall editor UX, text/block styling reliability, separator discoverability, and performance.  
**Scope:** research and plan only. No app code or note content was changed.

## What the references tell us

Craft's public material is useful for studying behavior, not its private implementation. Its documented editor patterns include a refreshed insert menu with clearer block icons, slash/Markdown commands, custom text and highlight colors, block colors, callouts, captions, and explicit color/contrast controls. The official [quick styling guide](https://www.craft.do/getting-started/b/4AECB2AC-447F-4E06-BA03-040007D74E8D/Quick-Text-Styling---Markdown-) documents separator shortcuts; the [3.5.4 release notes](https://www.craft.do/blog/craft-update-3-5-4) specifically mention refreshing the insert menu to make content types easier to discover; and the [3.6 color update](https://www.craft.do/blog/craft-update-3-6-0) documents custom colors and RGB/HSB controls.

The Craft screenshot provided here establishes a visual reference for a styled page, colored heading, backdrop, and sidebar. It does not establish Craft's internal renderer, animation timings, or frame rate. Those need interaction captures and measurements.

### Findings from the installed Craft bundle

Read-only inspection of `/Applications/Craft.app` adds a few concrete leads. Its bundled theme catalogue has 101 page themes; each theme specifies a theme ID, page text/background colors, font family, separator style, backdrop, and card assets. A separate catalogue has 59 washi presets. In 86 bundled document templates, block style records contain independent fields for text style, list style, decorations, decoration styles, alignment and color; inline runs separately record ranges and marks such as bold, italic, link, and highlight. This is evidence of a layered **document representation**, not evidence that Craft draws the live editor with CSS, Core Text, Metal, or any particular layout engine. A few CSS files under `PageStyles/` are scoped to page, comment preview, block-link, and AI-chat surfaces; their presence cannot establish the live editor's rendering path. The main executable is a large native Swift/Objective-C Mach-O that imports AppKit, SwiftUI, CoreText, CoreGraphics, WebKit, and Metal; imports alone do not identify which framework draws the note body.

Swift type names embedded in the installed binary give a more specific, still static map: `CraftBlockEditor` contains named text, separator, image, table and code renderers; a text container view; a block display view and interactive view; block selection background/indicator views; a multi-block decoration manager and decoration views; a decoration size calculator; local/global interactive-view pools; a local item-model pool; and a text-container image cache. The names establish that these components exist in the binary. They do **not** prove which are active in the current macOS editor, whether each block owns a text view, how virtualization works, or what draws any given pixel. We can inspect a matched runtime session and profile those questions later.

The actionable Draft comparison is to trace one style change through persisted marks, resolved style, glyph drawing, block background geometry, selection overlay, and exports. Keep the layers explicit and find the point where an inline effect accidentally creates or retains a block-level rectangle. Do not copy Craft's proprietary theme values, artwork, CSS, or pseudocode.

| Craft binary lead | Draft comparison | Prototype to validate |
| --- | --- | --- |
| Distinct text and separator renderer types | Draft uses `DraftLayoutManager` for text/block chrome and `DividerCell` for separators | Keep Draft's tape/wave art; test separate cached separator display without changing its saved format |
| Distinct block selection and decoration views/managers | Draft draws decoration and selected-block fill in `drawBackground` | Isolate selection overlay from decoration geometry and compare screenshots through style/selection transitions |
| Decoration size calculator | Draft mixes line-fragment unions and baseline-derived boxes | Compute stable visual bounds once per affected block, including wrapped/empty/last paragraphs |
| Local/global interactive-view pools and image cache | Current Draft code needs a measured allocation/redraw profile | Prototype visible-block reuse in a large document only if profiling shows view churn or full-document work |
| Separate block style attributes and inline run attributes in templates | Draft also has block and inline marks, but a color action can implicitly set a block decoration | Make color/effect commands explicit about their target layer and verify undo/exports |

These are hypotheses for Draft's own implementation, not a specification of Craft's private algorithms.

Craft's own [3.4.2 update](https://www.craft.do/blog/craft-update-3-4-2) says custom reminders were put in both the slash and block Edit menus, and its [3.5.0 update](https://www.craft.do/blog/craft-update-3-5-0) reports smoother large-document typing, lower CPU use, and faster opening. Those are useful behaviors and measurement categories; the published speedup figures are Craft's claims, not a Draft benchmark.

## Important separator finding

Draft already supports separator insertion through the editor's `+` menu, the macOS Insert menu, and the `/` command menu. The `/` shortcut is optional; a person does not need to know it to insert one. The current `+` is icon-only (with an “Insert block” hover/accessibility label), and choosing Separator inserts the document's current default style without previewing the other looks. The likely gap is discovering the alternate styles and choosing one at insertion time, not missing separator artwork or insertion support.

Draft's existing `line`, `dotted`, `tape`, and `wave` styles, plus per-separator `strong`, `dotted`, and `dots` variants, are intentionally preserved. The tape and other separators are user-approved and should not be removed, replaced, or visually redesigned as part of this work.

**Clean-room improvement:** provide an explicit “Separator” picker with small previews of the existing styles, directly from the Insert menu. Keep the current default as the one-click action; expose alternate looks as a submenu or compact picker. Add a subtle first-use slash-menu hint at an empty line and keep the menu-bar path. This improves findability without requiring users to memorize a shortcut.

Relevant Draft source: `Sources/Draft/DocumentScreen.swift` (the top-bar `+` menu), `Sources/DraftEditor/Commands.swift` (shared Insert/Slash commands), `Sources/DraftEditor/SlashMenu.swift`, `Sources/DraftEditor/EditorController.swift` (`insertDivider`), `Sources/DraftEditor/Attachments.swift` (`DividerCell` rendering), and `docs/FORMAT.md`.

## Draft's current foundation

- Text color, highlight, and effect color are represented separately in Draft's own document format.
- Draft already has block colors, callouts/captions, heading levels, a native `NSTextView` + custom `NSLayoutManager`, and custom gradient/Spectrum glyph rendering.
- The formatting toolbar has been deliberately reorganized and the user likes its current structure. Preserve its layout while fixing effect/color behavior and selection edge cases.
- The app already has shortcut and Insert menus, a first-run welcome/tour, collections, offline Assistant, MCP-reviewed edits, styles, and rich separators. Improvements should make these capabilities easier to discover and more dependable rather than adding another layer of competing controls.
- Draft's block context menu already supports actions such as Turn Into, duplicate, copy link, group/ungroup, move, reorder, and delete. Task due dates and local reminders also exist. I did not find a block comment/reaction model in the current source scan.

## Prioritized UX and implementation plan

### P0 — Make common editor actions discoverable

1. Keep the existing Insert `+` menu and its hover/accessibility label; add concise first-use guidance where it helps without permanently taking toolbar space.
2. Add a separator-style picker with previews of the *existing* tape, wave, dot, and line styles. Keep the saved document default and a quick one-click insert.
3. Review the Insert/Format/Block menus for overlapping names, hidden actions, and repeated commands. Keep one shared command registry so the menu bar, plus menu, slash menu, and shortcut sheet stay in sync.
4. Check keyboard-only paths and focus rings for every picker and menu.

**Done when:** a new user can insert a separator and choose its existing visual style without knowing a shortcut; insertion happens at the intended text boundary; one Undo removes it; all entry points agree.

### P1 — Fix selection, color, and effect correctness

1. Reproduce reported selection cases in throwaway notes: selecting a heading then the following paragraph, extending toward an empty trailing block, opening styling controls, applying an effect, and clicking away.
2. Fix range calculation so an empty trailing paragraph is not silently absorbed into the prior selection. Preserve selection, caret, and scroll anchor when opening/closing Style or Format.
3. Keep text foreground, highlight, static gradient stops, and Spectrum palette as independent values. Choosing an effect must not silently recolor text or reset effect parameters.
4. Add a compact custom color editor (hex, RGB, HSB), recent/favorite colors, and live preview for the selected range. Let users change an effect's own color without removing the effect.
5. Keep the current formatting toolbar layout. Improve the color/effect controls inside it and in the Style panel.

**Done when:** each action changes only the intended mark/range, text color/highlight/effect color remain independently editable, and one Undo restores the exact prior styling.

**Renderer trace:** for one reported failing note, record the selected character range and block IDs before and after the action, the saved style marks, the resolved attributes given to `NSLayoutManager`, the rectangles drawn by each overlay/decoration layer, and the final export. Compare those values to isolate the first layer that diverges. A screenshot alone cannot tell whether the unwanted rectangle came from layout, decoration, or selection state.

**Concrete Draft code leads:** `DraftLayoutManager.drawBackground` draws a full-width rounded rectangle whenever a block has `decoration == "block"` or any `blockColor`; it also draws a separate rounded selection fill for every selected block ID. These are two plausible sources of the reported rectangle, but the affected note/action still needs reproduction. `EditorController.setBlockColor` automatically adds the `block` decoration when a color is first set. When color is later removed, that decoration can remain, so “Remove block color” can leave a box behind. Trace and correct this interaction while preserving boxes the user deliberately chose. The Format panel labels its color grid as **block** color; inline text color is in the selection toolbar and effect editor, so the control hierarchy should make the distinction obvious.

### P2 — Make block styling and export dependable

1. Reproduce the unwanted rectangle and identify its source before changing it: selected-block outline, decoration card, block-color fill, text selection, or view border. Capture the same block before/after each style action so intentional styling remains intact.
2. Use one Draft-owned geometry path for block colors, callouts, decorations, selection outlines, and export.
3. Test wrapped paragraphs, headings, lists, nested lists, callouts, empty paragraphs, long notes, and first/last visible blocks. Cover dark/light appearance, narrow windows, Increase Contrast, and Reduce Transparency.
4. Validate every decoration at native resolution; tighten any clipping, overlap, collapsed final-block fill, inconsistent padding, or unreadable color.
5. Ensure editor, HTML, PDF, PNG, and the agent formatting preview share the same style meaning and explicit static export behavior.

**Done when:** style boxes follow the real text bounds, never cover text or vanish on wraps, and editor/export screenshots match.

### P3 — Audit the whole everyday workflow

Compare matched tasks in Craft and Draft: create a note, insert a separator/callout/table/image, format a selection, navigate by outline/folder/tab, open and close a side panel, search/open a note, and undo. Inspect empty states, hover states, selected states, narrow layouts, and keyboard paths.

Prioritize observed friction: unlabeled icon actions, modal or panel layout jumps, tabs that are hard to return to, repeated paths to the same action, unclear empty states, and controls that only reveal their function after a shortcut is known. Check current code and the live app before calling any of these a Draft bug; the Craft screenshot alone cannot establish parity.

Also compare the quality-of-life surfaces that shape the whole app: quick capture, shortcuts sheet, onboarding/tour, search/Quick Open, tab and folder navigation, updates/install/release notes, and accessibility. Recommend a new feature only when the matched workflow shows a meaningful gap.

**Done when:** each proposed change is tied to an observed issue, has a small interaction spec, preserves Draft's own design language, and includes a keyboard/VoiceOver path.

### P3a — Add a contextual block action bar, with a clear local-first scope

Study the Craft block bar the user described and compare it with Draft's existing block handle/context menu. Prototype a compact bar anchored to the selected block, separate from the text selection toolbar. Start with actions Draft already supports: More, Turn Into, style, due date/reminder for tasks, copy/open link, and move. Keep the bar stable as the selection changes and hide it when a text range is being edited.

Expose reminder and separator actions through both the visible block/Insert UI and the slash command registry. Craft's public release notes explicitly describe this multiple-entry-point pattern; the Draft implementation should use its own controls, names, and visual language.

Comments and emoji reactions are not simple visual controls: Draft currently stores local plain files and does not have a collaboration/comment service. First define whether “comment” means a private local annotation and whether an emoji is a personal marker or a shared reaction. If implemented locally, store annotations as Draft-owned block metadata with stable IDs, backup/export semantics, and undo; do not imply shared comments or counts without sync.

**Done when:** the common block actions are discoverable without right-click or memorized shortcuts, the bar never covers selected text, and all actions retain one-step undo where applicable. Any comment/reaction behavior has clear local-only labeling and survives relaunch/export as specified.

### P4 — Measure motion and performance before optimizing

1. Re-establish the baseline on the current build; the most detailed frame-pacing report is from v0.5.1 and cannot be treated as current.
2. Measure typing, scrolling, selection, panel open/close, tab/Space switches, window resize, and styled text on a 10,000-block note. Record display refresh rate, build, power/load conditions, Parsec state, p50/p95/p99 frame times, input latency, and CPU/GPU/memory.
3. Capture identical interaction sequences in Draft and Craft if the same hardware and capture path allow it. Do not infer animation performance from screenshots or compare compressed Parsec video to native Retina captures.
4. Profile before changing rendering. Prioritize only measured hot paths; keep Spectrum limited to visible text and avoid whole-document work per frame.

**Done when:** at least 99% of normal editor frames meet the display's frame budget (16.7 ms at 60 Hz), high-refresh displays are assessed against their own budget, and existing typing/navigation budgets remain green.

### P5 — Evaluate a renderer redesign with a vertical-slice prototype

Do not replace the whole editor on a visual hunch. First compare Draft's current AppKit `NSTextView`/custom `NSLayoutManager` path with a small isolated prototype that renders the same sample note using a candidate native path. Include ordinary text, multi-line selection, colored highlights, one block treatment, a tape separator, and a styled heading. Measure text sharpness, selection/caret correctness, scrolling frame times, and how often edits trigger layout work. Keep the production renderer until the prototype proves a measurable improvement and preserves Draft's file format and undo model.

**Done when:** a decision to rework the renderer is backed by native-resolution captures, a profile, a compatibility plan, and a prototype that beats the existing path on the user's actual style/scroll scenarios.

## Suggested implementation batches

1. **Audit + reproduce:** capture Craft and Draft equivalents; reproduce the unexpected rectangle, selection-range bug, effect-color bug, and separator insertion flow in disposable data.
2. **Styling reliability:** repair selection transactions and block geometry; validate text color/highlight/effects, existing separators, undo, persistence, and export.
3. **Discoverability + block actions:** add the separator preview picker and a contextual block bar for existing actions; scope any local comments/reactions separately.
4. **Whole-app polish:** audit navigation, search, empty states, onboarding, side panels, keyboard/VoiceOver, update UI, and motion for consistency.
5. **Scale + renderer decision:** measure the current renderer, prototype a vertical slice if profiling justifies it, then decide whether a broader rewrite earns its compatibility/performance cost.

Keep the installed stable Draft app separate and running during experiments. Build prototypes and test bundles under a distinct name/path; replace the stable app only when a later release is ready for the user's own testing.

## Reverse-engineering status and limits

- Craft Anything and REA inspected Craft's installed macOS executable and its native Mach-O structure. The universal binary must be thinned to arm64 before REA can bind Ghidra to the correct architecture.
- Ghidra 12.2 and its Apple-silicon native decompiler are installed under `~/Applications/Ghidra-12.2/`; Temurin JDK 25 is installed under `~/Applications/Temurin-25/`.
- Ghidra analysis of Craft's large executable exceeded REA's default startup limit. A later full import ran for nearly three hours without a completed analysis result and was stopped; logs showed unresolved-address and decompiler warnings. **No full decompilation or source recovery is claimed.** The bundle and template findings above came from direct read-only inspection and do not depend on a completed Ghidra import.
- Continue with targeted analysis of relevant executable regions only if it yields useful evidence. Ghidra can reconstruct pseudocode and symbols; it cannot recover Craft's original Swift source. Treat binary findings as leads and corroborate them with Craft's public docs and observed behavior.

## References

- [Craft Anything](https://github.com/storytold/craft-anything)
- [REA](https://github.com/morluto/rea)
- [Ghidra setup guide](https://github.com/NationalSecurityAgency/ghidra/blob/master/GhidraDocs/GettingStarted.md)
- [Craft quick styling guide](https://www.craft.do/getting-started/b/4AECB2AC-447F-4E06-BA03-040007D74E8D/Quick-Text-Styling---Markdown/)
- [Craft Insert menu changes](https://www.craft.do/blog/craft-update-3-5-4)
- [Craft color update](https://www.craft.do/blog/craft-update-3-6-0)
- Draft implementation references: `docs/FORMAT.md`, `docs/UI_AUDIT_V06.md`, `Sources/DraftEditor/Commands.swift`, `Sources/DraftEditor/Attachments.swift`, `Sources/DraftEditor/LayoutManager.swift`
