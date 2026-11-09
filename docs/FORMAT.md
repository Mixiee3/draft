# Draft vault format (schema 2)

The schema grows only by **additive** node types and optional attributes. A Draft that does not know
a node type keeps it verbatim and shows it as a preserved placeholder, so older builds never lose
newer content; the schema number changes only for changes that need a migration.

This is the contract every Draft implementation (macOS today, Windows later) reads and writes.
The reference implementation is `Sources/DraftCore`. All JSON is UTF‑8; timestamps are Unix epoch
**milliseconds**; ids are `[A-Za-z0-9_-]{1,64}`.

```
<vault>/
  library.json            index (schemaVersion, space, spaces, folders, docs, settings, tabs)
  docs/<docId>.json       one document
  assets/<sha256-32>.<ext> images, covers and attached files, content-addressed (extension: 1–10 lowercase letters/digits)
  backups/                copies written before any migration (never read by the app)
  history/<docId>/<ms>.json automatic local backups of a document (≤ 1 per 10 min, 30 kept)
  index/index.json        derived link/tag/task index (safe to delete; rebuilt on launch)
  assistant/<spaceId>.json local Assistant history; <spaceId>-openai.json optional cloud history
  agent-requests/<requestId>.json local MCP proposals (Codex, Claude Code) and their outcome
```

## Rules for every implementation

1. **Atomic writes**: write a temp file in the same directory, then rename.
2. **Never drop unknown data**: unknown top-level keys of `library.json` / document files, unknown
   node types and unknown attributes must be written back unchanged.
3. **Schema versions**: if `schemaVersion` is higher than supported, open read-only and refuse to
   write. When migrating, write the original into `backups/` first, run the migration on an
   in-memory copy and compare it with the original (titles, styles, folders, parents, trash state,
   block ids, text, links); write only if nothing differs, otherwise stay read-only.
4. **Block ids** are stable. On load, a block without an id or with a duplicate id gets a new one;
   the first occurrence of an id always keeps it.

## library.json

```json
{
  "schemaVersion": 2,
  "space": { "id": "s_…", "name": "My Space" },
  "spaces": [{ "id": "s_…", "name": "My Space", "tabs": [ … ], "activeTabId": "t_…" }],
  "folders": [{ "id": "f_…", "spaceId": "s_…", "name": "Getting Started", "parentId": null, "color": "#5b6cf0", "order": 0, "createdAt": 0 }],
  "docs": { "d_…": { "id": "d_…", "spaceId": "s_…", "title": "…", "folderId": "f_…", "parentDocId": null,
                     "createdAt": 0, "updatedAt": 0, "viewedAt": 0, "starred": false, "styleId": "paper",
                     "excerpt": "…", "searchText": "…", "words": 0, "blocks": 0, "tint": "#…" } },
  "settings": { "theme": "system", "accent": "#5b6cf0", "useDocStyleForApp": true, "…": "…" },
  "tabs": [{ "id": "t_…", "view": { "kind": "all" } }, { "id": "t_…", "view": { "kind": "doc", "docId": "d_…" } }],
  "activeTabId": "t_…",
  "expandedFolders": ["f_…"]
}
```

**Spaces (schema 2).** `space` is the active Space; `spaces` lists all of them, each with the tabs it
had open when it was last left (`tabs`, `activeTabId`; the active Space's live tabs are the top-level
`tabs`). Folders and documents belong to the Space in `spaceId`. Tags, tasks and the sidebar are per
Space; user styles and templates are shared. `DocMeta.template` (a category name) marks a saved
template; templates are listed in every Space. **Migration 1 → 2** sets `spaceId` on every folder and
document to the existing Space and adds `spaces: [space]`; the original is kept as
`backups/<time>-library.v1.json`.

Document tabs may carry `scrollY`, `selStart`, `selLength` (where the user was; optional). `DocMeta.deletedAt`
marks a document in Recently Deleted. `DocMeta.dailyDate` (`yyyy-MM-dd`, optional) marks a daily note;
there is at most one live document per date.

Settings added in schema 1 (all optional, defaults in parentheses): `weekStart` (0 = system, 1 = Sunday,
2 = Monday), `dayStartHour` (0), `showDailyNotes` (true), `dailyTemplateId`, `tagColors`
(`{lowercased tag: "#hex"}`), `tagRules` (`{ignoreHex: true, ignoreNumeric: true, custom: []}`),
`reminders` (false), `reminderHour` (9), `calendarEvents` (false), `dateStyle` (`chip`/`text`), `calendarFilter`
(`all`/`tasks`/`notes`), `calendarShowCompleted` (false), `onlineImageSearch` (false), `linkPreviews` (false),
`assistantModel` (a model id such as `lfm2.5-2.6b-qad-q4`; absent until chosen), `assistantPinned` (true).

