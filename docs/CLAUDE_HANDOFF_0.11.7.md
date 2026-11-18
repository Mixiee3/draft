# Claude handoff — Draft editor UX polish since 0.11.5

**Repository:** `Mixiee3/draft`  
**Branch:** `feature/editor-ux-smoothness`  
**Current commit:** `d97ada2` (`feat: ship editor UX polish preview`)  
**Baseline:** `e8c5403` (`docs: record 0.11.5 update and installer status`)  
**Current version:** `0.11.7` preview

## Review objective

Audit everything added since the 0.11.5 baseline. Treat the current implementation as a review candidate, not as proven-good UI. Preserve the last known-good stable app and verify every visual claim at native resolution on light and dark pages.

## What changed

This is the complete change inventory from `e8c5403..e9bf782`, not just the headline features.

### Release/version bookkeeping

- `628ab4a` added the 0.11.6 beta installer-test note and moved the version to 0.11.6.
- `d97ada2` moved the preview version to 0.11.7 and added the 0.11.7 preview notes.
- The branch was pushed as `feature/editor-ux-smoothness`; the stable `main` branch and installed app were not replaced.

### Liquid Glass and contextual toolbars

- Reworked `SelectionToolbar` to use macOS native `NSGlassEffectView`/`NSGlassEffectContainerView` on macOS 26+, with the legacy visual-effect fallback on older systems.
- Added document-aware appearance/tint handling so light paper does not inherit a dark chrome surface.
- Kept the native material at full alpha during entrance animation; only the outer toolbar fades. This avoids the unreadable flat-gray plate seen in earlier tests.
- Added `BlockActionBar` for block-mode actions, using the same material/tint strategy and shared motion curve.
- Added `ContextBarMotion` so the selection toolbar and block bar use the same animation timing.
- Added toolbar hover, pressed, keyboard-focus, accessibility labels, and diagnostic glass-state reporting.
- The selection toolbar now exposes `presentationView` and `glassDiagnostic` for automation and runtime inspection.
- Native glass is hosted at the window content level rather than inside the SwiftUI masked editor overlay, because AppKit needs a real window-level backdrop for refraction.
- The toolbar layout width calculation now uses the presentation host; native corner radius is set through `NSGlassEffectView` and the legacy path keeps its own layer radius.
- The text-selection animation now uses `ContextBarMotion`; the native glass itself is held at alpha 1 while the outer toolbar fades.
- The new block bar has compact and expanded modes, actions for select block, more, turn-into, style, and copy-link, and a menu-backed style picker for None/Focus/Block/Gradient/Glass/Glow/Accent.
- `DocumentEditorView` now owns the block bar, updates it on selection/theme/mouse/layout changes, and centers it at a fixed viewport position with compact and expanded widths.

### Document sidebar selector

- Reworked the document-rail selector in `RailView` to use `GlassEffectContainer`, interactive regular glass, and a matched `glassEffectID`.
- Added hover morphing and a simultaneous zero-distance drag gesture so pressing and sliding across the five tabs changes the active tab.
- Added adaptive selected-state tint/foreground contrast.
- `RailRow.icon` is now optional so outline child rows can omit the misleading numeric glyph.
- A macOS 26+ fallback path remains for older systems, with the previous capsule fill behavior preserved.

### Editor behavior and rendering

- Added/updated block-action positioning and selection/layout coordination in `DocumentEditorView`, `LayoutManager`, and `EditorController`.
- Kept text color, highlight, effect color, block color, and decoration layers separate.
- Fixed effect rendering coverage for accent/glow behavior; glow is intended to be a transparent halo without a hard inner rectangle.
- Added separator insertion/discoverability work and preserved Draft's existing separator styles.
- Added title-layout caching and related editor/layout polish.
- Added automation helpers and selection/formatting coverage used during the UX pass.
- `AutomationPolish` now captures compact/selected/dark/light/apricot-glass/block/text-selection states and writes `block-actions-checks.json` with accessibility settings, native-glass availability, geometry, and toolbar diagnostics.
- `AutomationSelection` now sends synthetic mouse events directly to the target window and measures the toolbar through its presentation view, including whether it is outside the host or covers the selected glyphs.
- `WindowChrome` explicitly raises the custom title-bar container above the traffic lights and forces the standard close/minimize/zoom buttons visible and opaque; this was added after the traffic lights became dim/covered.
- Block-mode selection invalidation was narrowed from the entire document to the previous/current selection ranges to reduce redraw work.
- Exiting block mode now invalidates only the prior block-selection range.
- `EditorController.onSelectionChange` was added so block-bar visibility follows selection changes.
- Removing an automatically-created `block` decoration together with block color now avoids leaving an unexplained empty rectangle, while preserving deliberate non-block decorations.
- `insertDivider` now accepts an optional variant and persists it in the divider node attributes; the document `+` menu exposes previews for line, strong, dotted, dots, wave, and tape.
- Title layout now skips repeated `ensureLayout` work when title text and width are unchanged.
- Short-document paper fill/height constants were adjusted to leave room for the bottom action bar.
- `DraftLayoutManager` now draws accent as a final-line underline for headings, paragraphs, and list items rather than allowing paragraphs to fall through to a rounded block treatment.
- Glow rendering was changed from a filled/stroked rectangle to a transparent source stroke plus shadow halo; the center is intentionally left transparent.
- Selected-block fill was changed from accent-colored fill to a lower-contrast text-colored fill.
- Inline tags no longer receive a rectangular background; document links and date chips remain explicit chip treatments.

