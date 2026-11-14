# Contributing to Draft

Thanks for helping. Draft is a native macOS notes app: your notes are plain files you own, nothing
leaves the Mac unless a person turns on a feature that needs the network, and there is no telemetry.
Keep those rules in every change.

## Before you start

- Open an issue first for anything larger than a small fix, so we can agree on the approach.
- Read [docs/FORMAT.md](docs/FORMAT.md) before touching anything that reads or writes a vault. A vault
  made by one version must keep opening in the next.
- Read [docs/VERSIONING.md](docs/VERSIONING.md) for schema and migration rules.

## Setup

- macOS 14 or later, Xcode command-line tools, Swift 6.
- Build: `scripts/build-app.sh` (writes `build/Draft.app`). Use `JOBS=2` on machines with little memory.
- Tests: `swift test -j 2`.

## Ground rules

- **Throwaway vaults only.** Every test and every script uses a temporary folder through
  `DRAFT_DATA_DIR`. Never test against your own vault.
- **No secrets in the repo.** Signing certificates, update keys (`*.key`, `*.p12`, `*.p8`), tokens and
  personal notes must never be committed. `.gitignore` covers the usual names; check `git status` before you commit.
- **No new network calls** without a visible, user-initiated trigger and a note in
  [docs/PRIVACY.md](docs/PRIVACY.md).
- **Accessibility and localization.** New controls need accessibility labels, and user-facing strings go
  through `Localization/Localizable.xcstrings` (English, Czech, German). See `scripts/l10n-check.sh`.
- **Tests go with the change.** Logic changes need a unit test in `Tests/`; UI or behaviour changes need
  the matching script (`scripts/smoke.sh`, `scripts/trust-test.sh` and so on) to still pass.

## Pull requests

1. Branch from `main`, keep the change focused, and write a clear commit message in the imperative.
2. Run `swift test -j 2` and the scripts that touch your area.
3. Describe what changed, why, and how you tested it. Add screenshots for visible changes (light and dark).
4. Maintainers will review; expect questions, not rejection, for reasonable changes.

## Reporting bugs

Use the bug report template. Help › Report a Problem creates a local report you can review before sharing.
It never includes note text, titles or paths. Please don't attach your vault or notes.

## Conduct

Everyone taking part follows the [Code of Conduct](CODE_OF_CONDUCT.md).
