# Privacy

Draft is offline by default. Your notes are files in a folder you own; nothing about you or your notes
leaves the Mac unless you turn on a feature that needs the network, and each one says what it sends.
Settings › Privacy lists all of this live, with a button to each setting.

## Data

| What | Where | Notes |
|---|---|---|
| Vault (notes, attachments, versions, backups) | `~/Library/Application Support/Draft/Vault` (Settings › Data & Storage shows and moves it) | Plain JSON and files, documented in [FORMAT.md](FORMAT.md). |
| Backup archives | `~/Documents/Draft Backups` or where you choose | One `.zip` with a checksummed manifest. |
| Log | `~/Library/Logs/Draft/draft.log` (1 MB, one rotation) | Launch, quit, errors: ids and counts, never note text, titles or paths. |
| Session marker | `~/Library/Application Support/Draft/session.json` | Start time and last save time, to notice a crash. |
| Update work folder | `~/Library/Application Support/Draft/Updates` | The previous app, kept for rollback. |
| OpenAI API key | Keychain | Only if you add one. |

**Telemetry: none.** No analytics, crash upload or usage pings exist in Draft.

**Encryption:** Draft relies on FileVault (Settings › Privacy shows whether it's on). Notes aren't separately encrypted.

## Network features (all off until you turn them on)

| Feature | Sends | Turn off |
|---|---|---|
| Update checks | An HTTPS GET of the update list and, if you download, the archive. Nothing about you. | Settings › Updates (automatic checks are off by default; manual checks only when you click). |
| Online image search | Your search words to the image provider. | Settings › Advanced. |
| Link previews | A request to the pasted link's site. | Settings › Advanced. |
| Assistant with OpenAI | The question and the note excerpts you approve, to OpenAI with your key. | Settings › Assistant › Provider: On this Mac. |
| Assistant model download | A download of the model file, only after you click Download. | Don't download; delete it in Settings › Assistant. |

The local Assistant runs on the Mac and sends nothing.

## Local permissions

| Permission | Why | Turn off |
|---|---|---|
| MCP agents | Local AI agents read through Draft's tools and propose changes you approve; they never write note files directly. | Settings › Agents (per-agent permissions). |
| Notifications | Reminders for dated tasks. | System Settings › Notifications › Draft. |
| Calendar | Shows your events next to daily notes, only if you turn it on; never changes events. | Settings › Daily Notes, or System Settings › Privacy & Security › Calendars. |
| Microphone | Dictation to the Assistant, only while you dictate. | System Settings › Privacy & Security › Microphone. |

## Report a Problem

Help › Report a Problem writes a **local** text file you review before saving: app and macOS versions,
a performance summary, vault counts, and (if you tick it) recent log lines and a window screenshot.
Paths become `~`, your note titles become `‹title›`, and no note text is included. Nothing is sent;
you decide whether to attach the file anywhere.