Settings added in v0.6 (optional, defaults in parentheses): `paperFollowsAppearance` (true; display
only: an untouched Paper document is drawn dark in a dark app, the file and exports keep the light
style), `onboardingSeen` (0; the welcome/tour version already shown), `sidebarHidden` (`[]`; any of
`shared`, `today`, `calendar`, `tasks`, `starred`, `folders`, `tags`, `trash`) and `sidebarOrder`
(`["starred", "folders", "tags"]`; readers drop unknown names and add missing ones).

**Per-Space settings (v0.6).** Each entry in `spaces` may carry `settings` with the Space's own
`theme`, `accent`, `showDailyNotes`, `dailyTemplateId`, `dayStartHour`, `tagRules` and `tagColors`
(each optional). The active Space's values live in the top-level `settings`; when Draft switches
Space it saves them into the outgoing Space's `settings` and applies the incoming Space's. A Space
without `settings` keeps the current values. Older readers ignore the field.

`userStyles` (top-level, optional; written only when non-empty): `[{id: "u_…", name, base: "<built-in id>",
tokens: {…appearance tokens…}, pinned?, createdAt}]`. A document's `appearance.styleId` may name a user
style; if it is missing, readers use the built-in style `paper` (Draft itself moves documents to
`base` when a style is deleted).

`excerpt`, `searchText`, `words`, `blocks`, `tint` are **derived** and may be rebuilt from the
document files at any time. `parentDocId` marks a nested page.

## docs/&lt;id&gt;.json

```json
{
  "schemaVersion": 1, "id": "d_…", "title": "Welcome", "createdAt": 0, "updatedAt": 0,
  "appearance": { "styleId": "tidepool", "overrides": { "pageColor": "#ffffff" }, "cover": { "assetId": "….png", "focalY": 0.5, "crop": { "x": 0, "y": 0.1, "w": 1, "h": 0.5 }, "ratio": "2:1" } },
  "content": { "type": "doc", "content": [ … nodes … ] }
}
```

### Nodes (ProseMirror-style JSON: `type`, `attrs`, `content`, `marks`, `text`)

