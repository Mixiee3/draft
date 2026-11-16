# Draft UX polish checklist

This is the working checklist for the Craft-inspired interaction and rendering pass. We are recreating behaviors with Draft's own code and keeping the existing tape/separator system.

## In progress

- [~] Document-rail selector now follows a pointer drag across all five tabs; the gesture is simultaneous with button taps so press-drag handoff is preserved. Needs hands-on confirmation.
- [~] Bottom block-action bar uses native glass content layering and adaptive tint; needs hands-on confirmation.
- [~] Sidebar selector now uses the interactive regular glass variant; needs hands-on confirmation.

## Editor and rendering

- [x] Stabilize inline tag styling so tags no longer receive unwanted rectangular background fills; document-link/date chips remain explicit.
- [x] Keep separators as first-class blocks and make insertion discoverable from the document `+` menu with visible style previews.
- [~] Verify headings, lists, checklists, callouts, links, code, highlights, and block decorations after edits and reloads. Accent now renders as a consistent underline for headings and body/list blocks; Glow now uses a transparent halo without a hard inner outline. Full visual coverage remains.
- [~] Reduce unnecessary editor/layout work during typing, scrolling, and selection changes. Title layout now skips repeated `ensureLayout` calls when text and width are unchanged; broader profiling remains.

## Interaction and UX

- [~] Make the contextual selection toolbar and block-action bar share one interaction model and motion curve. Both now use the shared ContextBarMotion curve; interaction-model consolidation remains.
- [~] Add clear hover/pressed/focus states with keyboard and VoiceOver labels. Selection-toolbar hover, pressed, keyboard-focus, and labels are implemented; block-bar coverage still needs hands-on confirmation.
- [ ] Preserve selection and focus when formatting menus open or close.
- [ ] Verify document/folder dragging, drop targets, and undo behavior in the library sidebar.

## Validation and release

- [x] `swift build -q` and the full `swift test -q` suite pass, including `testToolbarFlipsBelowNearTopAndClamps`; all 157 DraftCore and 11 DraftAssistant tests pass.
- [ ] Capture light/dark screenshots for every changed glass surface.
- [~] Test bundle launches after the embedded framework is copied and the bundle is re-signed; ad-hoc signing is required for local test packaging. Stable app remains untouched.
- [ ] Update the changelog/status page only after the visual and interaction checks pass.

## Working checkpoint

The current working tree is the fallback checkpoint for this pass. No installed/stable app bundle is modified; test builds are launched from `/tmp/Draft-LiquidGlass-Test.UxetX7.app`.