### Tests and documentation

- Added/updated text-effect and link tests.
- Added `docs/UX_POLISH_TASKLIST.md` as the live checklist.
- Added `docs/CRAFT_COMPARISON_PLAN.md` with clean-room behavior comparisons and explicit limits on reverse engineering.
- Added preview notes in `Release/notes/0.11.7.md`.
- Added test coverage for effects persistence/render/undo/selection retention, block-color removal, block-effect undo/content IDs, Spectrum animation/gradient behavior, direction/palette behavior, and link picker/accessibility/backspace/round-trip behavior.

## Validation already performed

- `swift test -q` passed.
- `swift build -q` passed.
- `scripts/build-app.sh debug` passed.
- A uniquely identified ad-hoc test bundle was launched from `/tmp`, leaving the installed stable Draft app untouched.
- Manual CUA test confirmed the sidebar selector is visible and the selected-text toolbar icons are readable after the native-glass alpha/tint changes.

## Known limitations / likely review issues

These are intentionally not marked done:

- Native glass surfaces still need hands-on comparison against the target Craft behavior in both light and dark page themes. Confirm that the stronger tint does not remove too much refraction.
- The block-action bar needs a dedicated screenshot and interaction pass, especially its bottom-center placement, icon contrast, and entrance/exit animation.
- The selection toolbar needs animation verification during repeated selection changes, not just initial appearance.
- Sidebar press-drag handoff needs testing with all five tabs, including starting on one tab and ending on another without releasing.
- Selection/focus preservation around format menus is not fully verified.
- Document/folder dragging and undo behavior are still unchecked.
- Full visual coverage remains for headings, lists, checklists, callouts, links, code, highlights, block decorations, Increase Contrast, and Reduce Transparency.
- The crash-recovery card can appear in test bundles because the vault records a prior unclean session. Confirm whether that is expected recovery behavior or a real crash regression before shipping broadly.
- No production/notarized release was made. The branch is a preview handoff only.

## Explicit rework permission

Claude should not preserve these changes merely because they are already implemented. If any part is visually wrong, architecturally brittle, or below the project standard, rework it or revert it. In particular:

- Replace the custom/native-glass composition if it does not produce real readable refraction on the target macOS version.
- Rework or remove `BlockActionBar` if its placement, iconography, animation, or interaction model is not clearly better than the prior stable behavior.
- Rework the `RailView` `GlassEffectContainer`/gesture implementation if press-drag feels unreliable, causes accidental tab changes, or produces a fake gray selector.
- Revisit the traffic-light z-order change if it interferes with standard macOS window behavior.
- Revert the title/paper sizing constants if they create unexplained whitespace or scroll/layout regressions.
- Revisit accent/glow geometry from first principles if screenshots show clipping, outlines, rectangles, or inconsistent behavior across wrapped blocks.
- Do not assume the automation harness proves the UI is correct; it only provides repeatable checks and screenshots.
- It is acceptable to split this branch into smaller commits, discard experimental pieces, or return to the last known-good stable implementation before rebuilding the feature cleanly.

## Files to inspect first

1. `Sources/DraftEditor/SelectionToolbar.swift`
2. `Sources/DraftEditor/BlockActionBar.swift`
3. `Sources/DraftEditor/ContextBarMotion.swift`
4. `Sources/Draft/RailView.swift`
5. `Sources/DraftEditor/DocumentEditorView.swift`
6. `Sources/DraftEditor/LayoutManager.swift`
7. `Sources/DraftEditor/EditorController.swift`
8. `docs/UX_POLISH_TASKLIST.md`

## Suggested Claude review sequence

1. Checkout `feature/editor-ux-smoothness` at `e9bf782` and run the full test suite.
2. Build a uniquely named test app; do not overwrite `/Users/danielpekarek/Applications/Draft.app`.
3. Capture matched screenshots for light page, dark page, selected text, block mode, sidebar selector idle/hover/drag, and reduced-transparency/reduced-motion settings.
4. Verify toolbar geometry and animation timing with repeated selection changes and window resizing.
5. Trace any remaining rectangle/opacity issue through persisted marks → resolved attributes → layout-manager drawing → overlay geometry.
6. Mark each item in `docs/UX_POLISH_TASKLIST.md` only after visual and interaction evidence exists.
7. Only then decide whether to merge or revert individual pieces. Do not publish a stable update from this branch without notarization and a clean release review.

## Useful commands

```bash
git checkout feature/editor-ux-smoothness
git show --stat d97ada2
swift test -q
swift build -q
scripts/build-app.sh debug
```

## Handoff judgment

The code is pushed and builds, but this is not a claim that every Liquid Glass or animation detail meets the target standard. The most important next step is an adversarial visual/interaction audit, followed by a focused revert or correction of any surface that still reads as a flat translucent rectangle or loses its controls.