| type | attrs | content |
|---|---|---|
| `paragraph` | `id`, `variant?`=`"caption"`, `blockColor?`, `decoration?` (`focus`/`block`), `textAlign?`, `font?` (`system`/`serif`/`mono`/`rounded`; also on `heading`, `listItem`, `taskItem`, `toggleItem`) | inline |
| `heading` | `id`, `level` 1 Title · 2 Subtitle · 3 Heading · 4 Strong | inline |
| `blockquote` | `id` | paragraphs |
| `codeBlock` | `id`, `language?` | one text node, `\n` line breaks |
| `bulletList` / `orderedList` (`start`) / `taskList` | `id` | `listItem` / `taskItem` |
| `listItem` / `taskItem` (`checked`) | `id`, `blockColor?`, `decoration?` | paragraph, then paragraphs or nested lists |
| `horizontalRule` | `id`, `variant?` (`strong` / `dotted` / `dots`; absent = the document's separator style) | — |
| `pageBreak` | `id` | — (starts a new page when printing) |
| `callout` | `id`, `icon` (emoji, default 💡) | paragraphs; block color comes from the paragraphs' `blockColor` |
| `toggleList` | `id` | `toggleItem` |
| `toggleItem` | `id`, `open` (bool; collapsed children are hidden, never dropped) | paragraph, then paragraphs or nested lists |
| `image` | `id`, `assetId` or `src`, `alt`, `caption?`, `width?` (fraction 0.15–1 of the text width; absent = natural size up to full width) | — |
| `file` | `id`, `assetId` (content hash + original extension), `name` (original file name), `size` (bytes) | — |
| `pageCard` | `id`, `docId`, `title` (cached), `presentation` (`card`/`page`), `size?` (`compact`/`medium`/`feature`), `preview?` (`standard`/`icon`/`gallery`) | — |
| `linkPreview` | `id`, `url`, `title`, `summary?`, `site?` (filled from the page when link previews are on) | — |
| `table` | `id` | `tableRow` (the first row is the header) |
| `tableRow` | — | `tableCell` |
| `tableCell` | — | inline (text with marks) |
| `collection` | `id`, `data` (below) | — |
| `text` | — | `text`, `marks?` |
| `hardBreak` | — | — |

Marks: `bold`, `italic`, `underline`, `strike`, `code`, `highlight {color}`, `textStyle {color}`,
`link {href}`, `docLink {docId, blockId?}`, `date {date}`.

- **`docLink`** marks the text of a link chip. `docId` is the linked document; `blockId`, when
  present, makes it a block reference. The text is a cached title: readers show the target's current
  title (or the block's text) and may rewrite the text. If `blockId` is no longer in `docId`, look it
  up in the other documents (blocks keep their ids when moved or grouped). A target that cannot be
  found is shown as missing; the mark is kept so the link works again if the target returns.
- **`date`** marks a date chip; `date` is `yyyy-MM-dd` or `yyyy-MM-ddTHH:mm` (local time). The text
  is a cached absolute label ("Mon 9 Nov", "Mon 9 Nov 15:00"); builds before v0.4 wrote relative words,
  which readers replace on load.
- **Tags** are plain text: `#` + a letter, digit or `_`, then letters, digits, `_`, `-`, `/`, not
  preceded by a letter, digit, `#`, `&`, `/` or `\`. Hex colors (`#fff`, `#a1b2c3`), numbers (`#12`) and
  the custom words in `tagRules` are not tags. Text in `code`, `link`, `docLink` and `date` marks and
  in code blocks never contains tags.
- **Task due date**: an optional `due` attribute on `taskItem`, else the first `date` mark in the
  task's first paragraph, else the `dailyDate` of the document holding it.
- Older builds keep `docLink` and `date` text as plain text with the unknown mark preserved.

### Collections

`collection.data` is `{name, fields, views, activeView?, items}`:

- `fields`: `[{id, name, type, options?}]`, `type` one of `text`, `number`, `select`, `multiSelect`,
  `date`, `checkbox`, `relation`, `url`; `options` lists select choices.
- `views`: `[{id, name, type: table|gallery|kanban, sort: [{field, ascending}], filters: [{id, field,
  op, value?}], match: all|any, groupBy?, visible?: [fieldId], calc: {fieldId: count|empty|filled|sum|average|min|max|checked}}]`.
  Filter `op`: `is`, `isNot`, `contains`, `isEmpty`, `isNotEmpty`, `gt`, `lt`, `before`, `after`, `checked`,
  `unchecked`. The field id `title` means the item's page title.
- `items`: `[{id, docId, values: {fieldId: value}}]`. Each item is a page: `docId` is a document whose
  `parentDocId` is the document holding the collection; its title is the item's name. Values are
  strings (`text`, `select`, `url`, `date` as `yyyy-MM-dd`), numbers, booleans (`checkbox`) or arrays
  of strings (`multiSelect`; `relation` holds document ids).

Markdown export writes a collection as a table of its active view, and each item page with its
values as YAML frontmatter. A collection's CSV has a `Name` column plus one column per field
(multi-values joined with `; `).

### assistant/&lt;spaceId&gt;.json and assistant/&lt;spaceId&gt;-openai.json

`{"schemaVersion": 1, "spaceId": "s_…", "provider": "local|openai", "messages": [{id, role: user|assistant, text, action?, scope?,
sources?: [{n, docId, blockId?, title, text}], createdAt, failed?}]}`. `action` is one of `ask`,
`summarize`, `explain`, `rewrite`, `shorten`, `expand`, `outline`; `scope` is `selection`, `document` or
`space`. Sources record which blocks an answer cited. History never changes a document. Models are not
part of the vault: they live in `~/Library/Application Support/Draft/Models`.

### agent-requests/&lt;requestId&gt;.json

An MCP client (Codex, Claude Code) may queue a proposed change here; it never writes `docs/` or
`library.json`. A proposal is

`{"id": "request_…", "documentId": "d_…" | "new", "documentTitle", "instruction", "expectedRevision",
"edits": [{"action", "blockId", "value?", "text?", "expectedText?", "target?", "position?"}], "createdAt",
"status": "pending" | "accepted" | "rejected" | "stale" | "failed", "result?", "client?"}` (`client` is the
MCP client's reported name).

`agent-requests/activity.jsonl` holds one line per MCP call, `{"time", "client", "tool", "document?"}`,
never note text; Draft keeps about the last 1,000 lines. Per-client permissions live in
`settings.agentPermissions`: `{"<client name>": {"read": true, "propose": true, "destructive": false}}`;
a client not listed gets those defaults.

`expectedRevision` is the SHA-256 of the document's JSON (sorted keys) for note proposals, and of the
sorted list of Space and folder ids (`s:<id>`, `f:<id>:<spaceId>`) for `create_document`. Library
actions are standalone: `create_document` (`documentId` and `blockId` `"new"`, `expectedText` = title,
`text` = Markdown, `value` = folder id or `unsorted`, `target` = Space id), `rename_document`
(`expectedText` = new title) and `move_document` (`value` = folder id or `unsorted`, `target` = Space
id), `create_folder` (`documentId`/`blockId` `"new"`, `expectedText` = name, `value` = parent folder
id, `target` = Space id) and `delete_document` (moves the note and its nested pages to Recently
Deleted). A multi-note proposal has `documentId` `"multi"`, empty `edits`, and
`"parts": [{"documentId", "documentTitle", "expectedRevision", "edits"}]` (2–20 notes, note edits
only), applied all-or-nothing. Table actions (`table_set_cell`, `table_insert_row`, `table_delete_row`,
`table_move_row`, `table_insert_column`, `table_delete_column`, `table_move_column`) use the table's
id as `blockId`, a row id or cell id as `target`, the anchor row or cell id as `value` for moves, and
`text` for cell Markdown (cells separated by `|` for new rows and columns). Note actions are listed in `draft_propose_note_edits`; `target` names the other block for
`move_block` and `position` is `before`/`after` for `insert_blocks` and `move_block`.

The running app shows each proposal for review. Applying rechecks the revision (a mismatch sets
`stale`), applies note edits through the editor as one Undo step and library actions with one Undo
step of their own, saves (with the usual backup) and updates the index. `failed` means the edit was
refused (for example a phrase that no longer occurs once, or deleting an image, file, table or page
card) and nothing changed. Older readers ignore `target` and `position`. This directory is local
coordination data, not a source of truth for notes.

### index/index.json (derived)

`{"version": 2, "rules": "<tag rules key>", "entries": {docId: {"updatedAt", "daily?", "links": [{block,
doc, target?, text}], "tags": [{tag, block, text}], "tasks": [{block, text, checked, due?}], "blocks":
[{id, text, heading?}]}}}`. An entry is current when its `updatedAt` and `daily` equal the document's
metadata; anything else is re-indexed from `docs/`. Building the index never writes a document.
Block `text` keeps up to 1,000 characters (version 2; version 1 kept 200, so a version-1 index is
rebuilt on launch).

`cover.crop` is the visible part of the original image, normalized to 0…1 of its width and height
(absent: a 3:1 band centered on `focalY`). `cover.ratio` is the user's choice (`original`, `16:9`,
`2:1`, `3:1`, `4:3`, `free`).

### Appearance tokens

`backdrop {kind: none|solid|gradient|image, color, from, to, angle, image, blur, effect: immersive|faded}`,
`pageColor`, `textColor`, `accent`, `font: system|serif|mono|rounded`, `separator: line|dotted|tape|wave`,
`shellTint`. Built-in style ids: `paper`, `tidepool`, `ember`, `meadow`, `citrus`, `nightink`,
`typewriter`. Scenic image ids (`lagoon`, `dusk`, `meadow`, `ridge`, `fog`, `night`) are vector scenes
defined by palettes in `Styles.swift`; `asset:<file>` refers to an uploaded backdrop.

## Export bundle

`<Title>/` with one `.md` per document (nested pages and `docLink` chips to exported documents linked
relatively; dates written as `yyyy-MM-dd`), `assets/`, and
`draft-export.json` (`{"format":"draft-export","formatVersion":1,"docs":[…],"metas":[…],"folders":[…],"styles":[…]}`) — the
lossless native copy. Importing it gives clashing document and folder ids new ones and rewrites every
reference (page cards, doc links, collection items). Markdown is CommonMark plus `==highlight==` and `- [ ]` tasks; `linkPreview`
becomes a plain `[title](url)` link.

Styled exports (v0.4): one `.html` per document with inline CSS from its style (or neutral with
"Use document style" off), `assets/`, and `backdrop.png` for scenic backdrops; PDF and PNG are
rendered from that HTML. A website export adds `index.html`, one page per document (nested pages
included) and `backdrops/`; every link between pages is relative and nothing loads from the network.
