Vaults in every schema Draft has written, for `MigrationFixtureTests`.

- `v0` — pre-release prototype: library without `schemaVersion`, documents as an array; a document
  without `schemaVersion`, `appearance` or times. Carries an unknown field that must survive.
- `v1` — library schema 1 (one Space, documents keyed by id), documents schema 1, with a folder, a
  nested page, a link and a block reference.
- `v2` — library schema 2 (Spaces), the current format.
