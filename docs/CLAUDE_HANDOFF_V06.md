# Draft handoff: finish v0.6 polish and integrate Codex/MCP

Updated 8 November 2026. This is a working handoff, not a claim that v0.6 is finished.

## Status on 8 November 2026 (end of the Claude session)

- `main` contains the v0.6 polish work and the Codex/MCP integration (merged from
  `feature/v0.6-polish` and `feature/codex-integration` through `feature/v0.6-codex-integration`).
- Every row of the v0.6 table in `ROADMAP.md` now has a measured result or an honest status. Open:
  rows 1, 2, 6, 20 need a person (VoiceOver, permission clicks, keyboard layouts and IME); row 3's
  `scripts/ax-audit.swift` needs a terminal with Accessibility permission; row 5 (localization) and
  the table parts of row 11 moved to v0.8; Present on a second display is untested.
- Checks: `swift test`, smoke, drag, links, style, structure, workflow, perf, ux-perf (3 of 4 runs
  under budget under Parsec load), assistant-test (offline), assistant-quality (27/30),
  agent-test, and an external stdio MCP round-trip in a throwaway vault.
- Codex's MCP registration points at `~/Documents/Draft/scripts/draft-mcp.sh`.

The sections below are the original handoff, kept for context.

## Start here: two concurrent workstreams

| Workstream | Checkout | Branch and state |
|---|---|---|
| Main app and v0.6 polish | `<your-checkout>` | `feature/v0.6-polish`, with substantial **uncommitted** code on top of the `4358749` polish baseline and this handoff commit. This is the active app checkout. Preserve every modification and untracked file. |
| Codex, OpenAI and MCP integration | `<codex-worktree>/draft-codex-integration/Draft` | `feature/codex-integration` at `fb30dd9`, clean and pushed. See its `docs/CODEX_INTEGRATION_HANDOFF.md`. |

`main` is at the v0.5.1 baseline (`3b75f26`) in the integration worktree. Verify local and remote refs again before merging; the references above can become stale. Keep the GitHub repository private.

The polish checkout currently has 20 modified tracked files and four untracked source/test files: `Sources/Draft/Components.swift`, `Sources/Draft/Onboarding.swift`, `Sources/DraftCore/WindowFit.swift`, and `Tests/DraftCoreTests/WindowFitTests.swift`. **Do not reset, clean, switch branches in that checkout, or overwrite these changes.** Inspect and continue them. On 8 November, `swift test` and `git diff --check` passed there; broader scripts and live UI checks were not run in this handoff pass.

The global Codex MCP registration currently points at the script in the integration worktree. After the code is merged, point it to the stable `~/Documents/Draft/scripts/draft-mcp.sh`, rebuild `DraftMCP`, restart the MCP connection, and verify the actual tools and a proposal round-trip. Do not delete the worktree until the stable connection works.

## References and user intent

- `docs/UI_AUDIT_V06.md` is the detailed pre-polish visual and performance audit. Its baseline predates the current v0.6 changes, so remeasure rather than treating every finding as still open.
- `docs/screenshots/audit-v06/` holds 134 screen captures, 11 transition recordings, seven onboarding mockups, and raw timings. Compare the current app to these and the Craft reference set; do not commit Craft captures or personal note screenshots.
- `docs/ROADMAP.md` has the 20-item v0.6 milestone, copied below as the completion checklist. `docs/FEATURE_PARITY.md` and `docs/FORMAT.md` need truthful updates after changes land.
- The integration worktree's `docs/CODEX_INTEGRATION_HANDOFF.md` describes the implemented provider, MCP tools, checks, limitations, and remaining work. Read it before touching Assistant or MCP code.

The goal is one coherent native macOS interface that feels calm, fast, precise and close to Craft's interaction quality, while retaining Draft's own visual identity, artwork, and code. Review **all** relevant UI code, shared controls and animation behavior, not just the audit's top 15. Fix bugs and performance regressions found during that review. Aim for at least 99% frames on time at 60 Hz during ordinary navigation and motion, with refresh-aware frame budgets on faster displays; retain the explicit action and typing budgets in the audit and roadmap. Measure on the actual machine, including the 10,000-block case, and report the conditions.

## Polish work to verify and finish

