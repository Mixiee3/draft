# Versions, schemas and migration

## Version numbers

- **Version** (`VERSION`, `CFBundleShortVersionString`): semantic, `MAJOR.MINOR.PATCH`.
  - PATCH: fixes only, no format change.
  - MINOR: features; may add optional fields to the vault (older Drafts ignore them).
  - MAJOR: a change an older Draft can't read (a schema bump that isn't backward compatible), or removing a feature.
  - Pre-1.0 (0.x), minor versions may still change formats, always with a migration and a backup.
- **Build** (`CFBundleVersion`): the commit count. Strictly increasing; the updater compares builds, never strings.
- **Channel** (`DraftChannel` in Info.plist): `stable`, `beta` or `development` (any local build).

## Channels

| Channel | Gets | Rules |
|---|---|---|
| Stable (default) | stable releases | Notarized, passed `scripts/release-check.sh`. |
| Beta | beta and stable | Same gates. May add a schema version; then the update shows a migration warning and makes a backup archive first. Switching to Beta asks for confirmation. |
| Development | everything | Local and test builds. Switching asks for confirmation. A development build never installs over a stable or beta Draft (the updater refuses it), and the test mode only exists in development builds. |

Going back from Beta to Stable is allowed, but a vault migrated by a newer schema stays at that schema
(see below); restore the backup archive made before the migration to go back fully.

## Supported schemas

| Draft | library.json schema | note schema |
|---|---|---|
| 0.1 – 0.4 | 1 | 1 |
| 0.5 – 0.10 | 2 | 1 |

`DraftCore/Model.swift` has the current numbers (`librarySchemaVersion`, `docSchemaVersion`). Every
older schema has a fixture in `Tests/Fixtures/vaults` and a migration test.

## Migration

1. Before migrating a file Draft writes the original to `backups/<time>-library.vN.json` (or
   `<time>-doc-<id>.vN.json`), then writes the migrated file atomically. An unreadable file is kept as
   `backups/<time>-library.unreadable.json` and never overwritten. Settings › Recovery › Migration checks
   a vault against the current schema without writing.
2. An update that raises the schema says so in the update sheet, and Draft writes a full backup archive
   (`~/Documents/Draft Backups`) before installing it.
3. Migrations only add or rename fields; note text and block ids are never rewritten.

## Older and newer

- **Newer Draft, older vault:** migrated on open as above.
- **Older Draft, newer vault:** opened **read-only** with a notice ("written by a newer Draft"); nothing is
  written, so nothing is lost. Update Draft, or restore the pre-migration backup archive with the older Draft.
- **Unknown fields** written by a newer minor version are kept when an older Draft of the same schema saves.

## Rollback

- The updater keeps the previous app in `~/Library/Application Support/Draft/Updates/previous` and puts it
  back if the new version doesn't start within 40 s ([UPDATES.md](UPDATES.md)).
- Going back a schema: restore the backup archive made before the migrating update (Settings › Data & Storage › Backup Archive).

## Deprecation

A feature or format is marked deprecated in the release notes at least one minor version before it is
removed, and its data is migrated, never dropped. Removals happen only in a MAJOR version.
