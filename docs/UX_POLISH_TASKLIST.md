# Draft UX polish checklist

Working checklist for the 0.11.7 interaction and rendering pass. `[x]` only with screenshot or test evidence; `[~]` means implemented but not yet confirmed by hand; `[ ]` means not started.

Evidence lives in `docs/screenshots/ux-review-0.11.7/` (`before/` = handoff state at `f5ab754`, `after/` = this pass). Screenshots come from `DRAFT_AUTOMATION=block-actions-shots` and `DRAFT_AUTOMATION=effects-shots`, run against a throwaway vault (`DRAFT_DATA_DIR`) in a uniquely identified bundle (`org.draftnotes.Draft.claudereview`). The installed Draft.app is never touched.

## Liquid Glass surfaces (Claude review pass)

- [x] Floating glass is hosted inside the editor, not the window content view. A non-scrolling `FloatingLayer` sits above the page. The selection toolbar and block bar live in it, so they are clipped to the editor. Evidence: before, the toolbar overlapped the sidebar and title (`before/toolbar-over-sidebar.png`); after, it stays inside the editor (`after/block-actions-text-selection*.png`).
- [x] Glass refracts real page content. The top-edge scroll fade moved from a SwiftUI `.mask` on the whole editor to a `CAGradientLayer` mask on the scroll view only, so the floating glass is not composited in an offscreen pass. Evidence: text behind both bars is lensed at the rim in the light and dark shots.
- [x] Selection toolbar: rounded, readable icons, page-matched appearance (light lens on light pages in dark chrome), shared `ContextBarGlass` tint (white 0.5 / black 0.3). It is not an opaque plate. Evidence: `after/block-actions-text-selection.png`, `-dark.png`, `outline-without-hashes.png` (apricot).
- [x] Removed the toolbar frame hack. The toolbar was the glass view's content but was being given a host-coordinate origin. It now always sits at the glass origin, and callers and tests use `presentationView.frame`. The single-shape `NSGlassEffectContainerView` wrappers were removed too.
- [~] Toolbar entrance and exit. The plate and controls now fade together (before, the plate appeared instantly and the icons faded in), and there is now an exit fade, which was missing. Not checked frame by frame or under rapid reselection.
- [x] Block bar is centred at the bottom of the editor, sized to its buttons (it was a fixed width with oversized, clipped icons), has 14 pt symbols and a visible separator, and is native glass. Evidence: `before/block-bar-clipped-icons.png` vs `after/block-actions-selected*.png`, `after/block-actions-compact.png`.
- [x] Block bar hands-on (real pointer and keyboard, dark page). Select block expands the bar. Turn into, Style and More all open above the bar and apply (Heading and Glow applied and survived a relaunch). Escape collapses the bar. Selecting text hides the bar and shows the selection toolbar.
- [x] Block bar improvements from the hands-on pass, each checked by hand:
  - the bar steps aside while you type and returns on the next mouse move
  - Copy link shows a checkmark for 1.2 s
  - expand and collapse animate the width. Not verified frame by frame: the expand already looked complete at about 60 ms.
- [ ] Reduce Transparency and Increase Contrast captures for both bars.

## Controls and chrome (0.11.8 pass)

- [x] One Draft switch style (`DraftSwitchStyle` in `Components.swift`) replaces every tinted system switch: Settings rows, the sidebar list, the Style and Format panels, the effect editor and Find's Replace. It has a bright accent track, a white knob that stretches while pressed and a spring when it flips, and it respects Reduce Motion and the disabled state. VoiceOver uses the system toggle through `accessibilityRepresentation`. Checked by hand in light and dark (it flips on and off). The old "on" track was a dull navy in dark mode.
- [x] The document top-bar pills (Back, Insert, daily-note controls, Share, Format/Style/Info) and the location chip are Liquid Glass on macOS 26, not a fixed white plate. Icons use adaptive `.primary`. Checked by hand on a dark page, a light page and the lagoon image backdrop. Before, there were light-grey plates in dark mode.
- [x] Sidebar tab selector in light mode: a soft track behind the five tabs and an accent-coloured selected icon. Before, a white capsule sat on a near-white sidebar and was hard to see.
- [ ] Not yet converted: the tab strip's Assistant button and the side panels' surfaces.

## Document sidebar selector

- [x] The selected capsule shows its icon. Before, the glass container composited the capsule over the icon (white on white, `before/rail-selected-icon-hidden.png`). The icon is now the glass's content (`after/outline-without-hashes.png`).
- [x] The selection, not the hover, owns the glass. Hover used to move the capsule onto unselected tabs.
- [x] Press-and-slide across the five tabs with a real pointer. Pressed on Outline, slid to Tasks while held (the capsule moved, the icon stayed visible), and released on Find (Find selected).

## Window chrome

- [x] Reverted the traffic-light z-order hack (`zPosition` on AppKit's private title-bar container, forced alpha). Its cause, window-level glass, is gone. The traffic lights render normally in every after shot.

## Editor and rendering

- [x] Accent is an underline under the last line for headings, wrapped paragraphs and list items. Manual and Assistant paths both call `setDecoration`. Evidence: `after/effects-light.png`, `after/effects-dark-page.png`.
- [x] Glow is an inner halo with a clear centre and no drawn outline. The old shadow came from a source at 2.5% alpha, so it barely showed. My first fix, an outer halo, was clipped by the text view's sides into a card (`before/glow-clipped-card.png`). Increase Contrast gets a plain tinted outline. Needs the user's sign-off on taste.
- [x] Inline tags have no rectangular background fill (tests).
- [x] Removing a block colour does not leave an implicit `block` decoration (tests). The Assistant's `block_color` edit uses the same `setBlockColor`.
- [x] Separators can be inserted from the document `+` menu with style previews.
- [~] Full visual coverage of checklists, callouts, links, code and highlights after edits and reloads.
- [~] Title layout skips repeated `ensureLayout`. Broader profiling remains.

## Interaction

- [x] Clicking the background ends typing. Clicking empty page well below the text, or the backdrop, removes the caret, exits block selection and hides both floating bars at once. That area shows the normal arrow cursor. A 24 pt band under the text still puts the caret at the end. Checked by hand. The arrow cursor itself comes from the cursor rects and was not seen in screenshots.
- [ ] A block menu was open at the window's bottom-left once after a relaunch. I couldn't reproduce it on the next launch. Watch for it.

- [~] Selection toolbar and block bar share one motion curve and one glass look (`ContextBarMotion`, `ContextBarGlass`).
- [ ] Preserve selection and focus when formatting menus open or close (hands-on).
- [ ] Document and folder dragging, drop targets and undo in the library sidebar.

## Validation and release

- [x] `swift build` and the full `swift test` suite pass after this pass.
- [x] Light and dark screenshots of every changed glass surface (toolbar, block bar, rail).
- [x] Crash-recovery card. It appears only after the process is killed (`pkill`/SIGTERM), which is how test builds were being stopped. A normal Quit followed by a relaunch shows no card, and the document state and edits are restored. This is expected recovery behaviour, not a crash.
- [x] 0.11.7 published to the in-app update feed (GitHub release `v0.11.7` and signed `feed.json`). The live feed lists build 245, and the hosted zip matches its SHA-256. It is signed with the Apple Development identity and not notarized, the same as 0.11.5. The website is deliberately not updated: it is not deployed and needs a notarized build first.