Current work appears to address several audit findings, but none is accepted solely because code exists. Verify each in the running app at normal and narrow widths, light and dark, with keyboard and pointer; compare screenshots and recordings to the audit. Priorities:

1. **Assistant window and review:** keep the floating window within the visible screen; make pinned and floating modes consistent; readable edit diffs and source cards; clear loading, cancellation, errors and focus; smooth open/close. The composer must be reachable on a small screen.
2. **Creation and editing:** center every icon-only `+`, including menus; start a new note with the caret in its title and an inviting full-page layout; use the arrow cursor over noneditable surfaces, the I-beam over editable text, and restore normal pointer/focus when menus or panels take interaction. Avoid scroll jumps and hard cuts.
3. **Consistent components:** unify spacing, typography, radii, icon sizes, button hierarchy, controls, hover/focus, panel materials, shadows, and toolbar alignment. Use restrained layered/translucent materials where they improve the UI. The formatting, Style, Info, Share, Settings, template, Quick Open and Assistant surfaces should feel like one app. Keep native accessibility and Reduce Motion behavior.
4. **Settings and onboarding:** replace dated controls, improve grouping and narrow layout; complete the first-use welcome and five-step tour already started in `Onboarding.swift`; make Skip, Back, Next, keyboard navigation and replay work. Never download the 1.6 GB model without a deliberate click.
5. **Motion and responsiveness:** consistent durations/easing for sheets, popovers, panels, tabs and note creation; no cut to empty slabs, no jitter, no unnecessary animation on Space switching. Respect Reduce Motion. Fix collection/gallery/list scrolling, large document layout, tab/Space switching, document opening, and broad invalidation without hiding regressions behind caches.
6. **Small details:** live Info counts, Share tabs that do not truncate, narrow tab overflow, centered titlebar traffic lights, proper panel edges, readable Assistant selection and diff, safe cursor states, and any other visible discrepancy found in the full review.

Use `scripts/ux-perf.sh`, `scripts/perf.sh`, the audit's scenarios, and real window captures. Current uncommitted work includes a shared component layer, onboarding, window fit helpers, Settings changes and broader UI edits. Inspect these before adding alternatives or merging.

## v0.6 "Every window" completion checklist

These are the current milestone commitments from `docs/ROADMAP.md`. Verify and update each row with evidence. Do not mark a row complete merely because it compiles. If scope must be revised, explain the changed scope and leave an honest partial/planned status.

1. VoiceOver pass: Calendar, Tasks, `[[`/`#` pickers, Style Gallery, export, tables, collections, template picker and Space switcher; keyboard-only Kanban moves.
2. Real notification and calendar permission prompts: Allow works; Don't Allow resets the setting and explains why.
3. Separate-process Accessibility API audit of SwiftUI screens with zero unnamed release controls.
4. Full keyboard paths and visible focus rings for every panel, popover and sheet.
5. String Catalog localization, two non-English locales and spelling-language control; no clipped or untranslated visible UI at standard and narrow widths.
6. AZERTY, QWERTZ and Dvorak shortcuts; Japanese and Chinese IME composition without early commit or broken blocks.
7. Searchable shortcuts sheet that matches real menu shortcuts.
8. Sidebar section visibility and reordering, persisted across relaunch.
9. Focus mode with chrome hidden/current block emphasized; Escape exits, typing stays within budget.
10. Present mode with heading-based slides, arrow navigation and second-display full screen.
11. Relation picker search, table column reordering in one undo, and rich text cells that round-trip.
12. Per-Space theme, daily notes and tag settings, persisted and applied on switch.
13. Return-key p95 under 33 ms in ten consecutive performance runs.
14. Tab-switch p95 under 50 ms and Space-switch p95 under 100 ms (`scripts/ux-perf.sh`), with localized observation invalidation.
15. Open a 2,000-block document from the library in under 250 ms.
16. Assistant long-document map/reduce, including a truthful notice of how much was read.
17. Cached Assistant prompt reuse, making a second question start answering at least twice as fast.
18. On-device speech input and output, no network; show Voice Glow/Ring only for actual listening/speaking.
19. Fixed 30-question note benchmark with expected facts and citations, default model score at least 90%, tracked per release.
20. VoiceOver pass for Assistant window, sources and preview, including opening a source and applying an edit without a pointer.

