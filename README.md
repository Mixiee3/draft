# Draft

A free, open-source, local-first notes and document app. **First release: native macOS.**
No account, no network, no telemetry — your notes are plain files on your Mac.

![Draft document](docs/screenshots/document.png)

## Build and run

Requirements: macOS 14 or later, Xcode 16+ (Swift 6 toolchain). No other dependencies.

```bash
scripts/build-app.sh          # builds build/Draft.app (release)
```

```bash
open build/Draft.app
```

Development loop and checks:

```bash
swift run Draft               # run without bundling
```

```bash
swift test                    # 111 tests: format, vault, index, links, tags, dates, styles, HTML/site export, online parsing, editor, blocks, paste, grouping, media
```

```bash
scripts/smoke.sh              # end-to-end: edit, group, trash, quit, relaunch; verify content, page, trash, backups, search, link, ungroup
```

```bash
scripts/perf.sh               # opens a 10,000-block document and checks editing and index-rebuild budgets
```

```bash
scripts/links-test.sh         # links, backlinks, tasks, daily notes: write, relaunch, delete index/ and relaunch
```

```bash
scripts/style-test.sh         # saved styles, block fonts, cards, separators; styled PDF/HTML/PNG and an offline site
```

```bash
scripts/drag-test.sh          # drags a block with mouse events posted through the app; checks undo, redo, relaunch
```

Your notes live in `~/Library/Application Support/Draft/Vault` (Settings → Data & Storage →
Show in Finder). Set `DRAFT_DATA_DIR=/some/folder` to use a different vault.

## Architecture (v0.1)

| Layer | Target | Notes |
|---|---|---|
| Portable format | `Sources/DraftCore` | Foundation only. Document tree, library index, migrations, vault (atomic writes), Markdown/JSON export, styles, seed content. This is the layer a future Windows app re-implements; see [`docs/FORMAT.md`](docs/FORMAT.md). |
| Editor | `Sources/DraftEditor` | AppKit + **TextKit 1** (`NSTextView`, custom `NSLayoutManager`). One text paragraph = one block with a stable id. Semantic attributes (block info, inline marks) are separate from derived display attributes. |
| App shell | `Sources/Draft` | SwiftUI: rail, tabs, library, panels, settings. Hosts the editor through `NSViewRepresentable`. |

Key decisions:

- **Four separate layers**: semantic content (`content`), inline marks (inside content), block style
  (`blockColor`, `decoration`, `textAlign` attrs), document appearance (`appearance`: style id +
  sparse overrides + cover). Restyling never touches content (tested).
- **One command registry** (`EditorCommands`) drives the selection toolbar, `Aa` panel, slash menu,
  `+` insert menu, menu bar and shortcuts; every command is undoable through `NSTextView`'s undo.
  Markdown conversions run as their own undo step, so ⌘Z restores the literal text.
- **Selection toolbar** is an AppKit overlay that never takes focus from the text, so the selection
  survives the color palette and link field; it flips below near the top, clamps horizontally,
  dismisses with Esc, and is keyboard reachable with ⌥F10 (←/→, Return, Esc).
- **Storage**: `library.json` (index) + one JSON file per document + content-addressed `assets/`.
  Explicit schema versions; migrations back up the original first; files from a newer schema open
  read-only; unknown fields and unknown block types are preserved verbatim.
- **Nested pages** are child documents referenced by a `pageCard` block (card or page presentation).
- The earlier Electron prototype was replaced; its data format, styles, seed copy, export rules and
  migration design were ported to `DraftCore` unchanged in spirit.

## Docs

- [`docs/ROADMAP.md`](docs/ROADMAP.md) — versioned plan from v0.1 to 1.0 and beyond (incl. Windows).
- [`docs/FEATURE_PARITY.md`](docs/FEATURE_PARITY.md) — evidence-backed gap matrix with acceptance checks.
- [`docs/FORMAT.md`](docs/FORMAT.md) — the portable on-disk format.
- [`docs/screenshots/`](docs/screenshots) — Draft captured by `DRAFT_AUTOMATION=screenshots`.

Reference screenshots of other products used during design research are **not** part of this
repository and must not be committed. All Draft artwork (scenes, separators, icon) is original and
generated in code.
