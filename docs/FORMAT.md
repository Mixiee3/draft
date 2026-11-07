# Draft vault format (schema 1)

Schema 1 grows only by **additive** node types and optional attributes. A Draft that does not know
a node type keeps it verbatim and shows it as a preserved placeholder, so older builds never lose
newer content; the schema number changes only for changes that need a migration.

This is the contract every Draft implementation (macOS today, Windows later) reads and writes.
The reference implementation is `Sources/DraftCore`. All JSON is UTF‑8; timestamps are Unix epoch
**milliseconds**; ids are `[A-Za-z0-9_-]{1,64}`.

```
<vault>/
  library.json            index (schemaVersion, space, folders, docs, settings, tabs)
  docs/<docId>.json       one document
  assets/<sha256-32>.<ext> images, covers and attached files, content-addressed (extension: 1–10 lowercase letters/digits)
  backups/                copies written before any migration (never read by the app)
```

## Rules for every implementation

1. **Atomic writes**: write a temp file in the same directory, then rename.
2. **Never drop unknown data**: unknown top-level keys of `library.json` / document files, unknown
   node types and unknown attributes must be written back unchanged.
3. **Schema versions**: if `schemaVersion` is higher than supported, open read-only and refuse to
   write. When migrating, write the original into `backups/` first.
4. **Block ids** are stable. On load, a block without an id or with a duplicate id gets a new one;
   the first occurrence of an id always keeps it.

## library.json

```json
{
  "schemaVersion": 1,
  "space": { "id": "s_…", "name": "My Space" },
  "folders": [{ "id": "f_…", "name": "Getting Started", "parentId": null, "color": "#5b6cf0", "order": 0, "createdAt": 0 }],
  "docs": { "d_…": { "id": "d_…", "title": "…", "folderId": "f_…", "parentDocId": null,
                     "createdAt": 0, "updatedAt": 0, "viewedAt": 0, "starred": false, "styleId": "paper",
                     "excerpt": "…", "searchText": "…", "words": 0, "blocks": 0, "tint": "#…" } },
  "settings": { "theme": "system", "accent": "#5b6cf0", "useDocStyleForApp": true, "…": "…" },
  "tabs": [{ "id": "t_…", "view": { "kind": "all" } }, { "id": "t_…", "view": { "kind": "doc", "docId": "d_…" } }],
  "activeTabId": "t_…",
  "expandedFolders": ["f_…"]
}
```

`excerpt`, `searchText`, `words`, `blocks`, `tint` are **derived** and may be rebuilt from the
document files at any time. `parentDocId` marks a nested page.

## docs/&lt;id&gt;.json

```json
{
  "schemaVersion": 1, "id": "d_…", "title": "Welcome", "createdAt": 0, "updatedAt": 0,
  "appearance": { "styleId": "tidepool", "overrides": { "pageColor": "#ffffff" }, "cover": { "assetId": "….png", "focalY": 0.5 } },
  "content": { "type": "doc", "content": [ … nodes … ] }
}
```

### Nodes (ProseMirror-style JSON: `type`, `attrs`, `content`, `marks`, `text`)

| type | attrs | content |
|---|---|---|
| `paragraph` | `id`, `variant?`=`"caption"`, `blockColor?`, `decoration?` (`focus`/`block`), `textAlign?` | inline |
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
| `pageCard` | `id`, `docId`, `title` (cached), `presentation` (`card`/`page`) | — |
| `text` | — | `text`, `marks?` |
| `hardBreak` | — | — |

Marks: `bold`, `italic`, `underline`, `strike`, `code`, `highlight {color}`, `textStyle {color}`,
`link {href}`.

### Appearance tokens

`backdrop {kind: none|solid|gradient|image, color, from, to, angle, image, blur, effect: immersive|faded}`,
`pageColor`, `textColor`, `accent`, `font: system|serif|mono|rounded`, `separator: line|dotted|tape|wave`,
`shellTint`. Built-in style ids: `paper`, `tidepool`, `ember`, `meadow`, `citrus`, `nightink`,
`typewriter`. Scenic image ids (`lagoon`, `dusk`, `meadow`, `ridge`, `fog`, `night`) are vector scenes
defined by palettes in `Styles.swift`; `asset:<file>` refers to an uploaded backdrop.

## Export bundle

`<Title>/` with one `.md` per document (nested pages linked relatively), `assets/`, and
`draft-export.json` (`{"format":"draft-export","formatVersion":1,"docs":[…],"metas":[…]}`) — the
lossless native copy. Markdown is CommonMark plus `==highlight==` and `- [ ]` tasks.