The polish audit adds a welcome/tour flow and broad visual/performance acceptance beyond these numbered rows. Treat that as part of this release rather than quietly replacing the numbered milestone.

## Codex/MCP integration: retain and complete

The clean `feature/codex-integration` branch adds an optional OpenAI API provider and `DraftMCP` stdio bridge. The local Liquid model remains default. OpenAI uses a user-provided API key in Keychain, explicit context review, and Responses API streaming with `store: false`. This is **not** ChatGPT subscription sign-in and is **not** a full Codex agent inside Draft. Do not label it as such.

The MCP bridge can read/search notes and structure; `draft_formatting_guide` describes Draft's styles, typography, highlights, block colors, alignment, focus/block decoration, and line/strong/dotted/three-dot/wave/tape separators. `draft_propose_note_edits` can propose whole-note Markdown replacement or targeted text/formatting changes, plus a document style. It queues a request; it never writes document JSON. Draft shows a review sheet and applies accepted edits through the editor with revision recheck, backup/index update and one Undo step. This is the required trust boundary. Keep links, images, nested pages and attachment protection intact; test conflicts and stale revisions. `draft_request_status` reports the outcome.

After completing the polish branch, merge/rebase the integration branch carefully. Reconcile `AssistantView`, Settings, design system, `AppModel`, core model and tests line by line so neither feature set is lost. Polish cloud and proposal screens to the unified UI, including light/dark, narrow/floating, long diff, selection/focus, accessible labels and errors. Test a full external MCP read → formatting guide → proposed edit → on-screen review → accept → saved note → one-step undo flow in a **throwaway vault**. Test reject and stale-revision paths. A live OpenAI request needs a user-owned API key and opt-in; do not claim that test passed without it. Never use, alter or commit the personal vault as a test fixture.

The user wants Codex eventually able to perform nearly all ordinary note operations with confirmation: create/rename/move notes; append/insert/delete/reorder blocks; apply saved styles; links, tags and tasks; advanced formatting including highlights and wave/tape separators. Extend the same reviewed, app-mediated proposal architecture in coherent groups. Avoid turning MCP into a direct file mutator. Record any remaining capabilities as explicit roadmap/parity rows with acceptance checks, rather than implying full agent control. Genuine Codex app-server sign-in is a separate future integration; verify current official support before building or claiming it.

## Suggested execution and release gates

1. Confirm Git branches/remotes and preserve all uncommitted v0.6 work. Inspect current diffs, audit and reference captures. Commit coherent polish slices to the existing polish branch.
2. Run the app and finish the broad UI, onboarding, motion and performance pass. Check normal/narrow, light/dark, cursor/focus, Reduce Motion, keyboard and VoiceOver. Produce new comparison captures in a dedicated folder using sample content only.
3. Work through all 20 v0.6 rows, with targeted tests and realistic acceptance evidence. Use code review and real interaction for visual/behavioral claims. Document any unmet row accurately.
4. Run `swift test`, `scripts/smoke.sh`, `scripts/drag-test.sh`, `scripts/links-test.sh`, `scripts/style-test.sh`, `scripts/structure-test.sh`, `scripts/workflow-test.sh`, `scripts/assistant-test.sh`, `scripts/perf.sh`, and `scripts/ux-perf.sh` as applicable. Fix concrete failures. Check old vault migration and existing local-model offline flow in a throwaway vault.
5. Merge the tested polish branch into `main`, then integrate the Codex/MCP branch with careful conflict resolution and fresh full checks. Update the stable MCP registration and verify it after a restart. Keep the remote private and push only reviewed source/tests/docs and Draft-owned sample captures.
6. Update `ROADMAP.md`, `FEATURE_PARITY.md`, `FORMAT.md`, Assistant privacy/setup docs and release notes. Report each v0.6 item as complete/partial/planned with evidence, performance numbers versus budgets, screenshots path, commits, and what still needs user input (for example, live API key or OS permission clicks).

If usage stops mid-task, commit and push only a coherent WIP branch, leave `main` untouched, and write a short exact resume note: branch/commit, uncommitted files, tests passing/failing, the next concrete operation, and the full remaining checklist.
